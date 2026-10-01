import dayjs from 'dayjs';
import { DEDUP_QUERY_DAYS } from '../../../common/Config';
import { isDuplicateBill } from '../../../common/dedup';
import AccountPO from '../../../models/account/accountPO';
import { AccountRepository } from '../../../data/AccountRepository';
import { RdbAccountRepository } from '../../../data/RdbAccountRepository';
import { PipelineContext } from './PipelineContext';
import { PipelineStep } from './PipelineStep';

/**
 * 去重步骤：与近期已有账单比较，金额相同 + 商家相同/互相包含 + 时间窗内 则标记疑似重复
 */
export class DedupStep implements PipelineStep {
  private repository: AccountRepository;

  constructor(repository?: AccountRepository) {
    this.repository = repository ? repository : new RdbAccountRepository();
  }

  async handle(ctx: PipelineContext): Promise<void> {
    const result = ctx.result;
    if (result.amount <= 0 || !result.merchant) {
      return;
    }
    const start = dayjs().subtract(DEDUP_QUERY_DAYS, 'day').valueOf();
    let existingList: AccountPO[] = [];
    try {
      existingList = await this.repository.queryByDateRange(start, Date.now());
    } catch (err) {
      // 查询失败不阻断识别，跳过去重
      return;
    }
    for (const existing of existingList) {
      if (isDuplicateBill(result.amount, result.merchant, result.payTime,
        existing.amount, existing.merchant, existing.payTime)) {
        ctx.result.duplicated = true;
        return;
      }
    }
  }
}
