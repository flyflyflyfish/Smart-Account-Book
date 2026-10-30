import preferences from '@ohos.data.preferences';
import { RdbAccountRepository } from '../data/RdbAccountRepository';
import CloudAccountRepository from '../data/CloudAccountRepository';
import CloudSettingSync, {
  SYNCABLE_SETTINGS,
  SyncableSettingDef,
  findSyncableKind,
  serializeSettingValue,
  deserializeSettingValue
} from './CloudSettingSync';
import AccountPO from '../models/account/accountPO';
import { AccountCloud } from '../models/cloud/AccountCloud';
import { SettingCloud } from '../models/cloud/SettingCloud';
import CategoryStore from '../models/accountType/CategoryStore';
import BillStore from '../common/BillStore';
import PreferenceUtil from '../utils/PreferenceUtil';
import MerchantLearningSync from './MerchantLearningSync';
import { ThemeKit, sanitizeFontScale, FONT_SCALE_DEFAULT } from '../common/theme/Theme';
import * as CONSTANTS from '../common/constants';
import { Logger } from '../utils/Logger';

/**
 * 端云全量同步服务：登录成功、应用启动（已登录）与回前台时触发，把本地与云端数据合并为最新：
 * - 账单：按主键合并，create_time 新者胜；本地新增补推云端，云端新增恢复本地
 * - 删除墓碑：双向补齐，墓碑中的账单不再落地/上传，防止已删账单复活
 * - 分类配置：并集合并（双方新增的自定义分类与隐藏记录都保留），分类 id 跨设备一致
 * - 其他设置：按 update_time 新者胜，云端值落地后重载主题等内存态
 */
class CloudSyncService {
  private syncing: boolean = false;
  private lastSyncAt: number = 0;
  private localRepo: RdbAccountRepository = new RdbAccountRepository();

  /**
   * 全量同步入口：重复触发时防重入，force=false 时按最小间隔节流
   */
  async syncAll(force: boolean = false): Promise<void> {
    if (this.syncing) {
      return;
    }
    if (!force && Date.now() - this.lastSyncAt < CONSTANTS.CLOUD_SYNC_MIN_INTERVAL_MS) {
      return;
    }
    if (!CloudSettingSync.isAttached()) {
      return;
    }
    this.syncing = true;
    try {
      const uid = CloudSettingSync.getUid();
      // 先同步设置/分类，再同步账单：账单恢复时分类已就绪，分类名能正确反查
      await this.syncSettings();
      await this.syncBills(uid);
      this.lastSyncAt = Date.now();
      Logger.debug('端云全量同步完成');
    } catch (err) {
      Logger.error('端云全量同步失败', (err as Error).message);
    } finally {
      this.syncing = false;
    }
  }

  /**
   * 账单与删除墓碑的合并同步
   */
  private async syncBills(uid: string): Promise<void> {
    // 1. 合并云端与本地的删除墓碑：双向补齐
    const cloudTombstones = await CloudSettingSync.queryTombstones();
    const localTombstones = await CloudSettingSync.loadLocalTombstones();
    const tombstones = new Set<string>();
    const cloudTombIds = new Set<string>();
    for (const item of cloudTombstones) {
      tombstones.add(item.id);
      cloudTombIds.add(item.id);
    }
    let localTombChanged = false;
    for (const id of localTombstones) {
      tombstones.add(id);
      if (!cloudTombIds.has(id)) {
        // 本地记录的删除还没到云端（如删除时离线），补传
        await CloudSettingSync.upsertTombstone(id);
      }
    }
    for (const item of cloudTombstones) {
      if (localTombstones.indexOf(item.id) < 0) {
        localTombstones.push(item.id);
        localTombChanged = true;
      }
    }
    if (localTombChanged) {
      await CloudSettingSync.saveLocalTombstones(localTombstones);
    }

    // 2. 拉取云端账单与本地全量账单，按主键合并：create_time 新者胜
    const cloudBills = await CloudAccountRepository.queryAll(uid);
    const localBills = await this.localRepo.queryAll();
    const cloudMap = new Map<string, AccountCloud>();
    for (const item of cloudBills) {
      cloudMap.set(item.id, item);
    }
    const localMap = new Map<string, AccountPO>();
    for (const item of localBills) {
      localMap.set(item.id, item);
    }

    let localChanged = false;
    const toUpsert: AccountPO[] = [];

    // 云端 → 本地：本地没有或云端更新的账单写入本地库
    for (const cloud of cloudBills) {
      if (tombstones.has(cloud.id)) {
        continue;
      }
      const local = localMap.get(cloud.id);
      if (!local || cloud.create_time > local.createTime) {
        await this.localRepo.upsert(CloudAccountRepository.toLocalPO(cloud));
        localChanged = true;
      }
    }

    // 本地 → 云端：云端没有或本地更新的账单补推
    for (const local of localBills) {
      if (tombstones.has(local.id)) {
        continue;
      }
      const cloud = cloudMap.get(local.id);
      if (!cloud || local.createTime > cloud.create_time) {
        toUpsert.push(local);
      }
    }
    if (toUpsert.length > 0) {
      await CloudAccountRepository.upsertAll(toUpsert, uid);
    }

    // 墓碑兜底：云端残留的已删账单再删一次（其他设备同步期间可能推回）
    for (const cloud of cloudBills) {
      if (tombstones.has(cloud.id)) {
        await CloudAccountRepository.deleteById(cloud.id);
      }
    }
    // 本地残留的已删账单删除
    for (const id of tombstones) {
      if (localMap.has(id)) {
        await this.localRepo.deleteById(id);
        localChanged = true;
      }
    }

    if (localChanged) {
      BillStore.notifyChanged();
    }
  }

