/**
 * 数据库表结构定义
 */
export const ACCOUNT_TABLE_NAME: string = 'account';
export const MERCHANT_CATEGORY_TABLE_NAME: string = 'merchant_category';
export const LEDGER_TABLE_NAME: string = 'ledger';
export const LEDGER_RECORD_TABLE_NAME: string = 'ledger_record';

/**
 * 当前数据库版本号：老库 version 为 0，升级后置为 7
 */
export const DB_VERSION: number = 7;

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
 * 账本表：多账本容器（如旅行账本、人情账本），颜色取主题 accent 令牌
 */
export const LEDGER_CREATE_TABLE_SQL: string = `
  CREATE TABLE IF NOT EXISTS ledger (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    color_key TEXT DEFAULT 'green',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL DEFAULT 0
  )`;

/**
 * 账本记录表：账本内的一笔收支（type：0 支出 / 1 收入），
 * category 为账单分类 id（-1 表示未选分类），
 * bill_id 为关联的主账单 id（空串表示与主账单无关，用于“从现有账单导入”防重复）
 */
export const LEDGER_RECORD_CREATE_TABLE_SQL: string = `
  CREATE TABLE IF NOT EXISTS ledger_record (
    id TEXT PRIMARY KEY,
    ledger_id TEXT NOT NULL,
    type INTEGER NOT NULL,
    amount DOUBLE NOT NULL,
    note TEXT DEFAULT '',
    time INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL DEFAULT 0,
    category INTEGER DEFAULT -1,
    bill_id TEXT DEFAULT ''
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
 * version 3 → 4：新增账本与账本记录两张表（IF NOT EXISTS 对新装为无操作）
 */
/**
 * version 3 → 4：新增账本与账本记录两张表（IF NOT EXISTS 对新装为无操作）。
 * 注意：保持历史原样（不含 category / bill_id 列），由 4→5、5→6 逐级补列，
 * 否则老库升级时 ALTER TABLE ADD COLUMN 会因列已存在而迁移失败。
 */
export const MIGRATE_3_TO_4_SQLS: string[] = [
  `CREATE TABLE IF NOT EXISTS ledger (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    color_key TEXT DEFAULT 'green',
    created_at INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS ledger_record (
    id TEXT PRIMARY KEY,
    ledger_id TEXT NOT NULL,
    type INTEGER NOT NULL,
    amount DOUBLE NOT NULL,
    note TEXT DEFAULT '',
    time INTEGER NOT NULL,
    created_at INTEGER NOT NULL
  )`
];

/**
 * version 4 → 5：账本记录补分类列（-1 表示未选分类），历史记录保持无分类
 */
export const MIGRATE_4_TO_5_SQLS: string[] = [
  `ALTER TABLE ledger_record ADD COLUMN category INTEGER DEFAULT -1`
];

/**
 * version 5 → 6：账本记录补关联主账单列（空串表示与主账单无关），
 * 供“从现有账单导入”防重复导入
 */
export const MIGRATE_5_TO_6_SQLS: string[] = [
  `ALTER TABLE ledger_record ADD COLUMN bill_id TEXT DEFAULT ''`
];

/**
 * version 6 → 7：账本与账本记录补端云同步用的 updated_at 列，
 * 历史行以 created_at 回填，作为合并比较的基准时间
 */
export const MIGRATE_6_TO_7_SQLS: string[] = [
  `ALTER TABLE ledger ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0`,
  `UPDATE ledger SET updated_at = created_at WHERE updated_at = 0`,
  `ALTER TABLE ledger_record ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0`,
  `UPDATE ledger_record SET updated_at = created_at WHERE updated_at = 0`
];

/**
 * 按版本号升序组织的全部迁移步骤，供 DBUtil 逐级执行
 */
export const MIGRATION_STEPS: MigrationStep[] = [
  { toVersion: 2, sqls: MIGRATE_1_TO_2_SQLS },
  { toVersion: 3, sqls: MIGRATE_2_TO_3_SQLS },
  { toVersion: 4, sqls: MIGRATE_3_TO_4_SQLS },
  { toVersion: 5, sqls: MIGRATE_4_TO_5_SQLS },
  { toVersion: 6, sqls: MIGRATE_5_TO_6_SQLS },
  { toVersion: 7, sqls: MIGRATE_6_TO_7_SQLS }
];
