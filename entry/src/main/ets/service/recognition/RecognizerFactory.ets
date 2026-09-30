import { RecognizerType } from '../../common/Config';
import CloudLlmConfigStore from './CloudLlmConfigStore';
import { CloudLlmRecognizer } from './CloudLlmRecognizer';
import { MockRecognizer } from './MockRecognizer';
import { Recognizer } from './Recognizer';

/**
 * 识别器工厂：按设置页保存的类型创建识别器，上层无需感知具体实现
 */
export class RecognizerFactory {
  static async create(): Promise<Recognizer> {
    const type = await CloudLlmConfigStore.loadRecognizerType();
    if (type === RecognizerType.CLOUD) {
      const config = await CloudLlmConfigStore.loadConfig();
      return new CloudLlmRecognizer(config);
    }
    return new MockRecognizer();
  }
}
