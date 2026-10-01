import { RecognitionResult } from '../../../models/recognition/RecognitionResult';
import { Recognizer } from '../Recognizer';
import { Logger } from '../../../utils/Logger';

/**
 * 日志识别器：记录识别耗时与状态，不记录图片地址与识别内容等敏感信息
 */
export class LoggingRecognizer implements Recognizer {
  private inner: Recognizer;

  constructor(inner: Recognizer) {
    this.inner = inner;
  }

  async recognize(imageUri: string): Promise<RecognitionResult[]> {
    const start = Date.now();
    try {
      const results = await this.inner.recognize(imageUri);
      Logger.debug('识别成功, 结果数: ', results.length, '耗时(ms): ', Date.now() - start);
      return results;
    } catch (error) {
      Logger.error('识别失败, 耗时(ms): ', Date.now() - start);
      const err = error as Error;
      throw err;
    }
  }
}
