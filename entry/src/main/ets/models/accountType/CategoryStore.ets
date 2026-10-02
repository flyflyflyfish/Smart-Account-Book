import common from '@ohos.app.ability.common';
import { AccountExpensesType, AccountIncomeType, AccountType } from '../account/account';
import AccountTypeModel from './AccountTypeModel';
import { expenses, incomes } from './accountType';
import {
  EXPENSE_CATEGORY_NAMES,
  INCOME_CATEGORY_NAMES,
  PREF_CATEGORY_CONFIG
} from '../../common/constants';
import PreferenceUtil from '../../utils/PreferenceUtil';
import { Logger } from '../../utils/Logger';

// 自定义分类 id 起始值，避开默认分类的枚举 id（0-12）
export const CATEGORY_CUSTOM_ID_BASE: number = 1000;

// 分类名称最大长度
export const CATEGORY_NAME_MAX_LENGTH: number = 6;

/**
 * 分类图标候选项：key 持久化存储，icon 供 UI 展示
 */
export class CategoryIconOption {
  key: string;
  icon: ResourceStr;

  constructor(key: string, icon: ResourceStr) {
    this.key = key;
    this.icon = icon;
  }
}

/**
 * 分类颜色候选项：key 持久化存储，color 供 UI 展示
 */
export class CategoryColorOption {
  key: string;
  color: ResourceStr;

  constructor(key: string, color: ResourceStr) {
    this.key = key;
    this.color = color;
  }
}

// JSON 反序列化的原始结构
class CustomCategoryRaw {
  id: number = 0;
  name: string = '';
  iconKey: string = 'other';
  colorKey: string = 'green';
}

class CategorySideConfig {
  custom: CustomCategoryRaw[] = [];
  hidden: number[] = [];

  reset(): void {
    this.custom = [];
    this.hidden = [];
  }
}

class CategoryConfig {
  nextId: number = CATEGORY_CUSTOM_ID_BASE;
  expenses: CategorySideConfig = new CategorySideConfig();
  incomes: CategorySideConfig = new CategorySideConfig();
}

export const CATEGORY_ICON_OPTIONS: CategoryIconOption[] = [
  new CategoryIconOption('meals', $r('app.media.meals')),
  new CategoryIconOption('medical', $r('app.media.medical')),
  new CategoryIconOption('traffic', $r('app.media.traffic')),
  new CategoryIconOption('house', $r('app.media.house')),
  new CategoryIconOption('tobacco', $r('app.media.tobacco')),
  new CategoryIconOption('educate', $r('app.media.educate')),
  new CategoryIconOption('communication', $r('app.media.communication')),
  new CategoryIconOption('social', $r('app.media.social')),
  new CategoryIconOption('invest', $r('app.media.invest')),
  new CategoryIconOption('shoping', $r('app.media.shoping')),
  new CategoryIconOption('game', $r('app.media.game')),
  new CategoryIconOption('loan', $r('app.media.loan')),
  new CategoryIconOption('salary', $r('app.media.salary')),
  new CategoryIconOption('bonus', $r('app.media.bonus')),
  new CategoryIconOption('interest', $r('app.media.Interest')),
  new CategoryIconOption('part_time', $r('app.media.part_time')),
  new CategoryIconOption('red_envalope', $r('app.media.red_envalope')),
  new CategoryIconOption('borrow', $r('app.media.borrow')),
  new CategoryIconOption('other', $r('app.media.other'))
];

export const CATEGORY_COLOR_OPTIONS: CategoryColorOption[] = [
  new CategoryColorOption('green', $r('app.color.green')),
  new CategoryColorOption('blue', $r('app.color.blue')),
  new CategoryColorOption('yellow', $r('app.color.yellow')),
  new CategoryColorOption('orange', $r('app.color.orange')),
  new CategoryColorOption('red', $r('app.color.red')),
  new CategoryColorOption('purple', $r('app.color.purple'))
];

/**
 * 分类存储：在默认分类基础上支持
 * - 新增自定义分类（名称 + 图标 + 颜色）
 * - 删除（隐藏）默认或自定义分类，历史账单仍按原分类名展示
 * - 恢复默认分类
 * 配置持久化到 Preferences，应用启动时在 EntryAbility 中初始化
 */
