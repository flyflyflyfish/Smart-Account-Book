import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import * as CONSTANTS from '../common/constants';
import { Logger } from './Logger';

class PreferenceUtils {
  private pref: preferences.Preferences | undefined = undefined;

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
      Logger.debug(`保存 Preference [${key} = ${value}] 成功`);
    } catch (err) {
      Logger.debug(`保存 Preference [${key} = ${value}] 失败`, err);
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
      Logger.debug(`读取 Preference [${key} = ${value}] 成功`);
      return value;
    } catch (err) {
      Logger.debug(`读取 Preference [${key}] 失败`, err);
      return defaultValue;
    }
  }
}

export default new PreferenceUtils();
