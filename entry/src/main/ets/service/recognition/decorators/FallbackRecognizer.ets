import { RecognitionResult } from '../../../models/recognition/RecognitionResult';
import { RecognitionWarnings } from '../../../models/recognition/RecognitionWarnings';
import { Recognizer } from '../Recognizer';
import { Logger } from '../../../utils/Logger';

/**
 * 降级识别器：primary 抛错或（可配置）结果最小置信度低于阈值时，改用 secondary；
 * secondary 也失败时，若 primary 曾产出结果（虽低置信）则返回 primary 结果供用户确认，
 * 而不是让整体识别失败——宁可给出待修正的草稿，也不给用户看一个空结果页。
 * fallbackOnLowConfidence=false 时不因低置信降级（secondary 弱于 primary 的场景，如纯 OCR 规则）：
 * primary 有结果即呈报，仅 primary 失败/空结果才走 secondary 兜底
 */
export class FallbackRecognizer implements Recognizer {
  private primary: Recognizer;
  private secondary: Recognizer;
  private confidenceThreshold: number;
  private fallbackOnLowConfidence: boolean;

  constructor(primary: Recognizer, secondary: Recognizer, confidenceThreshold: number,
    fallbackOnLowConfidence: boolean) {
    this.primary = primary;
    this.secondary = secondary;
    this.confidenceThreshold = confidenceThreshold;
    this.fallbackOnLowConfidence = fallbackOnLowConfidence;
  }

  async recognize(imageUri: string): Promise<RecognitionResult[]> {
    let primaryResults: RecognitionResult[] = [];
    try {
      primaryResults = await this.primary.recognize(imageUri);
      if (this.isConfident(primaryResults)) {
        return primaryResults;
      }
    } catch (error) {
      // primary 失败，降级到 secondary（warn 级别便于在日志里发现降级原因）
      Logger.warn('主识别器失败，降级到备用识别器: ', (error as Error).message);
    }
    // secondary 不强于 primary 时不做低置信降级：端侧模型低置信结果仍优于纯 OCR 规则解析
    if (!this.fallbackOnLowConfidence && primaryResults.length > 0) {
      return primaryResults;
    }
    try {
      return await this.secondary.recognize(imageUri);
    } catch (error) {
      const err = error as Error;
      if (primaryResults.length > 0) {
        Logger.warn('备用识别器失败，回退主识别器低置信结果: ', err.message);
        // 云端失败原因（如"当前模型不支持图片输入"）交给页面层在批次结束后提示用户
        RecognitionWarnings.add(err.message);
        return primaryResults;
      }
      throw err;
    }
  }

  // 结果非空且每笔置信度都不低于阈值才视为可信
  private isConfident(results: RecognitionResult[]): boolean {
    if (results.length === 0) {
      return false;
    }
    for (const r of results) {
      if (r.confidence < this.confidenceThreshold) {
        return false;
      }
    }
    return true;
  }
}
