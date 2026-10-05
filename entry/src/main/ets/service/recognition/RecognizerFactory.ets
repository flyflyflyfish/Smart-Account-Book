import {
  RECOGNIZE_CONFIDENCE_THRESHOLD,
  RECOGNIZE_RETRY_MAX_ATTEMPTS,
  RECOGNIZE_RETRY_BASE_DELAY_MS,
  RECOGNIZE_CACHE_SIZE
} from '../../common/Config';
import CloudLlmConfigStore from './CloudLlmConfigStore';
import { CloudLlmRecognizer } from './CloudLlmRecognizer';
import { LocalOcrRecognizer } from './LocalOcrRecognizer';
import { Recognizer } from './Recognizer';
import { FallbackRecognizer } from './decorators/FallbackRecognizer';
import { RetryRecognizer } from './decorators/RetryRecognizer';
import { CachingRecognizer } from './decorators/CachingRecognizer';
import { LoggingRecognizer } from './decorators/LoggingRecognizer';

/**
 * 识别器工厂：按设置页的引擎开关创建基础识别器，再按配置组合装饰器
 * 云端启用：Logging(Caching(Fallback(Retry(Cloud), LocalOcr)))  —— 云端失败先重试，仍失败才降级端侧（若端侧也启用）
 * 仅端侧：  Logging(Caching(Retry(LocalOcr)))
 */
export class RecognizerFactory {
  static async create(): Promise<Recognizer> {
    const cloudEnabled = await CloudLlmConfigStore.loadCloudEnabled();
    const ocrEnabled = await CloudLlmConfigStore.loadOcrEnabled();
    let primary: Recognizer;
    let useFallback = false;
    if (cloudEnabled) {
      primary = new CloudLlmRecognizer(await CloudLlmConfigStore.loadConfig());
      useFallback = ocrEnabled;
    } else {
      primary = new LocalOcrRecognizer();
    }

    let recognizer: Recognizer;
    if (useFallback) {
      // 重试包在 primary 内：云端超时/失败先原样重试，重试耗尽才降级端侧，避免端侧低质结果抢跑
      const retriedPrimary = new RetryRecognizer(primary, RECOGNIZE_RETRY_MAX_ATTEMPTS, RECOGNIZE_RETRY_BASE_DELAY_MS);
      recognizer = new FallbackRecognizer(retriedPrimary, new LocalOcrRecognizer(), RECOGNIZE_CONFIDENCE_THRESHOLD);
    } else {
      recognizer = new RetryRecognizer(primary, RECOGNIZE_RETRY_MAX_ATTEMPTS, RECOGNIZE_RETRY_BASE_DELAY_MS);
    }
    recognizer = new CachingRecognizer(recognizer, RECOGNIZE_CACHE_SIZE);
    recognizer = new LoggingRecognizer(recognizer);
    return recognizer;
  }
}
