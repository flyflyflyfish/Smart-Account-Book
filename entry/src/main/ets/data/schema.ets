/**
 * 数据库表结构定义
 */
export const ACCOUNT_TABLE_NAME: string = 'account';
export const MERCHANT_CATEGORY_TABLE_NAME: string = 'merchant_category';

/**
 * 当前数据库版本号：老库 version 为 0，升级后置为 2
 */
export const DB_VERSION: number = 2;

/**
 * 账单表建表语句（新装用户直接包含全部列）
 */
export const ACCOUNT_CREATE_TABLE_SQL: string = `
  CREATE TABLE IF NOT EXISTS account (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type INTEGER NOT NULL,
    account_type INTEGER NOT NULL,
    amount DOUBLE NOT NULL,
    create_time INTEGER NOT NULL,
    description STRING,
    time INTEGER NOT NULL,
    merchant TEXT DEFAULT '',
    source INTEGER DEFAULT 0,
    pay_time INTEGER DEFAULT 0
  )`;

/**
 * 商家-分类映射表：图片识别记账时按商家名智能匹配分类
 */
export const MERCHANT_CATEGORY_CREATE_TABLE_SQL: string = `
  CREATE TABLE IF NOT EXISTS merchant_category (
    merchant TEXT PRIMARY KEY,
    category_id INTEGER,
    account_type INTEGER,
    updated_at INTEGER
  )`;

/**
 * 老库（version < 2）迁移语句：仅补列，不清数据，保证升级后数据不丢失
 */
export const MIGRATE_1_TO_2_SQLS: string[] = [
  `ALTER TABLE account ADD COLUMN merchant TEXT DEFAULT ''`,
  `ALTER TABLE account ADD COLUMN source INTEGER DEFAULT 0`,
  `ALTER TABLE account ADD COLUMN pay_time INTEGER DEFAULT 0`
];
