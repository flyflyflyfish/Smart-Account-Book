import dayjs from 'dayjs';
import { DEDUP_QUERY_DAYS } from '../../../common/Config';
import { isDuplicateBill } from '../../../common/dedup';
import AccountPO from '../../../models/account/accountPO';
import { AccountRepository } from '../../../data/AccountRepository';
import { RdbAccountRepository } from '../../../data/RdbAccountRepository';
import { PipelineContext } from './PipelineContext';
import { PipelineStep } from './PipelineStep';
import { Logger } from '../../../utils/Logger';

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
      Logger.warn('去重跳过：金额<=0 或商家为空', String(result.amount), result.merchant);
      return;
    }
    const start = dayjs().subtract(DEDUP_QUERY_DAYS, 'day').valueOf();
    let existingList: AccountPO[] = [];
    try {
      existingList = await this.repository.queryByDateRange(start, Date.now());
    } catch (err) {
      Logger.warn('去重查询失败', (err as Error).message);
      return;
    }
    Logger.warn('去重比对：新账单 amount=', String(result.amount), ' merchant=', result.merchant,
      ' payTime=', String(result.payTime), ' 近30天账单数=', String(existingList.length));
    for (const existing of existingList) {
      const dup = isDuplicateBill(result.amount, result.merchant, result.payTime,
        existing.amount, existing.merchant, existing.payTime);
      if (dup) {
        ctx.result.duplicated = true;
        Logger.warn('去重命中：已存在 amount=', String(existing.amount), ' merchant=', existing.merchant,
          ' payTime=', String(existing.payTime));
        return;
      }
    }
  }
}
