import MerchantCategory from '../../../models/recognition/MerchantCategory';
import MerchantCategoryRepository, { MerchantCategoryStore } from '../../../data/MerchantCategoryRepository';
import MerchantLearningSync from '../../MerchantLearningSync';
import { Logger } from '../../../utils/Logger';
import { Classifier } from './Classifier';

/**
 * 学习分类器：优先命中历史“商家 → 分类”记忆，入账后由确认页调用 learn 写入
 */
export class LearnedClassifier implements Classifier {
  private repository: MerchantCategoryStore;

  constructor(repository: MerchantCategoryStore) {
    this.repository = repository;
  }

  async classify(merchant: string, rawText: string, accountType?: number): Promise<number | null> {
    if (!merchant) {
      return null;
    }
    const record = await this.repository.queryByMerchant(merchant);
    // 传入 accountType 时要求记忆的收支侧一致，避免支出商家命中收入分类
    if (record && (accountType === undefined || record.accountType === accountType)) {
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
    // 学习成功后即时合并上传；失败不影响本地学习，下次全量同步按内容差异补推
    try {
      await MerchantLearningSync.pushAfterLearn();
    } catch (err) {
      Logger.error('学习记忆上传云端失败', (err as Error).message);
    }
  }

  // 清除全部学习到的“商家 → 分类”记忆，返回删除条数
  async clearLearned(): Promise<number> {
    return this.repository.clearAll();
  }
}

export default new LearnedClassifier(new MerchantCategoryRepository());
