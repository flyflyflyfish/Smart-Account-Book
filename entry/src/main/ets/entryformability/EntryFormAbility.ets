import { formBindingData, FormExtensionAbility, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import relationalStore from '@ohos.data.relationalStore';
import dayjs from 'dayjs';
import { ACCOUNT_TABLE_NAME } from '../data/schema';
import { Logger } from '../utils/Logger';

const DB_FILENAME: string = 'account.db';
const IDENTITY_KEY: string = 'ohos.extra.param.key.form_identity';

interface TodaySummary {
  expenses: number;
  income: number;
}

/**
 * 记账卡片扩展：提供卡片创建、刷新等生命周期回调，展示今日支出/收入
 */
export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = this.getFormId(want);
    this.refreshCard(formId);
    const data: Record<string, string> = { 'expenses': '--', 'income': '--' };
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    this.refreshCard(formId);
  }

  private getFormId(want: Want): string {
    const params = want.parameters;
    if (params) {
      const id = params[IDENTITY_KEY];
      if (typeof id === 'string') {
        return id;
      }
    }
    return '';
  }

  private async refreshCard(formId: string): Promise<void> {
    if (!formId) {
      return;
    }
    try {
      const summary = await this.queryTodaySummary();
      const data: Record<string, string> = {
        'expenses': summary.expenses.toFixed(2),
        'income': summary.income.toFixed(2)
      };
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } catch (err) {
      Logger.error('卡片数据更新失败', (err as Error).message);
    }
  }

  // 卡片进程与主应用进程隔离，独立建立 RDB 连接查询今日收支
  private async queryTodaySummary(): Promise<TodaySummary> {
    const config: relationalStore.StoreConfig = {
      name: DB_FILENAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(this.context, config);
    const start = dayjs().startOf('day').valueOf();
    const end = dayjs().endOf('day').valueOf();
    const predicates = new relationalStore.RdbPredicates(ACCOUNT_TABLE_NAME);
    predicates.greaterThanOrEqualTo('time', start).and().lessThanOrEqualTo('time', end);
    const columns: string[] = ['account_type', 'amount'];
    const result = await store.query(predicates, columns);
    let expenses = 0;
    let income = 0;
    while (result.goToNextRow()) {
      const accountType = result.getLong(result.getColumnIndex('account_type'));
      const amount = result.getDouble(result.getColumnIndex('amount'));
      if (accountType === 0) {
        expenses += amount;
      } else {
        income += amount;
      }
    }
    result.close();
    return { expenses: expenses, income: income };
  }
}
