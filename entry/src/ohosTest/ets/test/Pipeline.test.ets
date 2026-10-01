import { describe, it, expect } from '@ohos/hypium';
import { RecognitionPipeline } from '../../../main/ets/service/recognition/pipeline/RecognitionPipeline';
import { PipelineStep } from '../../../main/ets/service/recognition/pipeline/PipelineStep';
import { PipelineContext } from '../../../main/ets/service/recognition/pipeline/PipelineContext';
import { RecognitionResult } from '../../../main/ets/models/recognition/RecognitionResult';
import { AccountType } from '../../../main/ets/models/account/account';

class FakeStep implements PipelineStep {
  private handler: (ctx: PipelineContext) => Promise<void>;

  constructor(handler: (ctx: PipelineContext) => Promise<void>) {
    this.handler = handler;
  }

  async handle(ctx: PipelineContext): Promise<void> {
    await this.handler(ctx);
  }
}

function buildResult(): RecognitionResult {
  const result: RecognitionResult = {
    accountType: AccountType.EXPENSES,
    amount: 10,
    merchant: '星巴克',
    payTime: Date.now(),
    categoryName: '',
    confidence: 1,
    isBill: true
  };
  return result;
}

export default function pipelineTest() {
  describe('PipelineTest', () => {
    it('pipeline_success', 0, async () => {
      const steps: PipelineStep[] = [
        new FakeStep(async (ctx: PipelineContext): Promise<void> => {
          ctx.result.merchant = '规范化';
        }),
        new FakeStep(async (ctx: PipelineContext): Promise<void> => {
          ctx.result.categoryName = '早午晚餐';
        })
      ];
      const pipeline = new RecognitionPipeline(steps);
      const outcome = await pipeline.run('uri', buildResult());
      expect(outcome.success).assertTrue();
      expect(outcome.result.merchant).assertEqual('规范化');
      expect(outcome.result.categoryName).assertEqual('早午晚餐');
    });

    it('pipeline_stepFail', 0, async () => {
      const steps: PipelineStep[] = [
        new FakeStep(async (ctx: PipelineContext): Promise<void> => {
          throw new Error('step failed');
        })
      ];
      const pipeline = new RecognitionPipeline(steps);
      const outcome = await pipeline.run('uri', buildResult());
      expect(outcome.success).assertFalse();
      expect(outcome.message).assertEqual('step failed');
    });
  });
}
