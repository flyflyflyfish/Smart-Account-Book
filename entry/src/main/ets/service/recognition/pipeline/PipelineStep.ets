import { PipelineContext } from './PipelineContext';

/**
 * 识别流水线步骤接口：每个步骤只做一件事，抛错即中止整条链
 */
export interface PipelineStep {
  handle(ctx: PipelineContext): Promise<void>;
}
