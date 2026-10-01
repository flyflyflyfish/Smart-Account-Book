import {
  RecognizerType,
  RECOGNIZE_CONFIDENCE_THRESHOLD,
  RECOGNIZE_RETRY_MAX_ATTEMPTS,
  RECOGNIZE_RETRY_BASE_DELAY_MS,
  RECOGNIZE_CACHE_SIZE
} from '../../common/Config';
import CloudLlmConfigStore from './CloudLlmConfigStore';
import { CloudLlmRecognizer } from './CloudLlmRecognizer';
import { MockRecognizer } from './MockRecognizer';
import { LocalOcrRecognizer } from './LocalOcrRecognizer';
import { Recognizer } from './Recognizer';
import { FallbackRecognizer } from './decorators/FallbackRecognizer';
import { RetryRecognizer } from './decorators/RetryRecognizer';
import { CachingRecognizer } from './decorators/CachingRecognizer';
import { LoggingRecognizer } from './decorators/LoggingRecognizer';

/**
 * 识别器工厂：按设置页保存的类型创建基础识别器，再按配置组合装饰器
 * CLOUD：Logging(Caching(Retry(Fallback(Cloud, LocalOcr))))
 * MOCK： Logging(Caching(Retry(Mock)))
 */
export class RecognizerFactory {
  static async create(): Promise<Recognizer> {
    const type = await CloudLlmConfigStore.loadRecognizerType();
    let primary: Recognizer;
    let useFallback = false;
    if (type === RecognizerType.CLOUD) {
      primary = new CloudLlmRecognizer(await CloudLlmConfigStore.loadConfig());
      useFallback = true;
    } else {
      primary = new MockRecognizer();
    }

    let recognizer: Recognizer = primary;
    if (useFallback) {
      recognizer = new FallbackRecognizer(primary, new LocalOcrRecognizer(), RECOGNIZE_CONFIDENCE_THRESHOLD);
    }
    recognizer = new RetryRecognizer(recognizer, RECOGNIZE_RETRY_MAX_ATTEMPTS, RECOGNIZE_RETRY_BASE_DELAY_MS);
    recognizer = new CachingRecognizer(recognizer, RECOGNIZE_CACHE_SIZE);
    recognizer = new LoggingRecognizer(recognizer);
    return recognizer;
  }
}
