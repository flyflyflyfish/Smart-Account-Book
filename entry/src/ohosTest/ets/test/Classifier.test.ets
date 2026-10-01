import { describe, it, expect } from '@ohos/hypium';
import CategoryRegistry from '../../../main/ets/models/accountType/CategoryRegistry';
import { RuleClassifier } from '../../../main/ets/service/recognition/classifier/RuleClassifier';
import { LearnedClassifier } from '../../../main/ets/service/recognition/classifier/LearnedClassifier';
import { MerchantCategoryStore } from '../../../main/ets/data/MerchantCategoryRepository';
import MerchantCategory from '../../../main/ets/models/recognition/MerchantCategory';
import { AccountType, AccountExpensesType } from '../../../main/ets/models/account/account';

class FakeMerchantCategoryStore implements MerchantCategoryStore {
  private record: MerchantCategory | null;
  upsertCalled: boolean = false;

  constructor(record: MerchantCategory | null) {
    this.record = record;
  }

  async queryByMerchant(merchant: string): Promise<MerchantCategory | null> {
    return this.record;
  }

  async upsert(record: MerchantCategory): Promise<void> {
    this.upsertCalled = true;
  }

  async clearAll(): Promise<number> {
    return 0;
  }
}

export default function classifierTest() {
  describe('ClassifierTest', () => {
    it('registry_listCount', 0, () => {
      expect(CategoryRegistry.list(AccountType.EXPENSES).length).assertEqual(13);
      expect(CategoryRegistry.list(AccountType.INCOME).length).assertEqual(8);
    });

    it('registry_getByName', 0, () => {
      const item = CategoryRegistry.getByName('早午晚餐', AccountType.EXPENSES);
      expect(item !== undefined).assertTrue();
    });

    it('ruleClassifier_match', 0, async () => {
      const rule = new RuleClassifier();
      const id = await rule.classify('星巴克咖啡', '');
      expect(id).assertEqual(AccountExpensesType.MEALS);
    });

    it('ruleClassifier_noMatch', 0, async () => {
      const rule = new RuleClassifier();
      const id = await rule.classify('', '');
      expect(id).assertNull();
    });

    it('learnedClassifier_hit', 0, async () => {
      const record = new MerchantCategory();
      record.merchant = '星巴克';
      record.categoryId = AccountExpensesType.MEALS;
      record.accountType = AccountType.EXPENSES;
      const store = new FakeMerchantCategoryStore(record);
      const learned = new LearnedClassifier(store);
      const id = await learned.classify('星巴克', '');
      expect(id).assertEqual(AccountExpensesType.MEALS);
    });

    it('learnedClassifier_miss', 0, async () => {
      const store = new FakeMerchantCategoryStore(null);
      const learned = new LearnedClassifier(store);
      const id = await learned.classify('星巴克', '');
      expect(id).assertNull();
    });

    it('learnedClassifier_learn_callsUpsert', 0, async () => {
      const store = new FakeMerchantCategoryStore(null);
      const learned = new LearnedClassifier(store);
      await learned.learn('星巴克', AccountExpensesType.MEALS, AccountType.EXPENSES);
      expect(store.upsertCalled).assertTrue();
    });
  });
}
