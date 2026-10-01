import { cloudDatabase } from '@kit.CloudFoundationKit';

/**
 * 账单云数据库客户端模型：字段名与 schema.json 的 objectType 字段一致
 */
export class AccountCloud extends cloudDatabase.DatabaseObject {
  id: string = '';
  type: number = 0;
  account_type: number = 0;
  amount: number = 0;
  create_time: number = 0;
  description: string = '';
  time: number = 0;
  merchant: string = '';
  source: number = 0;
  pay_time: number = 0;
  owner_uid: string = '';

  naturalbase_ClassName(): string {
    return 'account';
  }
}
