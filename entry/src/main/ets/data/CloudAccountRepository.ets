import { cloudDatabase } from '@kit.CloudFoundationKit';
import AccountPO from '../models/account/accountPO';
import { AccountCloud } from '../models/cloud/AccountCloud';
import CloudInit from './CloudInit';
import { Logger } from '../utils/Logger';

/**
 * 云端账单仓储：把本地账单同步到云数据库，云端未初始化或失败时静默忽略，不影响本地
 */
class CloudAccountRepository {
  // 本地 PO 映射为云端客户端模型，owner_uid 由登录用户 uid 填充
  private toCloud(record: AccountPO, ownerUid: string): AccountCloud {
    const cloud = new AccountCloud();
    cloud.id = record.id;
    cloud.type = record.type;
    cloud.account_type = record.accountType;
    cloud.amount = record.amount;
    cloud.create_time = record.createTime;
    cloud.description = record.description;
    cloud.time = record.time;
    cloud.merchant = record.merchant;
    cloud.source = record.source;
    cloud.pay_time = record.payTime;
    cloud.owner_uid = ownerUid;
    return cloud;
  }

  async upsert(record: AccountPO, ownerUid: string): Promise<void> {
    const zone = CloudInit.getZone();
    if (!zone) {
      return;
    }
    try {
      await zone.upsert(this.toCloud(record, ownerUid));
    } catch (err) {
      const e = err as Error;
      Logger.error('云端同步账单失败', e.message);
    }
  }

  /** 批量上传本地账单到云端（原子写入），供全量同步补推本地新增账单；分批规避单次条数/大小限制 */
  async upsertAll(records: AccountPO[], ownerUid: string): Promise<void> {
    const zone = CloudInit.getZone();
    if (!zone || records.length === 0) {
      return;
    }
    // 云数据库单次 upsert 限制：总条数 <= 1000、总大小 <= 2MB，按 100 条一批留足余量
    const BATCH_SIZE = 100;
    for (let start = 0; start < records.length; start += BATCH_SIZE) {
      const end = Math.min(start + BATCH_SIZE, records.length);
      const slice = records.slice(start, end);
      try {
        const clouds = slice.map((item: AccountPO): AccountCloud => this.toCloud(item, ownerUid));
        await zone.upsert(clouds);
      } catch (err) {
        const e = err as Error;
        Logger.error('云端批量同步账单失败', e.message);
      }
    }
  }

  /** 拉取指定用户在云端的全部账单，供全量同步时合并回本地 */
  async queryAll(ownerUid: string): Promise<AccountCloud[]> {
    const zone = CloudInit.getZone();
    if (!zone) {
      return [];
    }
    try {
      const condition = new cloudDatabase.DatabaseQuery(AccountCloud);
      condition.equalTo('owner_uid', ownerUid);
      return await zone.query(condition);
    } catch (err) {
      const e = err as Error;
      Logger.error('云端拉取账单失败', e.message);
      return [];
    }
  }

  /** 云端模型映射回本地 PO，供恢复/合并时写入本地库 */
  toLocalPO(cloud: AccountCloud): AccountPO {
    const po = new AccountPO();
    po.id = cloud.id;
    po.type = cloud.type;
    po.accountType = cloud.account_type;
    po.amount = cloud.amount;
    po.createTime = cloud.create_time;
    po.description = cloud.description;
    po.time = cloud.time;
    po.merchant = cloud.merchant;
    po.source = cloud.source;
    po.payTime = cloud.pay_time;
    return po;
  }

  // 云数据库按主键删除，只需填充 id
  async deleteById(id: string): Promise<void> {
    const zone = CloudInit.getZone();
    if (!zone) {
      return;
    }
    try {
      const cloud = new AccountCloud();
      cloud.id = id;
      await zone.delete(cloud);
    } catch (err) {
      const e = err as Error;
      Logger.error('云端删除账单失败', e.message);
    }
  }
}

export default new CloudAccountRepository();
