import { DEDUP_TIME_WINDOW_MS } from './Config';

/**
 * 判断两条账单是否疑似重复：金额相同 + 商家相同或互相包含 + 支付时间窗内
 * payTimeB 为 0（旧数据）时不参与时间比较
 */
export function isDuplicateBill(
  amountA: number, merchantA: string, payTimeA: number,
  amountB: number, merchantB: string, payTimeB: number
): boolean {
  if (Math.abs(amountA - amountB) >= 0.005) {
    return false;
  }
  if (!merchantA || !merchantB) {
    return false;
  }
  if (merchantA !== merchantB && merchantA.indexOf(merchantB) < 0 && merchantB.indexOf(merchantA) < 0) {
    return false;
  }
  if (payTimeB <= 0) {
    return true;
  }
  return Math.abs(payTimeA - payTimeB) <= DEDUP_TIME_WINDOW_MS;
}
