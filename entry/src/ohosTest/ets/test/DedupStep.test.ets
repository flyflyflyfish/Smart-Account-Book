import { describe, it, expect } from '@ohos/hypium';
import { DedupStep } from '../../../main/ets/service/recognition/pipeline/DedupStep';
import { PipelineContext } from '../../../main/ets/service/recognition/pipeline/PipelineContext';
import { AccountRepository } from '../../../main/ets/data/AccountRepository';
import AccountPO from '../../../main/ets/models/account/accountPO';
import { RecognitionResult } from '../../../main/ets/models/recognition/RecognitionResult';
import { AccountType } from '../../../main/ets/models/account/account';
import { DEDUP_TIME_WINDOW_MS } from '../../../main/ets/common/Config';

class FakeAccountRepository implements AccountRepository {
  list: AccountPO[] = [];

  async queryByDateRange(startDate: number, endDate: number): Promise<AccountPO[]> {
    return this.list;
  }

  async insert(record: AccountPO): Promise<void> {
  }

  async deleteById(id: string): Promise<number> {
    return 0;
  }

  async queryRangeAndType(startDate: number, endDate: number, type: number): Promise<AccountPO[]> {
    return [];
  }

  async update(id: string, record: AccountPO): Promise<number> {
    return 0;
  }
}

function buildResult(amount: number, merchant: string, payTime: number): RecognitionResult {
  const result: RecognitionResult = {
    accountType: AccountType.EXPENSES,
    amount: amount,
    merchant: merchant,
    payTime: payTime,
    categoryName: '早午晚餐',
    confidence: 1,
    isBill: true
  };
  return result;
}

function buildPo(amount: number, merchant: string, payTime: number): AccountPO {
  const po = new AccountPO();
  po.amount = amount;
  po.merchant = merchant;
  po.payTime = payTime;
  return po;
}

export default function dedupStepTest() {
  describe('DedupStepTest', () => {
    it('dedup_exactDuplicate', 0, async () => {
      const now = Date.now();
      const repo = new FakeAccountRepository();
      repo.list = [buildPo(35.5, '星巴克', now)];
      const step = new DedupStep(repo);
      const ctx = new PipelineContext('uri', buildResult(35.5, '星巴克', now));
      await step.handle(ctx);
      expect(ctx.result.duplicated === true).assertTrue();
    });

    it('dedup_overTimeWindow', 0, async () => {
      const now = Date.now();
      const repo = new FakeAccountRepository();
      repo.list = [buildPo(35.5, '星巴克', now - DEDUP_TIME_WINDOW_MS - 1000)];
      const step = new DedupStep(repo);
      const ctx = new PipelineContext('uri', buildResult(35.5, '星巴克', now));
      await step.handle(ctx);
      expect(ctx.result.duplicated === true).assertFalse();
    });

    it('dedup_amountDifferent', 0, async () => {
      const now = Date.now();
      const repo = new FakeAccountRepository();
      repo.list = [buildPo(20, '星巴克', now)];
      const step = new DedupStep(repo);
      const ctx = new PipelineContext('uri', buildResult(35.5, '星巴克', now));
      await step.handle(ctx);
      expect(ctx.result.duplicated === true).assertFalse();
    });

    it('dedup_paytimeZero_existing', 0, async () => {
      const now = Date.now();
      const repo = new FakeAccountRepository();
      repo.list = [buildPo(35.5, '星巴克', 0)];
      const step = new DedupStep(repo);
      const ctx = new PipelineContext('uri', buildResult(35.5, '星巴克', now));
      await step.handle(ctx);
      expect(ctx.result.duplicated === true).assertTrue();
    });
  });
}
