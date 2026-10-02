import { AccountType } from '../account/account';
import AccountTypeModel from './AccountTypeModel';
import CategoryStore from './CategoryStore';

/**
 * 分类注册表：统一入口委托 CategoryStore，支持用户自定义分类（增/减/恢复默认）
 */
class CategoryRegistry {
  getById(id: number, accountType: number): AccountTypeModel {
    return CategoryStore.getById(id, accountType);
  }

  /**
   * 按名称查找当前可选分类，供图片识别结果智能匹配分类使用
   */
  getByName(name: string, accountType: number): AccountTypeModel | undefined {
    return CategoryStore.getByName(name, accountType);
  }

  /**
   * 该收支侧“其他”分类（恒存在），供识别结果兜底
   */
  getOther(accountType: number): AccountTypeModel {
    return CategoryStore.getOther(accountType);
  }

  list(accountType: number): AccountTypeModel[] {
    return CategoryStore.list(accountType);
  }

  /**
   * 该收支侧当前可选分类名（纯字符串），供云端识别拼接提示词与校验分类使用
   */
  listNames(accountType: number): string[] {
    return CategoryStore.listNames(accountType);
  }

  /**
   * 分类 id 对应的纯文本名称（含被隐藏分类），供识别流水线回写分类名使用
   */
  nameText(id: number, accountType: number): string {
    return CategoryStore.nameText(id, accountType);
  }

  /**
   * 该收支侧“其他”分类名称，供识别流水线判断模型分类是否为兜底值
   */
  otherName(accountType: number): string {
    return CategoryStore.otherName(accountType);
  }
}

export default new CategoryRegistry();
