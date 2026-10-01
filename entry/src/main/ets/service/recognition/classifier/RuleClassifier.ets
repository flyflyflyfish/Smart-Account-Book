import { EXPENSE_CLASSIFY_RULES } from '../../../common/classifyRules';
import { Classifier } from './Classifier';

/**
 * 规则分类器：按 common 中配置的关键词规则匹配商家名/识别原文
 */
export class RuleClassifier implements Classifier {
  async classify(merchant: string, rawText: string): Promise<number | null> {
    const target = merchant + ' ' + rawText;
    if (!target.trim()) {
      return null;
    }
    for (const rule of EXPENSE_CLASSIFY_RULES) {
      for (const keyword of rule.keywords) {
        if (target.indexOf(keyword) >= 0) {
          return rule.categoryId;
        }
      }
    }
    return null;
  }
}
