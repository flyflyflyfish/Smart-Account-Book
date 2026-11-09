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
import { LocalBillModelRecognizer } from './local_model/LocalBillModelRecognizer';

/**
 * 识别器工厂：按设置页的引擎开关创建基础识别器，再按配置组合装饰器。
 * 端侧开启（默认）：本地模型为主 —— Logging(Caching(Fallback(LocalModel, 回退)))
 *   - 云端也开启：结果低置信/本地失败时回退云端大模型（云端带重试）—— 多模态仅作回退
 *   - 云端未开启：本地模型不可用时退回纯 OCR 规则解析
 * 仅云端：Logging(Caching(Retry(Cloud)))
 * 两者都关：纯 OCR 规则解析（保留旧行为兜底）
 */
export class RecognizerFactory {
  static async create(): Promise<Recognizer> {
    const cloudEnabled = await CloudLlmConfigStore.loadCloudEnabled();
    const ocrEnabled = await CloudLlmConfigStore.loadOcrEnabled();

    let recognizer: Recognizer;
    if (ocrEnabled) {
      // 本地模型为主：端侧 OCR 文本块 + 自训小模型
      const local = new LocalBillModelRecognizer();
      if (cloudEnabled) {
        // 多模态仅作回退：本地低置信/失败时才走云端，云端自身先重试（云端更强，允许低置信降级）
        const cloud = new RetryRecognizer(
          new CloudLlmRecognizer(await CloudLlmConfigStore.loadConfig()),
          RECOGNIZE_RETRY_MAX_ATTEMPTS, RECOGNIZE_RETRY_BASE_DELAY_MS);
        recognizer = new FallbackRecognizer(local, cloud, RECOGNIZE_CONFIDENCE_THRESHOLD, true);
      } else {
        // 未配云端：本地模型失败/空结果才退回纯 OCR 规则解析；
        // 低置信不降级——端侧模型低置信结果仍优于纯 OCR 规则，直接呈报确认页
        recognizer = new FallbackRecognizer(local, new LocalOcrRecognizer(),
          RECOGNIZE_CONFIDENCE_THRESHOLD, false);
      }
    } else if (cloudEnabled) {
      recognizer = new RetryRecognizer(
        new CloudLlmRecognizer(await CloudLlmConfigStore.loadConfig()),
        RECOGNIZE_RETRY_MAX_ATTEMPTS, RECOGNIZE_RETRY_BASE_DELAY_MS);
    } else {
      recognizer = new LocalOcrRecognizer();
    }
    recognizer = new CachingRecognizer(recognizer, RECOGNIZE_CACHE_SIZE);
    recognizer = new LoggingRecognizer(recognizer);
    return recognizer;
  }
}
