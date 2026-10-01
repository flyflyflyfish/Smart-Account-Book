import dayjs from 'dayjs';
import { DEDUP_QUERY_DAYS, DEDUP_TIME_WINDOW_MS } from '../../../common/Config';
import AccountPO from '../../../models/account/accountPO';
import { RecognitionResult } from '../../../models/recognition/RecognitionResult';
import AccountService from '../../account';
import { PipelineContext } from './PipelineContext';
import { PipelineStep } from './PipelineStep';

/**
 * 去重步骤：与近期已有账单比较，金额相同 + 商家相同/互相包含 + 时间窗内 则标记疑似重复
 */
export class DedupStep implements PipelineStep {
  async handle(ctx: PipelineContext): Promise<void> {
    const result = ctx.result;
    if (result.amount <= 0 || !result.merchant) {
      return;
    }
    const start = dayjs().subtract(DEDUP_QUERY_DAYS, 'day').valueOf();
    let existingList: AccountPO[] = [];
    try {
      existingList = await AccountService.queryByDateRange(start, Date.now());
    } catch (err) {
      // 查询失败不阻断识别，跳过去重
      return;
    }
    for (const existing of existingList) {
      if (DedupStep.isDuplicate(result, existing)) {
        ctx.result.duplicated = true;
        return;
      }
    }
  }

  private static isDuplicate(result: RecognitionResult, existing: AccountPO): boolean {
    // 金额相同（保留两位小数，浮点容差）
    if (Math.abs(result.amount - existing.amount) >= 0.005) {
      return false;
    }
    // 商家相同或互相包含
    const m1 = result.merchant;
    const m2 = existing.merchant;
    if (!m1 || !m2) {
      return false;
    }
    if (m1 !== m2 && m1.indexOf(m2) < 0 && m2.indexOf(m1) < 0) {
      return false;
    }
    // 旧数据 payTime 为 0 时不参与时间比较
    if (existing.payTime <= 0) {
      return true;
    }
    return Math.abs(result.payTime - existing.payTime) <= DEDUP_TIME_WINDOW_MS;
  }
}
