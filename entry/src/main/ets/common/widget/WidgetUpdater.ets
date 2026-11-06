import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import relationalStore from '@ohos.data.relationalStore';
import dayjs from 'dayjs';
import { ACCOUNT_TABLE_NAME } from '../../data/schema';
import { Logger } from '../../utils/Logger';
import PreferenceUtil from '../../utils/PreferenceUtil';
import { withAlpha, ThemePalette } from '../theme/Theme';
import { FORM_DIM_PREFIX, FORM_RANGE_PREFIX, PREF_FORM_IDS, PREF_SECOND_TAB_STYLE, PREF_WIDGET_SUMMARY,
  SECOND_TAB_STYLE_AI, SECOND_TAB_STYLE_LEDGER, WIDGET_RANGE_MONTH, WIDGET_RANGE_TODAY } from '../constants';

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

/** 单口径收支快照：key 为日期（YYYY-MM-DD）或月份（YYYY-MM）标记，卡片进程据此做跨日/跨月归零 */
export interface RangeSummaryEntry {
  key: string;
  expenses: number;
  income: number;
}

/** 小组件两口径收支缓存：主应用查库后写入 Preferences，卡片进程只读缓存推送 */
export interface WidgetSummaryCache {
  today: RangeSummaryEntry;
  month: RangeSummaryEntry;
}

// 各卡片的「+」菜单展开状态（进程内内存态，不持久化；进程重启后自动收起）
const formMenuOpenStates = new Map<string, boolean>();

