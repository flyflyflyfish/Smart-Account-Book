import { cloudDatabase } from '@kit.CloudFoundationKit';
import { Ledger, LedgerRecord } from '../models/ledger/Ledger';
import { LedgerCloud } from '../models/cloud/LedgerCloud';
import { LedgerRecordCloud } from '../models/cloud/LedgerRecordCloud';
import CloudInit from './CloudInit';
import { Logger } from '../utils/Logger';

/**
 * 云端账本仓储：把本地账本/账本记录同步到云数据库，
 * 云端未初始化或失败时静默忽略，不影响本地
 */
class CloudLedgerRepository {
  private ledgerToCloud(ledger: Ledger, ownerUid: string): LedgerCloud {
    const cloud = new LedgerCloud();
    cloud.id = ledger.id;
    cloud.name = ledger.name;
    cloud.color_key = ledger.colorKey;
    cloud.created_at = ledger.createdAt;
    cloud.update_time = ledger.updatedAt;
    cloud.owner_uid = ownerUid;
    return cloud;
  }

  private recordToCloud(record: LedgerRecord, ownerUid: string): LedgerRecordCloud {
    const cloud = new LedgerRecordCloud();
    cloud.id = record.id;
    cloud.ledger_id = record.ledgerId;
    cloud.type = record.type;
    cloud.amount = record.amount;
    cloud.note = record.note;
    cloud.time = record.time;
    cloud.created_at = record.createdAt;
    cloud.update_time = record.updatedAt;
    cloud.category = record.category;
    cloud.bill_id = record.billId;
    cloud.owner_uid = ownerUid;
    return cloud;
  }

  async upsertLedger(ledger: Ledger, ownerUid: string): Promise<void> {
    const zone = CloudInit.getZone();
    if (!zone) {
      return;
    }
    try {
      await zone.upsert(this.ledgerToCloud(ledger, ownerUid));
    } catch (err) {
      Logger.error('云端同步账本失败', (err as Error).message);
    }
  }

  async upsertRecord(record: LedgerRecord, ownerUid: string): Promise<void> {
    const zone = CloudInit.getZone();
    if (!zone) {
      return;
    }
    try {
      await zone.upsert(this.recordToCloud(record, ownerUid));
    } catch (err) {
      Logger.error('云端同步账本记录失败', (err as Error).message);
    }
  }

  /** 批量上传账本/记录（原子写入），供全量同步补推；分批规避单次条数/大小限制 */
  async upsertLedgers(ledgers: Ledger[], ownerUid: string): Promise<void> {
    await this.upsertInBatches<Ledger, LedgerCloud>(ledgers, ownerUid,
      (item: Ledger, uid: string): LedgerCloud => this.ledgerToCloud(item, uid));
  }

  async upsertRecords(records: LedgerRecord[], ownerUid: string): Promise<void> {
    await this.upsertInBatches<LedgerRecord, LedgerRecordCloud>(records, ownerUid,
      (item: LedgerRecord, uid: string): LedgerRecordCloud => this.recordToCloud(item, uid));
  }

  // 云数据库单次 upsert 限制：总条数 <= 1000、总大小 <= 2MB，按 100 条一批留足余量
  private async upsertInBatches<T, C extends cloudDatabase.DatabaseObject>(items: T[], ownerUid: string,
    mapper: (item: T, ownerUid: string) => C): Promise<void> {
    const zone = CloudInit.getZone();
    if (!zone || items.length === 0) {
      return;
    }
    const BATCH_SIZE = 100;
    for (let start = 0; start < items.length; start += BATCH_SIZE) {
      const end = Math.min(start + BATCH_SIZE, items.length);
      const slice = items.slice(start, end);
      try {
        const clouds = slice.map((item: T): C => mapper(item, ownerUid));
        await zone.upsert(clouds);
      } catch (err) {
        Logger.error('云端批量同步账本数据失败', (err as Error).message);
      }
    }
  }

  /** 拉取指定用户在云端的全部账本 */
  async queryLedgers(ownerUid: string): Promise<LedgerCloud[]> {
    const zone = CloudInit.getZone();
    if (!zone) {
      return [];
    }
    try {
      const condition = new cloudDatabase.DatabaseQuery(LedgerCloud);
      condition.equalTo('owner_uid', ownerUid);
      return await zone.query(condition);
    } catch (err) {
      Logger.error('云端拉取账本失败', (err as Error).message);
      return [];
    }
  }

  /** 拉取指定用户在云端的全部账本记录 */
  async queryRecords(ownerUid: string): Promise<LedgerRecordCloud[]> {
    const zone = CloudInit.getZone();
    if (!zone) {
      return [];
    }
    try {
      const condition = new cloudDatabase.DatabaseQuery(LedgerRecordCloud);
      condition.equalTo('owner_uid', ownerUid);
      return await zone.query(condition);
    } catch (err) {
      Logger.error('云端拉取账本记录失败', (err as Error).message);
      return [];
    }
  }

  /** 云端模型映射回本地账本模型 */
  toLocalLedger(cloud: LedgerCloud): Ledger {
    const ledger = new Ledger();
    ledger.id = cloud.id;
    ledger.name = cloud.name;
    ledger.colorKey = cloud.color_key;
    ledger.createdAt = cloud.created_at;
    ledger.updatedAt = cloud.update_time;
    return ledger;
  }

  /** 云端模型映射回本地账本记录模型 */
  toLocalRecord(cloud: LedgerRecordCloud): LedgerRecord {
    const record = new LedgerRecord();
    record.id = cloud.id;
    record.ledgerId = cloud.ledger_id;
    record.type = cloud.type;
    record.amount = cloud.amount;
    record.note = cloud.note;
    record.time = cloud.time;
    record.createdAt = cloud.created_at;
    record.updatedAt = cloud.update_time;
    record.category = cloud.category;
    record.billId = cloud.bill_id;
    return record;
  }

  // 云数据库按主键删除账本行，只需填充 id
  async deleteLedgerById(id: string): Promise<void> {
    const zone = CloudInit.getZone();
    if (!zone) {
      return;
    }
    try {
      const cloud = new LedgerCloud();
      cloud.id = id;
      await zone.delete(cloud);
    } catch (err) {
      Logger.error('云端删除账本失败', (err as Error).message);
    }
  }

  // 云数据库按主键删除账本记录行
  async deleteRecordById(id: string): Promise<void> {
    const zone = CloudInit.getZone();
    if (!zone) {
      return;
    }
    try {
      const cloud = new LedgerRecordCloud();
      cloud.id = id;
      await zone.delete(cloud);
    } catch (err) {
      Logger.error('云端删除账本记录失败', (err as Error).message);
    }
  }

  /** 按主键批量删除云端账本记录，按 100 条一批规避云数据库单次条数/大小限制 */
  async deleteRecordsByIds(ids: string[]): Promise<void> {
    const zone = CloudInit.getZone();
    if (!zone || ids.length === 0) {
      return;
    }
    const BATCH_SIZE = 100;
    for (let start = 0; start < ids.length; start += BATCH_SIZE) {
      const end = Math.min(start + BATCH_SIZE, ids.length);
      const clouds: LedgerRecordCloud[] = [];
      for (let index = start; index < end; index++) {
        const cloud = new LedgerRecordCloud();
        cloud.id = ids[index];
        clouds.push(cloud);
      }
      try {
        await zone.delete(clouds);
      } catch (err) {
        Logger.error('云端批量删除账本记录失败', (err as Error).message);
      }
    }
  }
}

export default new CloudLedgerRepository();
