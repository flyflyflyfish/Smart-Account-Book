import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import * as CONSTANTS from '../common/constants';
import { Logger } from './Logger';

class PreferenceUtils {
  private pref: preferences.Preferences | undefined = undefined;
  // 首次 loadPreference 的 context：后续读写发现未初始化时用它做懒加载重试
  private loadContext: common.Context | undefined = undefined;

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
    this.loadContext = context;
    try {
      this.pref = await preferences.getPreferences(context, CONSTANTS.H_STORE);
      Logger.debug(`加载 Preference [${CONSTANTS.H_STORE}] 成功`);
    } catch (err) {
      Logger.debug(`加载 Preference [${CONSTANTS.H_STORE}] 失败`, err);
    }
  }

  // 跨进程场景（主应用 ↔ 卡片进程）各自持有独立的内存缓存实例，
  // 对方进程写入并 flush 后，本进程的缓存实例不会自动更新，会一直读到旧值。
  // 该方法先把实例从静态缓存容器中移除，再从磁盘重新加载，保证读到对方进程的最新数据。
  async reloadPreference(context?: common.Context): Promise<void> {
    const ctx = context ?? this.loadContext;
    if (!ctx) {
      return;
    }
    this.loadContext = ctx;
    try {
      await preferences.removePreferencesFromCache(ctx, CONSTANTS.H_STORE);
    } catch (err) {
      Logger.debug(`移除 Preference 缓存 [${CONSTANTS.H_STORE}] 失败`, err);
    }
    try {
      this.pref = await preferences.getPreferences(ctx, CONSTANTS.H_STORE);
      Logger.debug(`重载 Preference [${CONSTANTS.H_STORE}] 成功`);
    } catch (err) {
      Logger.debug(`重载 Preference [${CONSTANTS.H_STORE}] 失败`, err);
    }
  }

  // 确保已加载：启动时加载失败不是永久状态，首次读写时用保存的 context 重试
  private async ensureLoaded(): Promise<preferences.Preferences> {
    if (this.pref) {
      return this.pref;
    }
    if (!this.loadContext) {
      throw new Error('Preference 尚未初始化');
    }
    this.pref = await preferences.getPreferences(this.loadContext, CONSTANTS.H_STORE);
    return this.pref;
  }

  async putPreferenceValue(key: string, value: preferences.ValueType): Promise<void> {
    try {
      const pref = await this.ensureLoaded();
      await pref.put(key, value);
      await pref.flush();
      Logger.debug(`保存 Preference [${key} = ${PreferenceUtils.maskValue(key, value)}] 成功`);
    } catch (err) {
      Logger.debug(`保存 Preference [${key} = ${PreferenceUtils.maskValue(key, value)}] 失败`, err);
      // 写失败必须上抛：调用方（如快捷记账的进度保存）依赖失败信号中断流程，
      // 吞掉异常会导致“以为保存成功”，引发重复记账等数据错误
      throw err as Error;
    }
  }

  async getPreferenceValue(key: string, defaultValue: preferences.ValueType): Promise<preferences.ValueType> {
    try {
      const pref = await this.ensureLoaded();
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
