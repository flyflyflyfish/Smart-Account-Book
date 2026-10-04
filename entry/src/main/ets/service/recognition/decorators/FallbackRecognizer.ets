import { RecognitionResult } from '../../../models/recognition/RecognitionResult';
import { Recognizer } from '../Recognizer';
import { Logger } from '../../../utils/Logger';

/**
 * 降级识别器：primary 抛错或结果最小置信度低于阈值时，改用 secondary
 */
export class FallbackRecognizer implements Recognizer {
  private primary: Recognizer;
  private secondary: Recognizer;
  private confidenceThreshold: number;

  constructor(primary: Recognizer, secondary: Recognizer, confidenceThreshold: number) {
    this.primary = primary;
    this.secondary = secondary;
    this.confidenceThreshold = confidenceThreshold;
  }

  async recognize(imageUri: string): Promise<RecognitionResult[]> {
    try {
      const results = await this.primary.recognize(imageUri);
      if (this.isConfident(results)) {
        return results;
      }
    } catch (error) {
      // primary 失败，降级到 secondary（warn 级别便于在日志里发现降级原因）
      Logger.warn('主识别器失败，降级到备用识别器: ', (error as Error).message);
    }
    return this.secondary.recognize(imageUri);
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