  /**
   * 设置与分类配置的合并同步
   */
  private async syncSettings(): Promise<void> {
    const cloudRows = await CloudSettingSync.querySettings();
    const cloudMap = new Map<string, SettingCloud>();
    for (const row of cloudRows) {
      cloudMap.set(row.setting_key, row);
    }
    // 安全清理：早期版本曾把含明文 API key 的多服务商配置上传云端，发现残留行立即删除
    const legacyProvidersRow = cloudMap.get(CONSTANTS.PREF_CLOUD_PROVIDERS);
    if (legacyProvidersRow) {
      try {
        await CloudSettingSync.deleteSettingRow(legacyProvidersRow.id);
        Logger.info('已清理云端残留的API配置行');
      } catch (err) {
        Logger.error('清理云端残留的API配置失败', (err as Error).message);
      }
    }
    // 商家→分类学习记忆：本地 rdb 表与 user_setting 的 JSON 行并集合并（独立于通用设置流）
    const learningRow = cloudMap.get(CONSTANTS.PREF_MERCHANT_LEARNING);
    try {
      await MerchantLearningSync.syncAndPush(learningRow ? learningRow.setting_value : undefined);
    } catch (err) {
      Logger.error('学习记忆同步失败', (err as Error).message);
    }
    const meta = await CloudSettingSync.loadMeta();
    let themeTouched = false;
    let budgetTouched = false;

    // 1. 云端 → 本地：云端变更时间晚于本地已知时间的才落地，避免旧值覆盖新值
    for (const row of cloudRows) {
      const kind = findSyncableKind(row.setting_key);
      if (!kind) {
        continue;
      }
      const localTs = meta[row.setting_key] ?? 0;
      if (row.update_time <= localTs) {
        continue;
      }
      if (row.setting_key === CONSTANTS.PREF_CATEGORY_CONFIG) {
        // 分类配置做并集合并：双方新增的自定义分类与隐藏记录都保留
        CategoryStore.mergeFromCloud(row.setting_value);
        const mergedJson = CategoryStore.getSnapshotJson();
        if (mergedJson !== row.setting_value) {
          // 合并结果含云端缺失的本地内容，推回云端让其他设备也能拿到
          const now = Date.now();
          await CloudSettingSync.upsertSettingRow(row.setting_key, mergedJson, now);
          meta[row.setting_key] = now;
        } else {
          meta[row.setting_key] = row.update_time;
        }
        continue;
      }
      const value = deserializeSettingValue(kind, row.setting_value);
      if (row.setting_key === CONSTANTS.PREF_FONT_SCALE && typeof value === 'number' &&
        sanitizeFontScale(value) !== value) {
        // 云端字号缩放为脏值（如 0，会把全部文字缩放为不可见）：本地回退默认并修复云端行
        const safeScale = sanitizeFontScale(value);
        await PreferenceUtil.putPreferenceValue(row.setting_key, safeScale);
        const healTime = Date.now();
        await CloudSettingSync.upsertSettingRow(row.setting_key, serializeSettingValue(safeScale), healTime);
        meta[row.setting_key] = healTime;
        themeTouched = true;
        Logger.info('已修复云端脏字号缩放值');
        continue;
      }
      await PreferenceUtil.putPreferenceValue(row.setting_key, value);
      if (this.isThemeKey(row.setting_key)) {
        themeTouched = true;
      }
      if (row.setting_key === CONSTANTS.PREF_BUDGET_ENABLED ||
        row.setting_key === CONSTANTS.PREF_BUDGET_LIMIT) {
        budgetTouched = true;
      }
      meta[row.setting_key] = row.update_time;
    }
    if (themeTouched) {
      // 云端主题偏好已写入 Preferences，重读四项并立即生效
      await ThemeKit.reloadSynced();
    }
    if (budgetTouched) {
      const version = AppStorage.get<number>('budgetVersion') ?? 0;
      AppStorage.setOrCreate('budgetVersion', version + 1);
    }

    // 2. 本地 → 云端：云端缺失或本地更新的设置上传
    for (const def of SYNCABLE_SETTINGS) {
      const cloudRow = cloudMap.get(def.key);
      const localTs = meta[def.key] ?? 0;
      if (cloudRow && localTs <= cloudRow.update_time) {
        continue;
      }
      const rawValue = def.key === CONSTANTS.PREF_CATEGORY_CONFIG
        ? CategoryStore.getSnapshotJson()
        : await PreferenceUtil.getPreferenceValue(def.key, this.defaultValueOf(def));
      const now = Date.now();
      await CloudSettingSync.upsertSettingRow(def.key, serializeSettingValue(rawValue), now);
      meta[def.key] = now;
    }
    await CloudSettingSync.saveMeta(meta);
  }

  private isThemeKey(key: string): boolean {
    return key === CONSTANTS.PREF_THEME_ID || key === CONSTANTS.PREF_COLOR_MODE ||
      key === CONSTANTS.PREF_FONT_SCALE || key === CONSTANTS.PREF_GLOW_LEVEL ||
      key === CONSTANTS.PREF_HOME_STAT_SCOPE || key === CONSTANTS.PREF_CUSTOM_THEME_COLOR;
  }

  private defaultValueOf(def: SyncableSettingDef): preferences.ValueType {
    if (def.key === CONSTANTS.PREF_OCR_ENABLED) {
      return true;
    }
    if (def.key === CONSTANTS.PREF_FONT_SCALE) {
      return FONT_SCALE_DEFAULT;
    }
    if (def.kind === 'boolean') {
      return false;
    }
    if (def.kind === 'number') {
      return 0;
    }
    return '';
  }
}

export default new CloudSyncService();