class CategoryStore {
  private config: CategoryConfig = new CategoryConfig();
  private initPromise: Promise<void> | undefined = undefined;
  // 可见分类（默认 - 隐藏 + 自定义 - 隐藏），供记账选择、AI 提示词使用
  private visibleExpenses: AccountTypeModel[] = expenses;
  private visibleIncomes: AccountTypeModel[] = incomes;
  // 全量分类（含被隐藏的），供历史账单反查名称
  private allExpenses: Map<number, AccountTypeModel> = new Map();
  private allIncomes: Map<number, AccountTypeModel> = new Map();

  // 应用启动时初始化，可重复调用（共享同一个 Promise）
  init(context: common.Context): Promise<void> {
    if (!this.initPromise) {
      this.initPromise = this.doInit(context);
    }
    return this.initPromise;
  }

  private async doInit(context: common.Context): Promise<void> {
    try {
      const raw = await PreferenceUtil.getPreferenceValue(PREF_CATEGORY_CONFIG, '');
      if (typeof raw === 'string' && raw.length > 0) {
        this.config = this.parseConfig(raw);
      }
    } catch (err) {
      Logger.error('加载自定义分类配置失败', (err as Error).message);
    }
    this.rebuild();
  }

  // 反序列化并逐字段校验，非法数据回退默认配置
  private parseConfig(text: string): CategoryConfig {
    const result = new CategoryConfig();
    try {
      const raw = JSON.parse(text) as CategoryConfig;
      if (raw && typeof raw.nextId === 'number' && raw.nextId >= CATEGORY_CUSTOM_ID_BASE) {
        result.nextId = raw.nextId;
      }
      this.parseSide(raw?.expenses, result.expenses);
      this.parseSide(raw?.incomes, result.incomes);
    } catch (err) {
      Logger.error('解析自定义分类配置失败', (err as Error).message);
      return new CategoryConfig();
    }
    return result;
  }

  private parseSide(raw: CategorySideConfig | undefined, target: CategorySideConfig): void {
    if (!raw) {
      return;
    }
    if (Array.isArray(raw.custom)) {
      raw.custom.forEach((item: CustomCategoryRaw) => {
        if (item && typeof item.id === 'number' && typeof item.name === 'string' && item.name.length > 0) {
          const custom = new CustomCategoryRaw();
          custom.id = item.id;
          custom.name = item.name;
          custom.iconKey = typeof item.iconKey === 'string' ? item.iconKey : 'other';
          custom.colorKey = typeof item.colorKey === 'string' ? item.colorKey : 'green';
          target.custom.push(custom);
        }
      });
    }
    if (Array.isArray(raw.hidden)) {
      raw.hidden.forEach((id: number) => {
        // 默认分类与自定义分类的 id 均可隐藏；自定义分类保留在 custom 中以便历史账单反查名称
        if (typeof id === 'number' && id >= 0) {
          target.hidden.push(id);
        }
      });
    }
  }

  private sideConfig(accountType: number): CategorySideConfig {
    return accountType === AccountType.EXPENSES ? this.config.expenses : this.config.incomes;
  }

  private defaultList(accountType: number): AccountTypeModel[] {
    return accountType === AccountType.EXPENSES ? expenses : incomes;
  }

  private defaultNames(accountType: number): string[] {
    return accountType === AccountType.EXPENSES ? EXPENSE_CATEGORY_NAMES : INCOME_CATEGORY_NAMES;
  }

  private rebuild(): void {
    this.visibleExpenses = this.buildSide(AccountType.EXPENSES);
    this.visibleIncomes = this.buildSide(AccountType.INCOME);
    this.allExpenses = this.buildAllMap(AccountType.EXPENSES);
    this.allIncomes = this.buildAllMap(AccountType.INCOME);
  }

  private buildSide(accountType: number): AccountTypeModel[] {
    const side = this.sideConfig(accountType);
    const result: AccountTypeModel[] = [];
    this.defaultList(accountType).forEach((item: AccountTypeModel) => {
      if (side.hidden.indexOf(item.id) < 0) {
        result.push(item);
      }
    });
    side.custom.forEach((item: CustomCategoryRaw) => {
      if (side.hidden.indexOf(item.id) < 0) {
        result.push(this.toModel(item));
      }
    });
    return result;
  }

  private buildAllMap(accountType: number): Map<number, AccountTypeModel> {
    const map: Map<number, AccountTypeModel> = new Map();
    this.defaultList(accountType).forEach((item: AccountTypeModel) => {
      map.set(item.id, item);
    });
    this.sideConfig(accountType).custom.forEach((item: CustomCategoryRaw) => {
      map.set(item.id, this.toModel(item));
    });
    return map;
  }

