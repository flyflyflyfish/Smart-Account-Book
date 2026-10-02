import { AccountType } from '../../../models/account/account';
import CategoryRegistry from '../../../models/accountType/CategoryRegistry';
import learnedClassifier from '../classifier/LearnedClassifier';
import { RuleClassifier } from '../classifier/RuleClassifier';
import { Classifier } from '../classifier/Classifier';
import { PipelineContext } from './PipelineContext';
import { PipelineStep } from './PipelineStep';

/**
 * 智能分类步骤：
 * 1. 商家记忆优先：历史账单中用户确认过该“商家→分类”时直接复用（含收入侧）
 * 2. 模型/OCR 未给出明确分类（缺失或“其他”）时，仅支出侧用关键词规则兜底
 * 3. 模型已给出明确分类时尊重模型结果，不再覆盖
 */
export class ClassifyStep implements PipelineStep {
  private classifier: Classifier;

  constructor(classifier?: Classifier) {
    this.classifier = classifier ? classifier : new RuleClassifier();
  }

  async handle(ctx: PipelineContext): Promise<void> {
    const accountType = ctx.result.accountType;
    // 商家记忆：同商家历史确认过的分类最可信，直接复用
    const rememberedId = await learnedClassifier.classify(ctx.result.merchant, '', accountType);
    if (rememberedId !== null) {
      ctx.result.categoryName = CategoryRegistry.nameText(rememberedId, accountType);
      ctx.result.autoClassified = true;
      return;
    }
    if (accountType !== AccountType.EXPENSES) {
      return;
    }
    const fallbackName = CategoryRegistry.otherName(AccountType.EXPENSES);
    if (ctx.result.categoryName && ctx.result.categoryName !== fallbackName) {
      return;
    }
    const id = await this.classifier.classify(ctx.result.merchant, '');
    if (id !== null) {
      ctx.result.categoryName = CategoryRegistry.nameText(id, AccountType.EXPENSES);
      ctx.result.autoClassified = true;
    }
  }
}
