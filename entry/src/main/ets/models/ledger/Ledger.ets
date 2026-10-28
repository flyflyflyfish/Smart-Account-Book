/**
 * 账本与账本记录的领域模型
 */

/** 账本颜色 key（对应主题调色板 accent 令牌） */
export const LEDGER_COLOR_KEYS: string[] = ['green', 'blue', 'yellow', 'orange', 'red', 'purple'];

export const LEDGER_COLOR_DEFAULT: string = 'green';

/** 记录收支类型：支出 / 收入 */
export const LEDGER_RECORD_EXPENSE: number = 0;
export const LEDGER_RECORD_INCOME: number = 1;

/** 账本 */
export class Ledger {
  id: string = '';
  name: string = '';
  colorKey: string = LEDGER_COLOR_DEFAULT;
  createdAt: number = 0;
}

/** 未选分类时的 category 值 */
export const LEDGER_RECORD_NO_CATEGORY: number = -1;

/** 账本内的一笔记录 */
export class LedgerRecord {
  id: string = '';
  ledgerId: string = '';
  type: number = LEDGER_RECORD_EXPENSE;
  amount: number = 0;
  note: string = '';
  time: number = 0;
  createdAt: number = 0;
  // 账单分类 id（取 CategoryStore 的分类，-1 表示未选）
  category: number = LEDGER_RECORD_NO_CATEGORY;
  // 关联的主账单 id（空串表示与主账单无关），供“从现有账单导入”防重复
  billId: string = '';
}

/** 账本列表项：账本 + 汇总（支出/收入/笔数），供列表卡片一次取齐 */
export class LedgerOverview {
  ledger: Ledger = new Ledger();
  expenses: number = 0;
  income: number = 0;
  recordCount: number = 0;
}
