import preferences from '@ohos.data.preferences';
import { RdbAccountRepository } from '../data/RdbAccountRepository';
import CloudAccountRepository from '../data/CloudAccountRepository';
import LedgerRepository from '../data/LedgerRepository';
import CloudLedgerRepository from '../data/CloudLedgerRepository';
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
import { LedgerCloud } from '../models/cloud/LedgerCloud';
import { LedgerRecordCloud } from '../models/cloud/LedgerRecordCloud';
import { Ledger, LedgerRecord } from '../models/ledger/Ledger';
import CategoryStore from '../models/accountType/CategoryStore';
import BillStore from '../common/BillStore';
import LedgerStore from '../common/LedgerStore';
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
  // 登录瞬间云端令牌可能未就绪导致首同步失败：延迟自动重试的上限与基础间隔
  private static readonly MAX_SYNC_RETRY: number = 3;
  private static readonly SYNC_RETRY_BASE_MS: number = 2000;
  private syncing: boolean = false;
  private lastSyncAt: number = 0;
  private syncFailCount: number = 0;
  private localRepo: RdbAccountRepository = new RdbAccountRepository();
  private ledgerRepo: LedgerRepository = new LedgerRepository();

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
      // 墓碑先于数据合并：账单与账本共用一份已合并的墓碑集
      const tombstones = await this.mergeTombstones();
      await this.syncBills(uid, tombstones);
      await this.syncLedgers(uid, tombstones);
      this.lastSyncAt = Date.now();
      this.syncFailCount = 0;
      Logger.debug('端云全量同步完成');
    } catch (err) {
      Logger.error('端云全量同步失败', (err as Error).message);
      this.scheduleSyncRetry();
    } finally {
      this.syncing = false;
    }
  }

  /**
    * 同步失败后延迟自动重试（2s/4s/6s 递增，最多3次）：
    * 登录/启动后首次同步常因云端令牌未就绪失败，重试期间账单恢复无需重启应用；
    * 重试耗尽后停止，等下次回前台或登录触发
    */
  private scheduleSyncRetry(): void {
    if (this.syncFailCount >= CloudSyncService.MAX_SYNC_RETRY) {
      return;
    }
    this.syncFailCount += 1;
    const delay = this.syncFailCount * CloudSyncService.SYNC_RETRY_BASE_MS;
    setTimeout(() => {
      this.syncAll(true).catch((): void => {
      });
    }, delay);
  }

  /**
   * 合并云端与本地的删除墓碑：双向补齐，返回合并后的墓碑 id 集。
   * 账单/账本/账本记录共用（账本与记录的墓碑 id 带 LEDGER 前缀区分类型）
   */
  private async mergeTombstones(): Promise<Set<string>> {
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
    return tombstones;
  }

  /**
   * 账单与删除墓碑的合并同步
   */
  private async syncBills(uid: string, tombstones: Set<string>): Promise<void> {
    // 1. 拉取云端账单与本地全量账单，按主键合并：create_time 新者胜
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
   * 账本与账本记录的合并同步：按主键合并，updated_at 新者胜；
   * 墓碑中的账本/记录不落地不复活，云端残留行兜底删除
   */
  private async syncLedgers(uid: string, tombstones: Set<string>): Promise<void> {
    // 按前缀拆分墓碑：账本墓碑与记录墓碑分别比对
    const ledgerTombstones = new Set<string>();
    const recordTombstones = new Set<string>();
    for (const id of tombstones) {
      if (id.startsWith(CONSTANTS.LEDGER_TOMBSTONE_PREFIX)) {
        ledgerTombstones.add(id.substring(CONSTANTS.LEDGER_TOMBSTONE_PREFIX.length));
      } else if (id.startsWith(CONSTANTS.LEDGER_RECORD_TOMBSTONE_PREFIX)) {
        recordTombstones.add(id.substring(CONSTANTS.LEDGER_RECORD_TOMBSTONE_PREFIX.length));
      }
    }

    const cloudLedgers = await CloudLedgerRepository.queryLedgers(uid);
    const cloudRecords = await CloudLedgerRepository.queryRecords(uid);
    const localLedgers = await this.ledgerRepo.queryLedgers();
    const localRecords = await this.ledgerRepo.queryAllRecords();

    const cloudLedgerMap = new Map<string, LedgerCloud>();
    for (const item of cloudLedgers) {
      cloudLedgerMap.set(item.id, item);
    }
    const localLedgerMap = new Map<string, Ledger>();
    for (const item of localLedgers) {
      localLedgerMap.set(item.id, item);
    }
    const cloudRecordMap = new Map<string, LedgerRecordCloud>();
    for (const item of cloudRecords) {
      cloudRecordMap.set(item.id, item);
    }
    const localRecordMap = new Map<string, LedgerRecord>();
    for (const item of localRecords) {
      localRecordMap.set(item.id, item);
    }

    let localChanged = false;

    // 1. 云端 → 本地：账本按 updated_at 新者胜落地
    for (const cloud of cloudLedgers) {
      if (ledgerTombstones.has(cloud.id)) {
        continue;
      }
      const local = localLedgerMap.get(cloud.id);
      if (!local || cloud.update_time > local.updatedAt) {
        await this.ledgerRepo.upsertLedger(CloudLedgerRepository.toLocalLedger(cloud));
        localChanged = true;
      }
    }

    // 2. 云端 → 本地：账本记录按 updated_at 新者胜落地；
    //    所属账本已删（在墓碑中）的记录不落地，避免恢复出孤儿记录
    for (const cloud of cloudRecords) {
      if (recordTombstones.has(cloud.id) || ledgerTombstones.has(cloud.ledger_id)) {
        continue;
      }
      const local = localRecordMap.get(cloud.id);
      if (!local || cloud.update_time > local.updatedAt) {
        await this.ledgerRepo.upsertRecord(CloudLedgerRepository.toLocalRecord(cloud));
        localChanged = true;
      }
    }

    // 3. 本地 → 云端：云端缺失或本地更新的补推
    const toUpsertLedgers: Ledger[] = [];
    for (const local of localLedgers) {
      if (ledgerTombstones.has(local.id)) {
        continue;
      }
      const cloud = cloudLedgerMap.get(local.id);
      if (!cloud || local.updatedAt > cloud.update_time) {
        toUpsertLedgers.push(local);
      }
    }
    if (toUpsertLedgers.length > 0) {
      await CloudLedgerRepository.upsertLedgers(toUpsertLedgers, uid);
    }
    const toUpsertRecords: LedgerRecord[] = [];
    for (const local of localRecords) {
      if (recordTombstones.has(local.id)) {
        continue;
      }
      const cloud = cloudRecordMap.get(local.id);
      if (!cloud || local.updatedAt > cloud.update_time) {
        toUpsertRecords.push(local);
      }
    }
    if (toUpsertRecords.length > 0) {
      await CloudLedgerRepository.upsertRecords(toUpsertRecords, uid);
    }

    // 4. 墓碑兜底：云端残留的已删账本/记录再删一次（其他设备同步期间可能推回）
    for (const cloud of cloudLedgers) {
      if (ledgerTombstones.has(cloud.id)) {
        await CloudLedgerRepository.deleteLedgerById(cloud.id);
      }
    }
    for (const cloud of cloudRecords) {
      if (recordTombstones.has(cloud.id) || ledgerTombstones.has(cloud.ledger_id)) {
        await CloudLedgerRepository.deleteRecordById(cloud.id);
      }
    }
    // 本地残留的已删账本/记录删除
    for (const id of ledgerTombstones) {
      if (localLedgerMap.has(id)) {
        await this.ledgerRepo.localDeleteLedger(id);
        localChanged = true;
      }
    }
    for (const id of recordTombstones) {
      if (localRecordMap.has(id)) {
        await this.ledgerRepo.localDeleteRecord(id);
        localChanged = true;
      }
    }

    if (localChanged) {
      LedgerStore.notifyChanged();
    }
  }

  /**
   * 清空全部账单数据（隐私页）：账单与账本记录做三清——本地行、云端行、删除墓碑，
   * 墓碑覆盖本地与云端 id 并集，任何设备同步时都不再复活；
   * 账本结构、分类、预算、学习记忆与设置不受影响
   */
  async clearAllBillsData(): Promise<void> {
    // 与 syncAll 互斥：清空与同步并发执行时，同步可能把清空前的快照推回云端或与墓碑写入交错
    if (this.syncing) {
      throw new Error('sync_in_progress');
    }
    this.syncing = true;
    try {
      await this.doClearAllBillsData();
    } finally {
      this.syncing = false;
    }
  }

  private async doClearAllBillsData(): Promise<void> {
    const attached = CloudSettingSync.isAttached();
    const uid = CloudSettingSync.getUid();
    // 1. 收集本地与云端全部账单/账本记录 id
    const localBills = await this.localRepo.queryAll();
    const localRecords = await this.ledgerRepo.queryAllRecords();
    let cloudBillIds: string[] = [];
    let cloudRecordIds: string[] = [];
    if (attached) {
      const cloudBills = await CloudAccountRepository.queryAll(uid);
      cloudBillIds = cloudBills.map((item: AccountCloud): string => item.id);
      const cloudRecords = await CloudLedgerRepository.queryRecords(uid);
      cloudRecordIds = cloudRecords.map((item: LedgerRecordCloud): string => item.id);
    }
    // 2. 写删除墓碑：本地列表 + 云端墓碑表（账本记录墓碑带前缀）
    const billIdSet = new Set<string>();
    for (const item of localBills) {
      billIdSet.add(item.id);
    }
    for (const id of cloudBillIds) {
      billIdSet.add(id);
    }
    const recordIdSet = new Set<string>();
    for (const item of localRecords) {
      recordIdSet.add(item.id);
    }
    for (const id of cloudRecordIds) {
      recordIdSet.add(id);
    }
    const tombIds: string[] = [];
    for (const id of billIdSet) {
      tombIds.push(id);
    }
    for (const id of recordIdSet) {
      tombIds.push(`${CONSTANTS.LEDGER_RECORD_TOMBSTONE_PREFIX}${id}`);
    }
    if (tombIds.length > 0) {
      await CloudSettingSync.recordBillDeletions(tombIds);
    }
    // 3. 删云端行
    if (attached) {
      if (cloudBillIds.length > 0) {
        await CloudAccountRepository.deleteAll(cloudBillIds);
      }
      if (cloudRecordIds.length > 0) {
        await CloudLedgerRepository.deleteRecordsByIds(cloudRecordIds);
      }
    }
    // 4. 删本地行
    if (localBills.length > 0) {
      await this.localRepo.deleteAll();
    }
    if (localRecords.length > 0) {
      await this.ledgerRepo.localDeleteAllRecords();
    }
    BillStore.notifyChanged();
    LedgerStore.notifyChanged();
  }

  /**
   * 设置与分类配置的合并同步
   */
  private async syncSettings(): Promise<void> {
    // 先排空在途推送链：快照 meta 前等推送的时间戳落盘，避免后面整体回写时覆盖
    await CloudSettingSync.drainChain();
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
    // 逐 key 取较大值合并落盘，不用旧快照整体覆盖：同步期间并发的设置推送时间戳不丢
    await CloudSettingSync.mergeMeta(meta);
  }

  private isThemeKey(key: string): boolean {
    return key === CONSTANTS.PREF_THEME_ID || key === CONSTANTS.PREF_COLOR_MODE ||
      key === CONSTANTS.PREF_FONT_SCALE || key === CONSTANTS.PREF_GLOW_LEVEL ||
      key === CONSTANTS.PREF_HOME_STAT_SCOPE || key === CONSTANTS.PREF_CUSTOM_THEME_PRIMARY;
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
