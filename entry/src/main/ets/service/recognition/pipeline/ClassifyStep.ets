import { AccountType } from '../../../models/account/account';
import CategoryRegistry from '../../../models/accountType/CategoryRegistry';
import compositeClassifier from '../classifier/CompositeClassifier';
import { Classifier } from '../classifier/Classifier';
import { PipelineContext } from './PipelineContext';
import { PipelineStep } from './PipelineStep';

/**
 * 智能分类步骤：仅对支出账单用组合分类器重分类，更新分类名并标记为自动分类
 */
export class ClassifyStep implements PipelineStep {
  private classifier: Classifier;

  constructor(classifier?: Classifier) {
    this.classifier = classifier ? classifier : compositeClassifier;
  }

  async handle(ctx: PipelineContext): Promise<void> {
    if (ctx.result.accountType !== AccountType.EXPENSES) {
      return;
    }
    const id = await this.classifier.classify(ctx.result.merchant, '');
    if (id !== null) {
      const names = CategoryRegistry.listNames(AccountType.EXPENSES);
      if (id >= 0 && id < names.length) {
        ctx.result.categoryName = names[id];
        ctx.result.autoClassified = true;
      }
    }
  }
}
