import { cloudDatabase } from '@kit.CloudFoundationKit';

/**
 * 用户设置云数据库客户端模型：字段名与 schema.json 的 user_setting 对象类型一致。
 * 每个设置键一行，id 为 "{owner_uid}:{setting_key}"，按 update_time 做新旧比较
 */
export class SettingCloud extends cloudDatabase.DatabaseObject {
  id: string = '';
  setting_key: string = '';
  setting_value: string = '';
  update_time: number = 0;
  owner_uid: string = '';

  naturalbase_ClassName(): string {
    return 'user_setting';
  }
}
