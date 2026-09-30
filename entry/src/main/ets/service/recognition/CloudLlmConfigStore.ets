import PreferenceUtil from '../../utils/PreferenceUtil';
import { RecognizerType } from '../../common/Config';
import * as CONSTANTS from '../../common/constants';
import { CloudLlmConfig } from '../../models/recognition/CloudLlmModels';

/**
 * 云端识别配置存取：API Key 仅保存在本机 Preferences，绝不写入代码或仓库
 */
class CloudLlmConfigStore {
  async loadConfig(): Promise<CloudLlmConfig> {
    const config: CloudLlmConfig = {
      baseUrl: String(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_CLOUD_BASE_URL, '')),
      apiKey: String(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_CLOUD_API_KEY, '')),
      model: String(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_CLOUD_MODEL, ''))
    };
    return config;
  }

  async saveConfig(config: CloudLlmConfig): Promise<void> {
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_CLOUD_BASE_URL, config.baseUrl);
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_CLOUD_API_KEY, config.apiKey);
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_CLOUD_MODEL, config.model);
  }

  async loadRecognizerType(): Promise<RecognizerType> {
    const value = Number(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_RECOGNIZER_TYPE, RecognizerType.MOCK));
    return value === RecognizerType.CLOUD ? RecognizerType.CLOUD : RecognizerType.MOCK;
  }

  async saveRecognizerType(type: RecognizerType): Promise<void> {
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_RECOGNIZER_TYPE, type);
  }
}

export default new CloudLlmConfigStore();
