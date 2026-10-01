import { describe, it, expect } from '@ohos/hypium';
import { ValidateStep } from '../../../main/ets/service/recognition/pipeline/ValidateStep';
import { NormalizeStep } from '../../../main/ets/service/recognition/pipeline/NormalizeStep';
import { PipelineContext } from '../../../main/ets/service/recognition/pipeline/PipelineContext';
import { RecognitionResult } from '../../../main/ets/models/recognition/RecognitionResult';
import { AccountType } from '../../../main/ets/models/account/account';
import { WARN_AMOUNT_INVALID, WARN_PAYTIME_INVALID } from '../../../main/ets/common/constants';

function buildResult(amount: number, payTime: number): RecognitionResult {
  const result: RecognitionResult = {
    accountType: AccountType.EXPENSES,
    amount: amount,
    merchant: '星巴克',
    payTime: payTime,
    categoryName: '早午晚餐',
    confidence: 1,
    isBill: true
  };
  return result;
}

export default function validateNormalizeStepTest() {
  describe('ValidateNormalizeStepTest', () => {
    it('validate_amountZero_warning', 0, async () => {
      const step = new ValidateStep();
      const ctx = new PipelineContext('uri', buildResult(0, Date.now()));
      await step.handle(ctx);
      expect(ctx.warnings.length).assertEqual(1);
      expect(ctx.warnings[0]).assertEqual(WARN_AMOUNT_INVALID);
    });

    it('validate_amountNegative_warning', 0, async () => {
      const step = new ValidateStep();
      const ctx = new PipelineContext('uri', buildResult(-5, Date.now()));
      await step.handle(ctx);
      expect(ctx.warnings.length).assertEqual(1);
      expect(ctx.warnings[0]).assertEqual(WARN_AMOUNT_INVALID);
    });

    it('validate_paytimeInvalid_reset', 0, async () => {
      const step = new ValidateStep();
      const ctx = new PipelineContext('uri', buildResult(10, 0));
      await step.handle(ctx);
      expect(ctx.result.payTime).assertLarger(0);
      expect(ctx.warnings.length).assertEqual(1);
      expect(ctx.warnings[0]).assertEqual(WARN_PAYTIME_INVALID);
    });

    it('normalize_amount_twoDecimals', 0, async () => {
      const step = new NormalizeStep();
      const ctx = new PipelineContext('uri', buildResult(35.567, Date.now()));
      await step.handle(ctx);
      expect(Math.round(ctx.result.amount * 100)).assertEqual(3557);
    });

    it('normalize_merchant_trim', 0, async () => {
      const step = new NormalizeStep();
      const ctx = new PipelineContext('uri', buildResult(10, Date.now()));
      ctx.result.merchant = '  **星巴克**  ';
      await step.handle(ctx);
      expect(ctx.result.merchant).assertEqual('星巴克');
    });
  });
}
