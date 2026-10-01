import { RecognitionResult } from '../../../models/recognition/RecognitionResult';
import { ClassifyStep } from './ClassifyStep';
import { DedupStep } from './DedupStep';
import { NormalizeStep } from './NormalizeStep';
import { PipelineContext } from './PipelineContext';
import { PipelineStep } from './PipelineStep';
import { ValidateStep } from './ValidateStep';

/**
 * 流水线执行结果：成功时携带处理后的结果与警告，失败时携带可读错误信息
 */
export interface PipelineResult {
  success: boolean;
  // 失败时的可读错误信息，成功时为空串
  message: string;
  // 非致命警告列表
  warnings: string[];
  // 处理后的识别结果（失败时为已处理到的最新状态）
  result: RecognitionResult;
}

/**
 * 识别流水线：按固定顺序执行各步骤，任一步抛错即中止并返回可读错误
 */
export class RecognitionPipeline {
  private steps: PipelineStep[];

  constructor(steps?: PipelineStep[]) {
    // 顺序即职责：校验 -> 规范化 -> 分类 -> 去重；测试可注入自定义步骤
    this.steps = steps ? steps : [new ValidateStep(), new NormalizeStep(), new ClassifyStep(), new DedupStep()];
  }

  async run(imageUri: string, raw: RecognitionResult): Promise<PipelineResult> {
    const ctx = new PipelineContext(imageUri, raw);
    try {
      for (const step of this.steps) {
        await step.handle(ctx);
      }
      return { success: true, message: '', warnings: ctx.warnings, result: ctx.result };
    } catch (error) {
      const err = error as Error;
      const message = err.message
        ? err.message
        : getContext().resourceManager.getStringSync($r('app.string.recognize_failed'));
      return { success: false, message: message, warnings: ctx.warnings, result: ctx.result };
    }
  }
}
