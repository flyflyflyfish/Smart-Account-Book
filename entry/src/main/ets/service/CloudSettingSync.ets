import preferences from '@ohos.data.preferences';
import { cloudDatabase } from '@kit.CloudFoundationKit';
import { SettingCloud } from '../models/cloud/SettingCloud';
import { TombstoneCloud } from '../models/cloud/TombstoneCloud';
import PreferenceUtil from '../utils/PreferenceUtil';
import { Logger } from '../utils/Logger';
import * as CONSTANTS from '../common/constants';

/**
 * 可同步设置项定义：键 + 值类型（拉取后按类型反序列化写回 Preferences）
 */
export class SyncableSettingDef {
  key: string;
  kind: string;

  constructor(key: string, kind: string) {
    this.key = key;
    this.kind = kind;
  }
}

/**
 * 参与端云同步的全部设置键。
 * 不同步的本地状态：多服务商 API 配置（含明文 API key，仅存本机）、
 * 训练采集开关（明确仅存本机）、小组件卡片列表（设备相关）、
 * 预算当月提醒标记（设备本地去重状态）、旧版单服务商三键（已被多服务商配置取代）
 */
export const SYNCABLE_SETTINGS: SyncableSettingDef[] = [
  new SyncableSettingDef(CONSTANTS.PREF_USER_FIRST_KEY, 'number'),
  new SyncableSettingDef(CONSTANTS.PREF_CLOUD_ACTIVE_PROVIDER, 'string'),
  new SyncableSettingDef(CONSTANTS.PREF_OCR_ENABLED, 'boolean'),
  new SyncableSettingDef(CONSTANTS.PREF_CLOUD_ENABLED, 'boolean'),
  new SyncableSettingDef(CONSTANTS.PREF_CLOUD_CONSENT, 'boolean'),
  new SyncableSettingDef(CONSTANTS.PREF_CATEGORY_CONFIG, 'string'),
  new SyncableSettingDef(CONSTANTS.PREF_BUDGET_ENABLED, 'boolean'),
  new SyncableSettingDef(CONSTANTS.PREF_BUDGET_LIMIT, 'number'),
  new SyncableSettingDef(CONSTANTS.PREF_RECURRING_BILLS, 'string'),
  new SyncableSettingDef(CONSTANTS.PREF_THEME_ID, 'string'),
  new SyncableSettingDef(CONSTANTS.PREF_COLOR_MODE, 'string'),
  new SyncableSettingDef(CONSTANTS.PREF_FONT_SCALE, 'number'),
  new SyncableSettingDef(CONSTANTS.PREF_GLOW_LEVEL, 'string'),
  new SyncableSettingDef(CONSTANTS.PREF_HOME_STAT_SCOPE, 'string'),
  new SyncableSettingDef(CONSTANTS.PREF_CUSTOM_THEME_COLOR, 'string')
];

/** 查询设置键的值类型；不在同步清单内返回 undefined */
export function findSyncableKind(key: string): string | undefined {
  const matched = SYNCABLE_SETTINGS.find((item: SyncableSettingDef): boolean => item.key === key);
  return matched ? matched.kind : undefined;
}

/** 设置值序列化为云端文本：布尔转 true/false，其余转十进制文本 */
export function serializeSettingValue(value: preferences.ValueType): string {
  if (typeof value === 'boolean') {
    return value ? 'true' : 'false';
  }
  return String(value);
}