/** 组装推送给卡片的全部数据：所选口径的收支金额、口径标记、菜单展开标记、宽窄标记、第三入口样式与主题色值 */
export function buildCardData(expenses: string, income: string, range: string, menuVisible: string,
  palette: ThemePalette, isWide: boolean, thirdEntry: string): Record<string, string> {
  // 三个快捷入口取主色锚定的图表色板前三色：同一色系、色相渐变、互不相同
  const chart = palette.chart;
  const addColor = chart.length > 0 ? chart[0] : palette.primary;
  const cameraColor = chart.length > 1 ? chart[1] : addColor;
  const aiColor = chart.length > 2 ? chart[2] : addColor;
  const softAlpha = palette.isDark ? 0.22 : 0.16;
  return {
    'expenses': expenses,
    'income': income,
    'range': range,
    'menuVisible': menuVisible,
    'isWide': isWide ? '1' : '0',
    'thirdEntry': thirdEntry === SECOND_TAB_STYLE_LEDGER ? SECOND_TAB_STYLE_LEDGER : SECOND_TAB_STYLE_AI,
    'entryAdd': addColor,
    'entryCamera': cameraColor,
    'entryCameraSoft': withAlpha(cameraColor, softAlpha),
    'entryAi': aiColor,
    'entryAiSoft': withAlpha(aiColor, softAlpha),
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
 * 卡片数据推送中心：卡片进程与主应用进程共用同一套推送逻辑。
 * 数据源职责分离：数据库只在主应用进程查询——查今日/本月两口径各一次，
 * 连同日期/月份标记持久化为缓存；卡片进程的定时/交互刷新只读缓存推送，
 * 不再跨进程读主应用数据库（多进程读库可能读到空/旧库，把正确金额覆盖成 0.00）。
 * 缓存按标记跨日/跨月自动归零；主应用在启动、回前台与账单变化时主动刷新全部卡片。
 */
export default class WidgetUpdater {
  /** 查询指定时间范围的收支（仅主应用进程调用；卡片进程读持久化缓存，不开库） */
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
      // 卡片进程写入前先重载：避免用旧缓存实例 flush 时把主进程新写入的数据回退
      await PreferenceUtil.reloadPreference(context);
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
      await PreferenceUtil.reloadPreference(context);
      const ids = await WidgetUpdater.readFormIds();
      const rest = ids.filter((id: string): boolean => id !== formId);
      if (rest.length !== ids.length) {
        await PreferenceUtil.putPreferenceValue(PREF_FORM_IDS, rest.join(','));
      }
    } catch (err) {
      Logger.error('卡片注销失败', (err as Error).message);
    }
  }

  /** 主应用启动、回前台或账单变化时，向所有已添加卡片推送最新数据 */
  static async refreshAllForms(context: common.Context, palette: ThemePalette): Promise<void> {
    try {
      // 先从磁盘重载：卡片可能是本进程运行期间由卡片进程注册的，缓存实例里还没有其 formId
      await PreferenceUtil.reloadPreference(context);
      const cache = await WidgetUpdater.querySummaryCache(context);
      if (!cache) {
        return;
      }
      const ids = await WidgetUpdater.readFormIds();
      for (const formId of ids) {
        await WidgetUpdater.refreshForm(context, formId, undefined, palette, cache);
      }
    } catch (err) {
      Logger.error('批量刷新卡片失败', (err as Error).message);
    }
  }

  /**
   * 查询今日/本月两口径收支并持久化为缓存（仅主应用进程调用）：
   * 卡片进程随后的定时/交互刷新只读缓存，不再跨进程查库
   */
  static async querySummaryCache(context: common.Context): Promise<WidgetSummaryCache | undefined> {
    try {
      const today = await WidgetUpdater.queryRangeSummary(context,
        dayjs().startOf('day').valueOf(), dayjs().endOf('day').valueOf());
      const month = await WidgetUpdater.queryRangeSummary(context,
        dayjs().startOf('month').valueOf(), dayjs().endOf('day').valueOf());
      const cache = WidgetUpdater.buildSummaryCache(today, month);
      await WidgetUpdater.persistSummaryCache(cache);
      return cache;
    } catch (err) {
      Logger.error('查询卡片收支失败', (err as Error).message);
      return undefined;
    }
  }

  /** 组装两口径缓存，带上当前日期/月份标记供卡片进程做跨日/跨月归零判定 */
  static buildSummaryCache(today: RangeSummary, month: RangeSummary): WidgetSummaryCache {
    const cache: WidgetSummaryCache = {
      today: { key: dayjs().format('YYYY-MM-DD'), expenses: today.expenses, income: today.income },
      month: { key: dayjs().format('YYYY-MM'), expenses: month.expenses, income: month.income }
    };
    return cache;
  }

  static async persistSummaryCache(cache: WidgetSummaryCache): Promise<void> {
    await PreferenceUtil.putPreferenceValue(PREF_WIDGET_SUMMARY, JSON.stringify(cache));
  }

  /** 读取主应用持久化的收支缓存；无缓存（应用从未启动过）返回 undefined */
  static async loadSummaryCache(): Promise<WidgetSummaryCache | undefined> {
    const raw = String(await PreferenceUtil.getPreferenceValue(PREF_WIDGET_SUMMARY, ''));
    if (raw.length === 0) {
      return undefined;
    }
    try {
      const parsed = JSON.parse(raw) as WidgetSummaryCache;
      if (!parsed || !parsed.today || !parsed.month) {
        return undefined;
      }
      if (typeof parsed.today.key !== 'string' || typeof parsed.today.expenses !== 'number' ||
        typeof parsed.today.income !== 'number') {
        return undefined;
      }
      if (typeof parsed.month.key !== 'string' || typeof parsed.month.expenses !== 'number' ||
        typeof parsed.month.income !== 'number') {
        return undefined;
      }
      return parsed;
    } catch (err) {
      return undefined;
    }
  }

  /** 跨日/跨月归零：缓存写入时的“今日/本月”已过期时，对应口径从 0 重新开始 */
  static rolloverSummary(cache: WidgetSummaryCache): WidgetSummaryCache {
    const todayKey = dayjs().format('YYYY-MM-DD');
    const monthKey = dayjs().format('YYYY-MM');
    const today: RangeSummaryEntry = cache.today.key === todayKey
      ? cache.today
      : { key: todayKey, expenses: 0, income: 0 };
    const month: RangeSummaryEntry = cache.month.key === monthKey
      ? cache.month
      : { key: monthKey, expenses: 0, income: 0 };
    const rolled: WidgetSummaryCache = { today: today, month: month };
    return rolled;
  }

  /** 卡片进程用：读取持久化缓存并做跨日/跨月归零；无缓存返回 undefined */
  static async loadRolloverSummary(): Promise<WidgetSummaryCache | undefined> {
    const cache = await WidgetUpdater.loadSummaryCache();
    return cache ? WidgetUpdater.rolloverSummary(cache) : undefined;
  }

  /** 读取卡片已保存的统计口径，未设置时默认今日 */
  static async readFormRange(formId: string): Promise<string> {
    const saved = await PreferenceUtil.getPreferenceValue(FORM_RANGE_PREFIX + formId, WIDGET_RANGE_TODAY);
    const range = typeof saved === 'string' ? saved : WIDGET_RANGE_TODAY;
    return range === WIDGET_RANGE_MONTH ? WIDGET_RANGE_MONTH : WIDGET_RANGE_TODAY;
  }

  /** 切换小卡「+」菜单的展开/收起状态 */
  static toggleFormMenu(formId: string): void {
    const next = !formMenuOpenStates.get(formId);
    if (next) {
      formMenuOpenStates.set(formId, true);
    } else {
      formMenuOpenStates.delete(formId);
    }
  }

  /**
   * 把指定口径的收支缓存推送到指定卡片；dimension 缺省时从 Preference 恢复。
   * 不查数据库：金额一律取自传入缓存（cache），卡片进程调用时传读取并归零后的缓存
   */
  static async refreshForm(context: common.Context, formId: string, dimension: number | undefined,
    palette: ThemePalette, cache: WidgetSummaryCache): Promise<void> {
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
      const isWide = dim === formInfo.FormDimension.Dimension_2_4;
      // 小卡（2*2）固定展示今日收支，不使用口径切换；大卡（2*4）按已保存口径展示
      const range = isWide ? await WidgetUpdater.readFormRange(formId) : WIDGET_RANGE_TODAY;
      const entry = range === WIDGET_RANGE_MONTH ? cache.month : cache.today;
      const menuVisible = formMenuOpenStates.get(formId) === true ? '1' : '0';
      // 第三入口跟随底部第二页签样式：AI 助手 / 账本
      const savedTabStyle = await PreferenceUtil.getPreferenceValue(PREF_SECOND_TAB_STYLE, SECOND_TAB_STYLE_AI);
      const thirdEntry = savedTabStyle === SECOND_TAB_STYLE_LEDGER ? SECOND_TAB_STYLE_LEDGER : SECOND_TAB_STYLE_AI;
      Logger.info('推送卡片数据', formId, range, '支出', entry.expenses, '收入', entry.income);
      const data = buildCardData(entry.expenses.toFixed(2), entry.income.toFixed(2),
        range, menuVisible, palette, isWide, thirdEntry);
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
