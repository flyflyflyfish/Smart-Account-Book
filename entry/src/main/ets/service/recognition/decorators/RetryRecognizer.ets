import { RecognitionResult } from '../../../models/recognition/RecognitionResult';
import { Recognizer } from '../Recognizer';
import { NonRetryableError } from '../NonRetryableError';
import { Logger } from '../../../utils/Logger';

/**
 * 重试识别器：失败按指数退避重试（间隔逐次翻倍），耗尽次数后抛出最后一次错误；
 * NonRetryableError（服务端明确拒绝，重试必然同结果）直接上抛不重试
 */
export class RetryRecognizer implements Recognizer {
  private inner: Recognizer;
  private maxAttempts: number;
  private baseDelayMs: number;

  constructor(inner: Recognizer, maxAttempts: number, baseDelayMs: number) {
    this.inner = inner;
    this.maxAttempts = maxAttempts;
    this.baseDelayMs = baseDelayMs;
  }

  async recognize(imageUri: string): Promise<RecognitionResult[]> {
    let attempt = 0;
    let delay = this.baseDelayMs;
    while (true) {
      try {
        return await this.inner.recognize(imageUri);
      } catch (error) {
        if (error instanceof NonRetryableError) {
          Logger.debug('识别失败且不可重试，直接上抛: ', (error as Error).message);
          throw error;
        }
        attempt++;
        if (attempt >= this.maxAttempts) {
          const err = error as Error;
          throw err;
        }
        Logger.debug('识别失败，准备重试, 第', attempt, '次, 等待(ms): ', delay);
        await this.sleep(delay);
        delay = delay * 2;
      }
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}
