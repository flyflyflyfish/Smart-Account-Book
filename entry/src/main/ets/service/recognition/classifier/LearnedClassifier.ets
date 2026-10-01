import MerchantCategory from '../../../models/recognition/MerchantCategory';
import MerchantCategoryRepository, { MerchantCategoryStore } from '../../../data/MerchantCategoryRepository';
import { Classifier } from './Classifier';

/**
 * 学习分类器：优先命中历史“商家 → 分类”记忆，入账后由确认页调用 learn 写入
 */
export class LearnedClassifier implements Classifier {
  private repository: MerchantCategoryStore;

  constructor(repository: MerchantCategoryStore) {
    this.repository = repository;
  }

  async classify(merchant: string, rawText: string): Promise<number | null> {
    if (!merchant) {
      return null;
    }
    const record = await this.repository.queryByMerchant(merchant);
    if (record) {
      return record.categoryId;
    }
    return null;
  }

  // 用户确认分类并入账后调用，记忆“商家 → 分类”
  async learn(merchant: string, categoryId: number, accountType: number): Promise<void> {
    if (!merchant) {
      return;
    }
    const record = new MerchantCategory();
    record.merchant = merchant;
    record.categoryId = categoryId;
    record.accountType = accountType;
    record.updatedAt = Date.now();
    await this.repository.upsert(record);
  }

  // 清除全部学习到的“商家 → 分类”记忆，返回删除条数
  async clearLearned(): Promise<number> {
    return this.repository.clearAll();
  }
}

export default new LearnedClassifier(new MerchantCategoryRepository());
