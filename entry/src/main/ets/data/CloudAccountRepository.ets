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
