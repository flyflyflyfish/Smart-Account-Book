/**
 * 数据库表结构定义
 */
export const ACCOUNT_TABLE_NAME: string = 'account';
export const MERCHANT_CATEGORY_TABLE_NAME: string = 'merchant_category';

/**
 * 当前数据库版本号：老库 version 为 0，升级后置为 3
 */
export const DB_VERSION: number = 3;

/**
 * 账单表建表语句（新装用户直接包含全部列，主键为 UUID 文本，便于端云同步）
 */
export const ACCOUNT_CREATE_TABLE_SQL: string = `
  CREATE TABLE IF NOT EXISTS account (
    id TEXT PRIMARY KEY,
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
 * 数据库迁移步骤：按 toVersion 升序逐级执行，避免跨版本直接跳级
 */
export interface MigrationStep {
  toVersion: number;
  sqls: string[];
}

/**
 * 老库（version < 2）迁移语句：仅补列，不清数据，保证升级后数据不丢失
 */
export const MIGRATE_1_TO_2_SQLS: string[] = [
  `ALTER TABLE account ADD COLUMN merchant TEXT DEFAULT ''`,
  `ALTER TABLE account ADD COLUMN source INTEGER DEFAULT 0`,
  `ALTER TABLE account ADD COLUMN pay_time INTEGER DEFAULT 0`
];

/**
 * version 2 → 3：主键自增 INTEGER 改为 UUID TEXT，重建表并复制旧数据，
 * 由 DBUtil 在单个事务内执行，任一步失败即回滚，避免数据丢失
 */
export const MIGRATE_2_TO_3_SQLS: string[] = [
  `DROP TABLE IF EXISTS account_tmp`,
  `CREATE TABLE account_tmp (
    id TEXT PRIMARY KEY,
    type INTEGER NOT NULL,
    account_type INTEGER NOT NULL,
    amount DOUBLE NOT NULL,
    create_time INTEGER NOT NULL,
    description STRING,
    time INTEGER NOT NULL,
    merchant TEXT DEFAULT '',
    source INTEGER DEFAULT 0,
    pay_time INTEGER DEFAULT 0
  )`,
  `INSERT INTO account_tmp (id, type, account_type, amount, create_time, description, time, merchant, source, pay_time)
    SELECT CAST(id AS TEXT), type, account_type, amount, create_time, description, time, merchant, source, pay_time FROM account`,
  `DROP TABLE account`,
  `ALTER TABLE account_tmp RENAME TO account`
];

/**
 * 按版本号升序组织的全部迁移步骤，供 DBUtil 逐级执行
 */
export const MIGRATION_STEPS: MigrationStep[] = [
  { toVersion: 2, sqls: MIGRATE_1_TO_2_SQLS },
  { toVersion: 3, sqls: MIGRATE_2_TO_3_SQLS }
];
