import { cloudDatabase } from '@kit.CloudFoundationKit';

/**
 * 账单删除墓碑云数据库客户端模型：字段名与 schema.json 的 bill_tombstone 对象类型一致。
 * id 即被删除账单的 UUID；同步时先比对墓碑，墓碑中的账单不再落地/上传
 */
export class TombstoneCloud extends cloudDatabase.DatabaseObject {
  id: string = '';
  delete_time: number = 0;
  owner_uid: string = '';

  naturalbase_ClassName(): string {
    return 'bill_tombstone';
  }
}
