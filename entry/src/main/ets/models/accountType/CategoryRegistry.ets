import { AccountType } from '../account/account';
import AccountTypeModel from './AccountTypeModel';
import { expenses, incomes } from './accountType';

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
    const list = this.list(accountType);
    return list.find((item: AccountTypeModel): boolean => this.resolveName(item.name) === name);
  }

  list(accountType: number): AccountTypeModel[] {
    return accountType === AccountType.EXPENSES ? expenses : incomes;
  }

  /**
   * 该收支侧全部分类名（已解析为字符串），供云端识别拼接提示词与校验分类使用
   */
  listNames(accountType: number): string[] {
    return this.list(accountType).map((item: AccountTypeModel): string => this.resolveName(item.name));
  }

  // 分类名称是资源引用，统一解析成字符串再比较
  private resolveName(name: ResourceStr): string {
    if (typeof name === 'string') {
      return name;
    }
    return getContext().resourceManager.getStringSync(name);
  }
}

export default new CategoryRegistry();
