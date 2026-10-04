import { AccountExpensesType, AccountIncomeType, AccountType } from '../../../models/account/account';
import { Classifier } from './Classifier';
import learnedClassifier, { LearnedClassifier } from './LearnedClassifier';
import { RuleClassifier } from './RuleClassifier';

/**
 * 组合分类器：按 学习记忆 → 关键词规则（仅支出侧）→ 对应收支侧“其他” 依次尝试
 */
export class CompositeClassifier implements Classifier {
  private learned: LearnedClassifier;
  private rule: RuleClassifier;

  constructor(learned: LearnedClassifier, rule: RuleClassifier) {
    this.learned = learned;
    this.rule = rule;
  }

  async classify(merchant: string, rawText: string, accountType: number = AccountType.EXPENSES): Promise<number | null> {
    const learnedId = await this.learned.classify(merchant, rawText, accountType);
    if (learnedId !== null) {
      return learnedId;
    }
    // 关键词规则只覆盖支出场景，收入侧不套用
    if (accountType === AccountType.EXPENSES) {
      const ruleId = await this.rule.classify(merchant, rawText);
      if (ruleId !== null) {
        return ruleId;
      }
    }
    // 兜底：对应收支侧的“其他”，避免收入账单被错标成支出分类
    return accountType === AccountType.EXPENSES ? AccountExpensesType.OTHER : AccountIncomeType.OTHER;
  }
}

export default new CompositeClassifier(learnedClassifier, new RuleClassifier());
