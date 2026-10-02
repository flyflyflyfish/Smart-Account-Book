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
import { PREF_THEME_ID, PREF_COLOR_MODE } from '../common/constants';

const IDENTITY_KEY: string = 'ohos.extra.param.key.form_identity';

/**
 * 记账卡片扩展：提供卡片创建、刷新、删除等生命周期回调。
 * 小卡（2*2）展示今日收支，大卡（2*4）左侧今日、右侧本月。
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
    const data = buildCardData('--', '--', '--', '--',
      resolveThemePalette(THEME_ID_PINE, false), this.isWideDimension(dimension));
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    this.refreshCard(formId, undefined);
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
      await PreferenceUtil.loadPreference(this.context);
      const palette = await this.resolvePalette();
      await WidgetUpdater.refreshForm(this.context, formId, dimension, palette);
    } catch (err) {
      Logger.error('卡片数据更新失败', (err as Error).message);
    }
  }

  /** 读主题偏好解析调色板；读取失败时回退默认松雾绿浅色 */
  private async resolvePalette(): Promise<ThemePalette> {
    const savedId = await PreferenceUtil.getPreferenceValue(PREF_THEME_ID, THEME_ID_PINE);
    const savedMode = await PreferenceUtil.getPreferenceValue(PREF_COLOR_MODE, THEME_MODE_SYSTEM);
    const id = typeof savedId === 'string' ? savedId : THEME_ID_PINE;
    const mode = typeof savedMode === 'string' ? savedMode : THEME_MODE_SYSTEM;
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
    return resolveThemePalette(id, dark);
  }
}
