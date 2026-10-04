import PreferenceUtil from '../../utils/PreferenceUtil';
import * as CONSTANTS from '../../common/constants';
import { CloudLlmConfig, SavedProviderConfig } from '../../models/recognition/CloudLlmModels';

/**
 * 云端识别配置与引擎开关存取：支持多服务商，API Key 仅保存在本机 Preferences，绝不写入代码或仓库
 */
class CloudLlmConfigStore {
  // 读取当前生效的云端配置（= 当前激活服务商的 baseUrl/apiKey/model）。
  // 无多服务商数据时回退读取旧版三键，并迁移为「自定义」服务商，保证老用户无缝升级。
  async loadConfig(): Promise<CloudLlmConfig> {
    const providers = await this.loadProviders();
    if (providers.length > 0) {
      const activeId = await this.loadActiveProvider();
      const active = this.findActive(providers, activeId);
      return { baseUrl: active.baseUrl, apiKey: active.apiKey, model: active.model };
    }
    const legacy: CloudLlmConfig = {
      baseUrl: String(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_CLOUD_BASE_URL, '')),
      apiKey: String(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_CLOUD_API_KEY, '')),
      model: String(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_CLOUD_MODEL, ''))
    };
    if (legacy.baseUrl || legacy.apiKey || legacy.model) {
      const migrated: SavedProviderConfig = {
        id: 'custom',
        baseUrl: legacy.baseUrl,
        apiKey: legacy.apiKey,
        model: legacy.model
      };
      await this.saveProviders([migrated]);
      await this.setActiveProvider('custom');
    }
    return legacy;
  }

  private findActive(providers: SavedProviderConfig[], activeId: string): SavedProviderConfig {
    for (const p of providers) {
      if (p.id === activeId) {
        return p;
      }
    }
    return providers[0];
  }

  // 多服务商配置列表（JSON 数组）
  async saveProviders(providers: SavedProviderConfig[]): Promise<void> {
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_CLOUD_PROVIDERS, JSON.stringify(providers));
  }

  async loadProviders(): Promise<SavedProviderConfig[]> {
    const raw = String(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_CLOUD_PROVIDERS, ''));
    if (!raw) {
      return [];
    }
    try {
      const arr = JSON.parse(raw) as SavedProviderConfig[];
      if (Array.isArray(arr)) {
        return arr;
      }
    } catch (e) {
      // 解析失败按空处理
    }
    return [];
  }

  // 当前激活的服务商 id
  async setActiveProvider(id: string): Promise<void> {
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_CLOUD_ACTIVE_PROVIDER, id);
  }

  async loadActiveProvider(): Promise<string> {
    return String(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_CLOUD_ACTIVE_PROVIDER, ''));
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

  // 训练数据采集开关：默认关闭，仅存本机，不上传
  async loadTrainCollectEnabled(): Promise<boolean> {
    const value = await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_TRAIN_COLLECT_ENABLED, false);
    return value === true;
  }

  async saveTrainCollectEnabled(enabled: boolean): Promise<void> {
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_TRAIN_COLLECT_ENABLED, enabled);
  }
}

export default new CloudLlmConfigStore();
