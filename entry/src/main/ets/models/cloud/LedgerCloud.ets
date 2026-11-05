import { cloudDatabase } from '@kit.CloudFoundationKit';

/**
 * 账本云数据库客户端模型：字段名与 schema.json 的 ledger 对象类型一致
 */
export class LedgerCloud extends cloudDatabase.DatabaseObject {
  id: string = '';
  name: string = '';
  color_key: string = '';
  created_at: number = 0;
  update_time: number = 0;
  owner_uid: string = '';

  naturalbase_ClassName(): string {
    return 'ledger';
  }
}
