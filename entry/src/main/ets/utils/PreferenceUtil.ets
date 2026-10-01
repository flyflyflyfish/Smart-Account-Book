import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import * as CONSTANTS from '../common/constants';
import { Logger } from './Logger';

class PreferenceUtils {
  private pref: preferences.Preferences | undefined = undefined;

  // 敏感键（API Key、密码等）不落明文，避免泄入日志
  private static maskValue(key: string, value: preferences.ValueType): string {
    const lower = key.toLowerCase();
    if (lower.indexOf('key') >= 0 || lower.indexOf('password') >= 0 ||
      lower.indexOf('secret') >= 0 || lower.indexOf('token') >= 0) {
      const text = String(value);
      if (text.length <= 4) {
        return '****';
      }
      return text.substring(0, 4) + '****' + text.substring(text.length - 2);
    }
    return String(value);
  }

  async loadPreference(context: common.Context): Promise<void> {
    try {
      this.pref = await preferences.getPreferences(context, CONSTANTS.H_STORE);
      Logger.debug(`加载 Preference [${CONSTANTS.H_STORE}] 成功`);
    } catch (err) {
      Logger.debug(`加载 Preference [${CONSTANTS.H_STORE}] 失败`, err);
    }
  }

  async putPreferenceValue(key: string, value: preferences.ValueType): Promise<void> {
    if (!this.pref) {
      Logger.debug(`Preference [${CONSTANTS.H_STORE}] 尚未初始化`);
      return;
    }
    try {
      const pref = this.pref;
      await pref.put(key, value);
      await pref.flush();
      Logger.debug(`保存 Preference [${key} = ${PreferenceUtils.maskValue(key, value)}] 成功`);
    } catch (err) {
      Logger.debug(`保存 Preference [${key} = ${PreferenceUtils.maskValue(key, value)}] 失败`, err);
    }
  }

  async getPreferenceValue(key: string, defaultValue: preferences.ValueType): Promise<preferences.ValueType> {
    if (!this.pref) {
      Logger.debug(`Preference [${CONSTANTS.H_STORE}] 尚未初始化`);
      return defaultValue;
    }
    try {
      const pref = this.pref;
      const value = await pref.get(key, defaultValue);
      Logger.debug(`读取 Preference [${key} = ${PreferenceUtils.maskValue(key, value)}] 成功`);
      return value;
    } catch (err) {
      Logger.debug(`读取 Preference [${key}] 失败`, err);
      return defaultValue;
    }
  }
}

export default new PreferenceUtils();
