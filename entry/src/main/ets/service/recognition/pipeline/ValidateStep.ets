import dayjs from 'dayjs';
import { WARN_AMOUNT_INVALID, WARN_PAYTIME_INVALID } from '../../../common/constants';
import { PipelineContext } from './PipelineContext';
import { PipelineStep } from './PipelineStep';

/**
 * 校验步骤：非账单直接终止；金额非法与时间缺失只记警告，由确认页兜底
 */
export class ValidateStep implements PipelineStep {
  async handle(ctx: PipelineContext): Promise<void> {
    if (!ctx.result.isBill) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.not_a_bill')));
    }
    if (ctx.result.amount <= 0) {
      ctx.addWarning(WARN_AMOUNT_INVALID);
    }
    // 时间戳非法（0/负数/NaN/无法解析）时回退为当前时间
    if (ctx.result.payTime <= 0 || !dayjs(ctx.result.payTime).isValid()) {
      ctx.result.payTime = Date.now();
      ctx.addWarning(WARN_PAYTIME_INVALID);
    }
  }
}