  private toModel(item: CustomCategoryRaw): AccountTypeModel {
    return new AccountTypeModel(item.id, item.name, CategoryStore.iconByKey(item.iconKey),
      CategoryStore.colorByKey(item.colorKey));
  }

  static iconByKey(key: string): ResourceStr {
    const matched = CATEGORY_ICON_OPTIONS.find((option: CategoryIconOption): boolean => option.key === key);
    return matched ? matched.icon : $r('app.media.other');
  }

  static colorByKey(key: string): ResourceStr {
    const matched = CATEGORY_COLOR_OPTIONS.find((option: CategoryColorOption): boolean => option.key === key);
    return matched ? matched.color : $r('app.color.green');
  }

  // 该收支侧当前可选分类
  list(accountType: number): AccountTypeModel[] {
    return accountType === AccountType.EXPENSES ? this.visibleExpenses : this.visibleIncomes;
  }

  // 该收支侧当前可选分类名（纯字符串），供识别提示词与校验使用
  listNames(accountType: number): string[] {
    return this.list(accountType).map((item: AccountTypeModel): string => this.nameText(item.id, accountType));
  }

  // 按 id 反查分类（含被隐藏分类），查不到回退“其他”，保证历史账单可渲染
  getById(id: number, accountType: number): AccountTypeModel {
    const map = accountType === AccountType.EXPENSES ? this.allExpenses : this.allIncomes;
    const matched = map.get(id);
    return matched ? matched : this.getOther(accountType);
  }

  // 按名称查找当前可选分类
  getByName(name: string, accountType: number): AccountTypeModel | undefined {
    const list = this.list(accountType);
    const matched = list.find((item: AccountTypeModel): boolean => this.nameText(item.id, accountType) === name);
    return matched;
  }

  // 该收支侧“其他”分类（默认分类恒存在），供识别兜底
  getOther(accountType: number): AccountTypeModel {
    const otherId = accountType === AccountType.EXPENSES ? AccountExpensesType.OTHER : AccountIncomeType.OTHER;
    const matched = this.defaultList(accountType).find((item: AccountTypeModel): boolean => item.id === otherId);
    return matched ? matched : this.defaultList(accountType)[0];
  }

  otherName(accountType: number): string {
    return this.nameText(this.getOther(accountType).id, accountType);
  }

  // 分类 id 对应的纯文本名称，供导出等非 UI 场景使用
  nameText(id: number, accountType: number): string {
    const map = accountType === AccountType.EXPENSES ? this.allExpenses : this.allIncomes;
    const matched = map.get(id);
    if (!matched) {
      return this.otherName(accountType);
    }
    if (typeof matched.name === 'string') {
      return matched.name;
    }
    const names = this.defaultNames(accountType);
    return names[matched.id] ?? names[names.length - 1];
  }

  isCustom(id: number): boolean {
    return id >= CATEGORY_CUSTOM_ID_BASE;
  }

  // 新增自定义分类，调用方需先做非空、长度与重名校验
  add(accountType: number, name: string, iconKey: string, colorKey: string): AccountTypeModel {
    const side = this.sideConfig(accountType);
    const custom = new CustomCategoryRaw();
    custom.id = this.config.nextId;
    custom.name = name;
    custom.iconKey = iconKey;
    custom.colorKey = colorKey;
    side.custom.push(custom);
    this.config.nextId += 1;
    this.persist();
    this.rebuild();
    return this.toModel(custom);
  }

  // 删除分类：默认分类仅隐藏，自定义分类从可选列表移除；至少保留一个分类
  remove(accountType: number, id: number): boolean {
    const side = this.sideConfig(accountType);
    const visible = this.list(accountType);
    if (visible.length <= 1) {
      return false;
    }
    // 默认与自定义分类统一记入隐藏列表；自定义分类保留在 custom 中以便历史账单反查名称
    if (side.hidden.indexOf(id) < 0) {
      side.hidden.push(id);
    }
    this.persist();
    this.rebuild();
    return true;
  }

  // 恢复该收支侧默认分类：清除隐藏记录与自定义分类
  restoreDefaults(accountType: number): void {
    this.sideConfig(accountType).reset();
    this.persist();
    this.rebuild();
  }

  private persist(): void {
    PreferenceUtil.putPreferenceValue(PREF_CATEGORY_CONFIG, JSON.stringify(this.config)).catch((): void => {
      Logger.error('保存自定义分类配置失败');
    });
  }
}

export default new CategoryStore();
