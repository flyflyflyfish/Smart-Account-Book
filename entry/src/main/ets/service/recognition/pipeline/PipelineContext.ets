import { RecognitionResult } from '../../../models/recognition/RecognitionResult';

/**
 * 识别流水线上下文：在责任链各步骤间传递图片、识别结果与非致命警告
 */
export class PipelineContext {
  // 原始图片地址
  imageUri: string;
  // 待处理/处理中的识别结果，各步骤就地修改
  result: RecognitionResult;
  // 非致命警告信息列表，供确认页提示用户
  warnings: string[] = [];

  constructor(imageUri: string, result: RecognitionResult) {
    this.imageUri = imageUri;
    this.result = result;
  }

  addWarning(message: string): void {
    this.warnings.push(message);
  }
}
