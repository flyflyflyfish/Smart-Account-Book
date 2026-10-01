import PreferenceUtil from '../../utils/PreferenceUtil';
import * as CONSTANTS from '../../common/constants';
import { CloudLlmConfig } from '../../models/recognition/CloudLlmModels';

/**
 * 云端识别配置与引擎开关存取：API Key 仅保存在本机 Preferences，绝不写入代码或仓库
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

  async loadOcrEnabled(): Promise<boolean> {
    const value = await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_OCR_ENABLED, true);
    return value === true;
  }

  async saveOcrEnabled(enabled: boolean): Promise<void> {
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_OCR_ENABLED, enabled);
  }

  async loadCloudEnabled(): Promise<boolean> {
    const value = await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_CLOUD_ENABLED, false);
    return value === true;
  }

  async saveCloudEnabled(enabled: boolean): Promise<void> {
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_CLOUD_ENABLED, enabled);
  }

  // 读取云端识别上传同意状态：默认 false，未同意前不得上传图片
  async loadCloudConsent(): Promise<boolean> {
    const value = await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_CLOUD_CONSENT, false);
    return value === true;
  }

  async saveCloudConsent(agreed: boolean): Promise<void> {
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_CLOUD_CONSENT, agreed);
  }
}

export default new CloudLlmConfigStore();
