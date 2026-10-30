/**
 * 金额输入统一上限：所有金额录入入口共用。
 * 超长数字（如 1000000000000000）入库后会导致界面排版溢出与统计显示异常，
 * 统一钳制到上限内；上限与记一笔自定义键盘一致（7 位整数 + 2 位小数）。
 */
export const AMOUNT_MAX: number = 9999999.99;

/** 数值金额钳制：非法/非正数归 0，超上限压到上限，结果保留两位小数 */
export function clampAmount(value: number): number {
  if (!Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.round(Math.min(value, AMOUNT_MAX) * 100) / 100;
}
