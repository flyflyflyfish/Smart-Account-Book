import { PipelineContext } from './PipelineContext';
import { PipelineStep } from './PipelineStep';

// 商家名首尾需去除的装饰符号：OCR 常带出 * # - 等多余字符
const MERCHANT_TRIM_PATTERN: RegExp = /^[\s*#\-—–·、,，.。:：;；"'()（）【】]+|[\s*#\-—–·、,，.。:：;；"'()（）【】]+$/g;

/**
 * 规范化步骤：金额保留两位小数，商家名清理首尾空格与多余符号
 */
export class NormalizeStep implements PipelineStep {
  async handle(ctx: PipelineContext): Promise<void> {
    // 先转整数再除回，避免浮点尾差
    ctx.result.amount = Math.round(ctx.result.amount * 100) / 100;
    ctx.result.merchant = NormalizeStep.normalizeMerchant(ctx.result.merchant);
  }

  private static normalizeMerchant(merchant: string): string {
    if (!merchant) {
      return '';
    }
    // 合并连续空白为单个空格，再去除首尾装饰符号
    return merchant.replace(/\s+/g, ' ').trim().replace(MERCHANT_TRIM_PATTERN, '');
  }
}
