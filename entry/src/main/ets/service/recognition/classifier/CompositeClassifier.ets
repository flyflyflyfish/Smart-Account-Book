import { AccountExpensesType } from '../../../models/account/account';
import { Classifier } from './Classifier';
import learnedClassifier, { LearnedClassifier } from './LearnedClassifier';
import { RuleClassifier } from './RuleClassifier';

/**
 * 组合分类器：按 学习记忆 → 关键词规则 → 其他支出 依次尝试
 */
export class CompositeClassifier implements Classifier {
  private learned: LearnedClassifier;
  private rule: RuleClassifier;

  constructor(learned: LearnedClassifier, rule: RuleClassifier) {
    this.learned = learned;
    this.rule = rule;
  }

  async classify(merchant: string, rawText: string): Promise<number | null> {
    const learnedId = await this.learned.classify(merchant, rawText);
    if (learnedId !== null) {
      return learnedId;
    }
    const ruleId = await this.rule.classify(merchant, rawText);
    if (ruleId !== null) {
      return ruleId;
    }
    // 兜底：其他支出
    return AccountExpensesType.OTHER;
  }
}

export default new CompositeClassifier(learnedClassifier, new RuleClassifier());
