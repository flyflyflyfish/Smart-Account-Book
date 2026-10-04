import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import relationalStore from '@ohos.data.relationalStore';
import dayjs from 'dayjs';
import { ACCOUNT_TABLE_NAME } from '../../data/schema';
import { Logger } from '../../utils/Logger';
import PreferenceUtil from '../../utils/PreferenceUtil';
import { ThemePalette } from '../theme/Theme';
import { FORM_DIM_PREFIX, PREF_FORM_IDS } from '../constants';

const DB_FILENAME: string = 'account.db';

// 进程级 RDB 连接缓存：卡片每次刷新都要查询，复用连接避免句柄累积；
// 打开失败时清空缓存，下次调用重试
let widgetStorePromise: Promise<relationalStore.RdbStore> | undefined = undefined;

function getWidgetStore(context: common.Context): Promise<relationalStore.RdbStore> {
  if (!widgetStorePromise) {
    const config: relationalStore.StoreConfig = {
      name: DB_FILENAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    widgetStorePromise = relationalStore.getRdbStore(context, config).catch((err: BusinessError) => {
      widgetStorePromise = undefined;
      throw err as Error;
    });
  }
  return widgetStorePromise;
}

export interface RangeSummary {
  expenses: number;
  income: number;
}

/** 组装推送给卡片的全部数据：收支金额、宽窄标记与主题色值 */
export function buildCardData(expenses: string, income: string, monthExpenses: string, monthIncome: string,
  palette: ThemePalette, isWide: boolean): Record<string, string> {
  return {
    'expenses': expenses,
    'income': income,
    'monthExpenses': monthExpenses,
    'monthIncome': monthIncome,
    'isWide': isWide ? '1' : '0',
    'bg': palette.background,
    'textPrimary': palette.textPrimary,
    'textSecondary': palette.textSecondary,
    'primary': palette.primary,
    'onPrimary': palette.onPrimary,
    'primarySoft': palette.primarySoft,
    'divider': palette.outline,
    'accentBlue': palette.accentBlue,
    'accentBlueSoft': palette.accentBlueSoft,
    'accentOrange': palette.accentOrange,
    'accentOrangeSoft': palette.accentOrangeSoft
  };
}

/**
 * 卡片数据推送中心：卡片进程与主应用进程共用同一套查询与推送逻辑。
 * 主应用在启动与账单变化时调用 refreshAllForms 主动同步所有已添加卡片，
 * 弥补卡片仅在添加时与定时刷新时更新数据、不随记账实时变化的问题。
 */
export default class WidgetUpdater {
  /** 卡片进程与主应用进程隔离，各自独立建立 RDB 连接，按时间范围查询收支 */
  static async queryRangeSummary(context: common.Context, start: number, end: number): Promise<RangeSummary> {
    const store = await getWidgetStore(context);
    const predicates = new relationalStore.RdbPredicates(ACCOUNT_TABLE_NAME);
    predicates.greaterThanOrEqualTo('time', start).and().lessThanOrEqualTo('time', end);
    const columns: string[] = ['account_type', 'amount'];
    const result = await store.query(predicates, columns);
    let expenses = 0;
    let income = 0;
    try {
      while (result.goToNextRow()) {
        const accountType = result.getLong(result.getColumnIndex('account_type'));
        const amount = result.getDouble(result.getColumnIndex('amount'));
        if (accountType === 0) {
          expenses += amount;
        } else {
          income += amount;
        }
      }
    } finally {
      // ResultSet 必须关闭，读取抛错时也不能泄漏
      result.close();
    }
    return { expenses: expenses, income: income };
  }

  /** 记录新增卡片：持久化尺寸并加入卡片列表，供主应用主动同步 */
  static async registerForm(context: common.Context, formId: string, dimension: number): Promise<void> {
    if (!formId) {
      return;
    }
    try {
      await PreferenceUtil.loadPreference(context);
      await PreferenceUtil.putPreferenceValue(FORM_DIM_PREFIX + formId, dimension);
      const ids = await WidgetUpdater.readFormIds();
      if (ids.indexOf(formId) < 0) {
        ids.push(formId);
        await PreferenceUtil.putPreferenceValue(PREF_FORM_IDS, ids.join(','));
      }
    } catch (err) {
      Logger.error('卡片注册失败', (err as Error).message);
    }
  }

  /** 卡片删除后从列表移除，避免主应用继续向不存在的卡片推送 */
  static async unregisterForm(context: common.Context, formId: string): Promise<void> {
    try {
      await PreferenceUtil.loadPreference(context);
      const ids = await WidgetUpdater.readFormIds();
      const rest = ids.filter((id: string): boolean => id !== formId);
      if (rest.length !== ids.length) {
        await PreferenceUtil.putPreferenceValue(PREF_FORM_IDS, rest.join(','));
      }
    } catch (err) {
      Logger.error('卡片注销失败', (err as Error).message);
    }
  }

  /** 主应用启动或账单变化时，向所有已添加卡片推送最新数据 */
  static async refreshAllForms(context: common.Context, palette: ThemePalette): Promise<void> {
    try {
      await PreferenceUtil.loadPreference(context);
      const ids = await WidgetUpdater.readFormIds();
      for (const formId of ids) {
        await WidgetUpdater.refreshForm(context, formId, undefined, palette);
      }
    } catch (err) {
      Logger.error('批量刷新卡片失败', (err as Error).message);
    }
  }

  /** 查询今日/本月收支并推送到指定卡片；dimension 缺省时从 Preference 恢复 */
  static async refreshForm(context: common.Context, formId: string, dimension: number | undefined,
    palette: ThemePalette): Promise<void> {
    if (!formId) {
      return;
    }
    try {
      await PreferenceUtil.loadPreference(context);
      let dim = dimension;
      if (dim === undefined) {
        const saved = await PreferenceUtil.getPreferenceValue(FORM_DIM_PREFIX + formId,
          formInfo.FormDimension.Dimension_2_2);
        dim = typeof saved === 'number' ? saved : formInfo.FormDimension.Dimension_2_2;
      }
      const today = await WidgetUpdater.queryRangeSummary(context,
        dayjs().startOf('day').valueOf(), dayjs().endOf('day').valueOf());
      const month = await WidgetUpdater.queryRangeSummary(context,
        dayjs().startOf('month').valueOf(), dayjs().endOf('day').valueOf());
      const isWide = dim === formInfo.FormDimension.Dimension_2_4;
      Logger.info('推送卡片数据', formId, '今日支出', today.expenses, '今日收入', today.income,
        '本月支出', month.expenses, '本月收入', month.income);
      const data = buildCardData(today.expenses.toFixed(2), today.income.toFixed(2),
        month.expenses.toFixed(2), month.income.toFixed(2), palette, isWide);
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } catch (err) {
      Logger.error('卡片数据更新失败', (err as Error).message);
    }
  }

  private static async readFormIds(): Promise<string[]> {
    const raw = await PreferenceUtil.getPreferenceValue(PREF_FORM_IDS, '');
    const text = typeof raw === 'string' ? raw : '';
    if (text.length === 0) {
      return [];
    }
    return text.split(',');
  }
}