/** 云端文本按设置类型反序列化，非法数字回退 0 */
export function deserializeSettingValue(kind: string, text: string): preferences.ValueType {
  if (kind === 'boolean') {
    return text === 'true';
  }
  if (kind === 'number') {
    const parsed = Number(text);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return text;
}

/**
 * 设置与删除墓碑的端云同步底座：
 * - 登录成功后由 CloudInit 注入云存储区与用户 uid（attach），此后设置变更即时上传
 * - 未登录时仅记录本地变更时间（meta），登录后的全量同步会发现本地更新并补推
 * - 不依赖 CloudInit/AuthService，避免被主题/分类等底层模块引用时产生循环依赖
 */
class CloudSettingSyncService {
  private zone: cloudDatabase.DatabaseZone | undefined = undefined;
  private ownerUid: string = '';
  // 推送串行链：避免并发的 meta 读改写互相覆盖
  private chain: Promise<void> = Promise.resolve();

  attach(zone: cloudDatabase.DatabaseZone, ownerUid: string): void {
    this.zone = zone;
    this.ownerUid = ownerUid;
  }

  // 退出登录时调用：清空同步辅助记录，避免换账号登录后旧时间戳/墓碑误伤新账号数据
  detach(): void {
    this.zone = undefined;
    this.ownerUid = '';
    PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_CLOUD_SYNC_META, '{}').catch((): void => {
      Logger.error('清空端云同步时间戳失败');
    });
    PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_CLOUD_TOMBSTONES, '[]').catch((): void => {
      Logger.error('清空端云删除墓碑失败');
    });
  }

  isAttached(): boolean {
    return this.zone !== undefined && this.ownerUid.length > 0;
  }

  getUid(): string {
    return this.ownerUid;
  }

  /**
   * 设置变更后调用：先记录本地变更时间，再异步上传云端。
   * 未登录仅记时间不上传；上传失败时下次全量同步发现本地更新会补推
   */
  pushSetting(key: string, value: preferences.ValueType): void {
    const kind = findSyncableKind(key);
    if (!kind) {
      return;
    }
    const text = serializeSettingValue(value);
    this.chain = this.chain.then((): Promise<void> => this.pushSettingText(key, text));
  }

  private async pushSettingText(key: string, text: string): Promise<void> {
    try {
      const now = Date.now();
      await this.updateMeta(key, now);
      const zone = this.zone;
      if (!zone || !this.ownerUid) {
        return;
      }
      const row = new SettingCloud();
      row.id = `${this.ownerUid}:${key}`;
      row.setting_key = key;
      row.setting_value = text;
      row.update_time = now;
      row.owner_uid = this.ownerUid;
      await zone.upsert(row);
    } catch (err) {
      Logger.error('云端同步设置失败', (err as Error).message);
    }
  }

  /** 全量同步专用：按指定时间上传一行设置（合并结果/本地新值），不更新 meta（由调用方维护） */
  async upsertSettingRow(key: string, text: string, updateTime: number): Promise<void> {
    const zone = this.zone;
    if (!zone || !this.ownerUid) {
      return;
    }
    const row = new SettingCloud();
    row.id = `${this.ownerUid}:${key}`;
    row.setting_key = key;
    row.setting_value = text;
    row.update_time = updateTime;
    row.owner_uid = this.ownerUid;
    await zone.upsert(row);
  }

  /** 按主键删除一行云端设置（清理早期版本误传的敏感配置） */
  async deleteSettingRow(rowId: string): Promise<void> {
    const zone = this.zone;
    if (!zone || !this.ownerUid) {
      return;
    }
    const row = new SettingCloud();
    row.id = rowId;
    await zone.delete([row]);
  }

  /** 拉取当前用户全部云端设置行 */
  async querySettings(): Promise<SettingCloud[]> {
    const zone = this.zone;
    if (!zone || !this.ownerUid) {
      return [];
    }
    try {
      const condition = new cloudDatabase.DatabaseQuery(SettingCloud);
      condition.equalTo('owner_uid', this.ownerUid);
      return await zone.query(condition);
    } catch (err) {
      Logger.error('云端拉取设置失败', (err as Error).message);
      return [];
    }
  }

  /** 拉取当前用户全部云端删除墓碑 */
  async queryTombstones(): Promise<TombstoneCloud[]> {
    const zone = this.zone;
    if (!zone || !this.ownerUid) {
      return [];
    }
    try {
      const condition = new cloudDatabase.DatabaseQuery(TombstoneCloud);
      condition.equalTo('owner_uid', this.ownerUid);
      return await zone.query(condition);
    } catch (err) {
      Logger.error('云端拉取删除墓碑失败', (err as Error).message);
      return [];
    }
  }

  /** 上传一条删除墓碑 */
  async upsertTombstone(billId: string): Promise<void> {
    const zone = this.zone;
    if (!zone || !this.ownerUid) {
      return;
    }
    const row = new TombstoneCloud();
    row.id = billId;
    row.delete_time = Date.now();
    row.owner_uid = this.ownerUid;
    await zone.upsert(row);
  }

  /**
   * 账单删除后调用：本地记录墓碑防复活，已登录时同时上传云端墓碑
   */
  async recordBillDeletion(billId: string): Promise<void> {
    await this.rememberLocalTombstone(billId);
    if (!this.isAttached()) {
      return;
    }
    try {
      await this.upsertTombstone(billId);
    } catch (err) {
      Logger.error('云端同步删除标记失败', (err as Error).message);
    }
  }

  /** 读取各设置最近一次本地变更时间 */
  async loadMeta(): Promise<Record<string, number>> {
    const raw = String(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_CLOUD_SYNC_META, ''));
    if (raw.length === 0) {
      return {};
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, number>;
      return parsed ? parsed : {};
    } catch (err) {
      return {};
    }
  }

  async saveMeta(meta: Record<string, number>): Promise<void> {
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_CLOUD_SYNC_META, JSON.stringify(meta));
  }

  async updateMeta(key: string, timestamp: number): Promise<void> {
    const meta = await this.loadMeta();
    meta[key] = timestamp;
    await this.saveMeta(meta);
  }

  /** 读取本地记录的删除墓碑 id 列表 */
  async loadLocalTombstones(): Promise<string[]> {
    const raw = String(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_CLOUD_TOMBSTONES, ''));
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as string[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (err) {
      return [];
    }
  }

  async saveLocalTombstones(list: string[]): Promise<void> {
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_CLOUD_TOMBSTONES, JSON.stringify(list));
  }

  private async rememberLocalTombstone(billId: string): Promise<void> {
    const list = await this.loadLocalTombstones();
    if (list.indexOf(billId) >= 0) {
      return;
    }
    list.push(billId);
    while (list.length > CONSTANTS.CLOUD_TOMBSTONE_MAX) {
      list.shift();
    }
    await this.saveLocalTombstones(list);
  }
}

export default new CloudSettingSyncService();
