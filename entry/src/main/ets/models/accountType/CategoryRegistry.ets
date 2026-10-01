import { AccountType } from '../account/account';
import AccountTypeModel from './AccountTypeModel';
import { expenses, incomes } from './accountType';
import { EXPENSE_CATEGORY_NAMES, INCOME_CATEGORY_NAMES } from '../../common/constants';

/**
 * 分类注册表：用 Map 按 id 索引分类，替代数组下标当 id 的隐式约定
 */
class CategoryRegistry {
  private expensesMap: Map<number, AccountTypeModel> = new Map();
  private incomesMap: Map<number, AccountTypeModel> = new Map();

  constructor() {
    expenses.forEach((item: AccountTypeModel) => {
      this.expensesMap.set(item.id, item);
    });
    incomes.forEach((item: AccountTypeModel) => {
      this.incomesMap.set(item.id, item);
    });
  }

  private getMap(accountType: number): Map<number, AccountTypeModel> {
    return accountType === AccountType.EXPENSES ? this.expensesMap : this.incomesMap;
  }

  getById(id: number, accountType: number): AccountTypeModel | undefined {
    return this.getMap(accountType).get(id);
  }

  /**
   * 按名称查找分类，供图片识别结果智能匹配分类使用
   */
  getByName(name: string, accountType: number): AccountTypeModel | undefined {
    const names = this.listNameTexts(accountType);
    const index = names.indexOf(name);
    if (index < 0) {
      return undefined;
    }
    return this.list(accountType)[index];
  }

  list(accountType: number): AccountTypeModel[] {
    return accountType === AccountType.EXPENSES ? expenses : incomes;
  }

  /**
   * 该收支侧全部分类名（纯字符串），供云端识别拼接提示词与校验分类使用
   */
  listNames(accountType: number): string[] {
    return this.listNameTexts(accountType);
  }

  // 纯字符串分类名，与 list 顺序一致，避免依赖资源上下文
  private listNameTexts(accountType: number): string[] {
    return accountType === AccountType.EXPENSES ? EXPENSE_CATEGORY_NAMES : INCOME_CATEGORY_NAMES;
  }
}

export default new CategoryRegistry();
