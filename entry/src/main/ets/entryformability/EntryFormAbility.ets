import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import resourceManager from '@ohos.resourceManager';
import { Logger } from '../utils/Logger';
import PreferenceUtil from '../utils/PreferenceUtil';
import WidgetUpdater, { buildCardData } from '../common/widget/WidgetUpdater';
import {
  resolveThemePalette,
  ThemePalette,
  THEME_ID_PINE,
  THEME_MODE_DARK,
  THEME_MODE_LIGHT,
  THEME_MODE_SYSTEM
} from '../common/theme/Theme';
import { PREF_THEME_ID, PREF_COLOR_MODE, PREF_CUSTOM_THEME_PRIMARY, FORM_RANGE_PREFIX, WIDGET_RANGE_MONTH, WIDGET_RANGE_TODAY } from '../common/constants';

const IDENTITY_KEY: string = 'ohos.extra.param.key.form_identity';

/** 卡片 message 事件的原始数据结构 */
interface CardMessageRaw {
  range?: string;
  menu?: string;
}

/**
 * 记账卡片扩展：提供卡片创建、刷新、删除等生命周期回调。
 * 大卡（2*4）在「今日 / 本月」两种统计口径间切换展示收支（点击卡片上的口径开关触发 message 事件），
 * 每张卡片的选择持久化在 Preference，刷新与主应用同步时按各自口径推送。
 * 小卡（2*2）固定展示今日收支，右上角「+」点击展开手动添加 / 拍照识别 / AI 助手三个入口。
 * 查询与推送逻辑收敛在 WidgetUpdater，与主应用共享；
 * 卡片进程与主应用进程隔离，主题偏好从共享的 Preference 文件读取，
 * 解析为调色板后随卡片数据一并推送，使小组件跟随应用主题与深浅色。
 */
export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = this.getFormId(want);
    const dimension = this.readDimension(want);
    WidgetUpdater.registerForm(this.context, formId, dimension);
    this.refreshCard(formId, dimension);
    const data = buildCardData('--', '--', WIDGET_RANGE_TODAY, '0',
      resolveThemePalette(THEME_ID_PINE, false), this.isWideDimension(dimension));
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    this.refreshCard(formId, undefined);
  }

  /** 卡片上的交互消息：大卡切换「今日 / 本月」口径，小卡展开/收起「+」菜单 */
  onFormEvent(formId: string, message: string): void {
    this.handleCardMessage(formId, message);
  }

  onRemoveForm(formId: string): void {
    WidgetUpdater.unregisterForm(this.context, formId);
  }

  private readDimension(want: Want): number {
    const params = want.parameters;
    if (params) {
      const raw = params[formInfo.FormParam.DIMENSION_KEY];
      if (typeof raw === 'number') {
        return raw;
      }
    }
    return formInfo.FormDimension.Dimension_2_2;
  }

  private isWideDimension(dimension: number): boolean {
    return dimension === formInfo.FormDimension.Dimension_2_4;
  }

  private getFormId(want: Want): string {
    const params = want.parameters;
    if (params) {
      const id = params[IDENTITY_KEY];
      if (typeof id === 'string') {
        return id;
      }
    }
    return '';
  }

  private async refreshCard(formId: string, dimension: number | undefined): Promise<void> {
    if (!formId) {
      return;
    }
    try {
      // 先从磁盘重载偏好：主题是主应用进程写入的，本进程缓存实例读不到最新值，
      // 不重载会一直用旧主题调色板推送，把主应用推送的新配色覆盖回旧色
      await PreferenceUtil.reloadPreference(this.context);
      const palette = await this.resolvePalette();
      await WidgetUpdater.refreshForm(this.context, formId, dimension, palette);
    } catch (err) {
      Logger.error('卡片数据更新失败', (err as Error).message);
    }
  }

  /** 解析卡片交互消息（口径切换 / 菜单展开），处理后刷新卡片 */
  private async handleCardMessage(formId: string, message: string): Promise<void> {
    if (!formId) {
      return;
    }
    let hasAction = false;
    try {
      // 先从磁盘重载偏好再写入：避免本进程旧缓存实例 flush 时回退主进程刚写入的数据
      await PreferenceUtil.reloadPreference(this.context);
      const raw = JSON.parse(message) as CardMessageRaw;
      if (raw.range === WIDGET_RANGE_TODAY || raw.range === WIDGET_RANGE_MONTH) {
        hasAction = true;
        await PreferenceUtil.putPreferenceValue(FORM_RANGE_PREFIX + formId, raw.range);
      } else if (raw.menu === 'toggle') {
        hasAction = true;
        WidgetUpdater.toggleFormMenu(formId);
      }
    } catch (err) {
      hasAction = false;
    }
    if (hasAction) {
      this.refreshCard(formId, undefined);
    }
  }

  /** 读主题偏好解析调色板；读取失败时回退默认松雾绿浅色 */
  private async resolvePalette(): Promise<ThemePalette> {
    const savedId = await PreferenceUtil.getPreferenceValue(PREF_THEME_ID, THEME_ID_PINE);
    const savedMode = await PreferenceUtil.getPreferenceValue(PREF_COLOR_MODE, THEME_MODE_SYSTEM);
    const savedCustom = await PreferenceUtil.getPreferenceValue(PREF_CUSTOM_THEME_PRIMARY, '');
    const id = typeof savedId === 'string' ? savedId : THEME_ID_PINE;
    const mode = typeof savedMode === 'string' ? savedMode : THEME_MODE_SYSTEM;
    const customPrimary = typeof savedCustom === 'string' ? savedCustom : '';
    let dark = false;
    if (mode === THEME_MODE_DARK) {
      dark = true;
    } else if (mode === THEME_MODE_LIGHT) {
      dark = false;
    } else {
      try {
        const conf = this.context.resourceManager.getConfigurationSync();
        dark = conf.colorMode === resourceManager.ColorMode.DARK;
      } catch (err) {
        dark = false;
      }
    }
    return resolveThemePalette(id, dark, customPrimary);
  }
}
