import { cloudDatabase } from '@kit.CloudFoundationKit';

/**
 * 账本记录云数据库客户端模型：字段名与 schema.json 的 ledger_record 对象类型一致
 */
export class LedgerRecordCloud extends cloudDatabase.DatabaseObject {
  id: string = '';
  ledger_id: string = '';
  type: number = 0;
  amount: number = 0;
  note: string = '';
  time: number = 0;
  created_at: number = 0;
  update_time: number = 0;
  category: number = 0;
  bill_id: string = '';
  owner_uid: string = '';

  naturalbase_ClassName(): string {
    return 'ledger_record';
  }
}
