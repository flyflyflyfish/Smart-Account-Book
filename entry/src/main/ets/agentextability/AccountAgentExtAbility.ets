import { common, Want, AgentExtensionAbility } from '@kit.AbilityKit';
import {
  OnDataCallback,
  RequestContext,
  Role,
  Server,
  TaskState,
  createA2AServer
} from '@kit.AgentFrameworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import relationalStore from '@ohos.data.relationalStore';
import util from '@ohos.util';
import dayjs from 'dayjs';
import { ACCOUNT_TABLE_NAME } from '../data/schema';
import { AccountType } from '../models/account/account';
import CategoryRegistry from '../models/accountType/CategoryRegistry';
import CategoryStore from '../models/accountType/CategoryStore';
import { Logger } from '../utils/Logger';

const TAG: string = 'AccountAgent';
const DB_FILENAME: string = 'account.db';

// Agent 侧独立 RDB 连接（进程级缓存）：小艺可能冷启动拉起本扩展而主进程 DBUtil 未初始化，
// 与卡片 WidgetUpdater 相同思路，各自建立只读连接，不依赖 DBUtil 单例
let agentStorePromise: Promise<relationalStore.RdbStore> | undefined = undefined;

function getAgentStore(context: common.Context): Promise<relationalStore.RdbStore> {
  if (!agentStorePromise) {
    const config: relationalStore.StoreConfig = {
      name: DB_FILENAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    agentStorePromise = relationalStore.getRdbStore(context, config).catch((err: BusinessError) => {
      agentStorePromise = undefined;
      throw new Error('数据库连接失败: ' + err.message);
    });
  }
  return agentStorePromise;
}

/** 查询的时间口径：本月/上月/今年/去年 */
interface TimeScope {
  label: string;
  start: number;
  end: number;
}

function resolveTimeScope(userInput: string): TimeScope {
  const now = dayjs();
  if (userInput.indexOf('去年') >= 0) {
    const lastYear = now.subtract(1, 'year');
    const scope: TimeScope = {
      label: '去年',
      start: lastYear.startOf('year').valueOf(),
      end: lastYear.endOf('year').valueOf()
    };
    return scope;
  }
  if (userInput.indexOf('上月') >= 0) {
    const lastMonth = now.subtract(1, 'month');
    const scope: TimeScope = {
      label: '上月',
      start: lastMonth.startOf('month').valueOf(),
      end: lastMonth.endOf('month').valueOf()
    };
    return scope;
  }
  if (userInput.indexOf('今年') >= 0) {
    const scope: TimeScope = {
      label: '今年',
      start: now.startOf('year').valueOf(),
      end: now.endOf('year').valueOf()
    };
    return scope;
  }
  const scope: TimeScope = {
    label: '本月',
    start: now.startOf('month').valueOf(),
    end: now.endOf('month').valueOf()
  };
  return scope;
}

/** 单个分类的汇总条目 */
interface CategorySummaryItem {
  name: string;
  amount: number;
  count: number;
}

/** 一段时间的账单汇总 */
interface BillSummary {
  expenses: number;
  income: number;
  expenseItems: CategorySummaryItem[];
  incomeItems: CategorySummaryItem[];
}

/** 返回给小艺的结构化汇总（经 JSON.stringify 后作为 artifact 数据） */
interface SummaryPayload {
  scope: string;
  expenses: number;
  income: number;
  expenseItems: CategorySummaryItem[];
  incomeItems: CategorySummaryItem[];
}

/** 小艺感知建议候选（AgentChips） */
interface SuggestionCandidate {
  text: string;
  reply: string;
}

/**
 * 记账 A2A 智能体（端侧）：
 * 小艺对话中将"查询账单汇总"类请求路由到本扩展，
 * 扩展进程内直连本地 RDB 按时间口径聚合收支与分类明细，
 * 以 Artifact（结构化 JSON + 文本摘要）返回给小艺。
 */
export default class AccountAgentExtAbility extends AgentExtensionAbility {
  private server: Server | null = null;

  private agentOnData: OnDataCallback = (method: string, context: RequestContext): void => {
    switch (method) {
      case 'Execute': {
        const executeTaskId: string = context.getTaskId() ?? '';
        this.handleExecute(executeTaskId, context).catch((err: BusinessError): void => {
          Logger.error(TAG, '查询账单汇总失败', err.message);
          this.failTask(executeTaskId, '查询账单数据失败，请稍后再试');
        });
        break;
      }
      case 'Cancel': {
        const cancelTaskId: string = context.getTaskId() ?? '';
        if (cancelTaskId) {
          this.server?.updateStatus(cancelTaskId, { state: TaskState.CANCELED });
        }
        break;
      }
      case 'GetOpening': {
        const openingTaskId: string = context.getTaskId() ?? '';
        if (openingTaskId) {
          this.server?.updateStatus(openingTaskId, {
            state: TaskState.COMPLETED,
            message: {
              messageId: util.generateRandomUUID(),
              role: Role.AGENT,
              parts: [{
                mediaType: 'text/plain',
                text: '你好，我是记账助手，可以帮你查询本月、上月、今年的收支汇总与分类明细。'
              }]
            }
          });
        }
        break;
      }
      case 'PerceptionSuggest': {
        const chipsTaskId: string = context.getTaskId() ?? '';
        if (chipsTaskId) {
          this.replyChips(chipsTaskId);
        }
        break;
      }
      default:
        break;
    }
  };

  async onCreate(want: Want): Promise<void> {
    try {
      this.server = createA2AServer(this.context.agentCard, this.agentOnData, want);
      Logger.info(TAG, 'A2A Server 创建成功');
    } catch (err) {
      Logger.error(TAG, 'A2A Server 创建失败', (err as Error).message);
    }
  }

  onConnect(want: Want, proxy: common.AgentHostProxy): void {
    Logger.info(TAG, '客户端连接');
    this.server?.start();
  }

  async onData(proxy: common.AgentHostProxy, data: string): Promise<void> {
    this.server?.onMessage(data, (response: string): void => {
      proxy.sendData(response);
    });
  }

  onDisconnect(want: Want, proxy: common.AgentHostProxy): void {
    Logger.info(TAG, '客户端断开连接');
    this.server?.stop();
  }

  onDestroy(): void {
    this.server?.stop();
  }

  /** 处理查询请求：解析时间口径 -> 查库聚合 -> 产物返回 */
  private async handleExecute(taskId: string, context: RequestContext): Promise<void> {
    if (!taskId) {
      Logger.error(TAG, 'Execute 缺少任务ID');
      return;
    }
    this.server?.updateStatus(taskId, {
      state: TaskState.WORKING,
      message: {
        messageId: util.generateRandomUUID(),
        role: Role.AGENT,
        parts: [{ mediaType: 'text/plain', text: '正在查询账单数据…' }]
      }
    });
    const userInput: string = context.getUserInput();
    const scope: TimeScope = resolveTimeScope(userInput);
    // 恢复自定义分类配置：进程冷启动时 CategoryStore 尚未初始化（幂等，重复调用安全）
    await CategoryStore.init(this.context);
    const summary: BillSummary = await this.queryBillSummary(scope.start, scope.end);
    const summaryText: string = this.buildSummaryText(scope.label, summary);
    const payload: SummaryPayload = {
      scope: scope.label,
      expenses: summary.expenses,
      income: summary.income,
      expenseItems: summary.expenseItems,
      incomeItems: summary.incomeItems
    };
    this.server?.addArtifact(taskId, {
      artifactId: util.generateRandomUUID(),
      name: scope.label + '账单汇总',
      parts: [
        { mediaType: 'application/json', data: JSON.stringify(payload) },
        { mediaType: 'text/plain', text: summaryText }
      ],
      lastChunk: true
    });
    this.server?.updateStatus(taskId, {
      state: TaskState.COMPLETED,
      message: {
        messageId: util.generateRandomUUID(),
        role: Role.AGENT,
        parts: [{ mediaType: 'text/plain', text: summaryText }]
      }
    });
  }

  /** 按时间范围做 SQL 聚合：按分类分组统计金额与笔数 */
  private async queryBillSummary(start: number, end: number): Promise<BillSummary> {
    const store = await getAgentStore(this.context);
    const sql: string = 'SELECT type, account_type, SUM(amount) AS total, COUNT(*) AS cnt FROM '
      + ACCOUNT_TABLE_NAME + ' WHERE time >= ? AND time <= ? GROUP BY type, account_type';
    const result = await store.querySql(sql, [start, end]);
    const expenseItems: CategorySummaryItem[] = [];
    const incomeItems: CategorySummaryItem[] = [];
    try {
      while (result.goToNextRow()) {
        const categoryId: number = result.getLong(result.getColumnIndex('type'));
        const accountType: number = result.getLong(result.getColumnIndex('account_type'));
        const amount: number = Math.round(result.getDouble(result.getColumnIndex('total')) * 100) / 100;
        const count: number = result.getLong(result.getColumnIndex('cnt'));
        const category = CategoryRegistry.getById(categoryId, accountType);
        const item: CategorySummaryItem = {
          name: this.resolveCategoryName(category.name),
          amount: amount,
          count: count
        };
        if (accountType === AccountType.EXPENSES) {
          expenseItems.push(item);
        } else {
          incomeItems.push(item);
        }
      }
    } finally {
      result.close();
    }
    expenseItems.sort((a: CategorySummaryItem, b: CategorySummaryItem): number => b.amount - a.amount);
    incomeItems.sort((a: CategorySummaryItem, b: CategorySummaryItem): number => b.amount - a.amount);
    let expenses: number = 0;
    for (const item of expenseItems) {
      expenses = Math.round((expenses + item.amount) * 100) / 100;
    }
    let income: number = 0;
    for (const item of incomeItems) {
      income = Math.round((income + item.amount) * 100) / 100;
    }
    const summary: BillSummary = {
      expenses: expenses,
      income: income,
      expenseItems: expenseItems,
      incomeItems: incomeItems
    };
    return summary;
  }

  /** 分类名可能是资源引用（$string:xxx），统一解析为纯文本 */
  private resolveCategoryName(name: ResourceStr): string {
    if (typeof name === 'string') {
      return name;
    }
    return this.context.resourceManager.getStringSync(name);
  }

  /** 组装自然语言摘要，供小艺直接播报/展示 */
  private buildSummaryText(scopeLabel: string, summary: BillSummary): string {
    let text: string = scopeLabel + '支出 ¥' + summary.expenses.toFixed(2)
      + '，收入 ¥' + summary.income.toFixed(2) + '。';
    if (summary.expenseItems.length > 0) {
      text += '\n支出分类：';
      for (const item of summary.expenseItems) {
        text += item.name + ' ¥' + item.amount.toFixed(2) + '(' + item.count + '笔)、';
      }
    }
    if (summary.incomeItems.length > 0) {
      text += '\n收入分类：';
      for (const item of summary.incomeItems) {
        text += item.name + ' ¥' + item.amount.toFixed(2) + '(' + item.count + '笔)、';
      }
    }
    return text;
  }

  /** 回复小艺感知建议 chips：给出常用查询入口 */
  private replyChips(taskId: string): void {
    const candidates: SuggestionCandidate[] = [
      { text: '这个月花了多少钱', reply: '这个月我花了多少钱' },
      { text: '上个月支出多少', reply: '上个月支出多少' },
      { text: '今年收入多少', reply: '今年收入多少' }
    ];
    const chipsData: Record<string, Object> = { 'suggestionCandidates': candidates };
    this.server?.addArtifact(taskId, {
      artifactId: util.generateRandomUUID(),
      parts: [{ mediaType: 'application/json', data: JSON.stringify(chipsData) }],
      lastChunk: true
    });
    this.server?.updateStatus(taskId, {
      state: TaskState.COMPLETED,
      message: {
        messageId: util.generateRandomUUID(),
        role: Role.AGENT,
        parts: [{ mediaType: 'text/plain', text: '已提供推荐问题' }]
      }
    });
  }

  /** 查询失败时结束任务，避免小艺侧长时间等待 */
  private failTask(taskId: string, message: string): void {
    if (!taskId) {
      return;
    }
    this.server?.updateStatus(taskId, {
      state: TaskState.FAILED,
      message: {
        messageId: util.generateRandomUUID(),
        role: Role.AGENT,
        parts: [{ mediaType: 'text/plain', text: message }]
      }
    });
  }
}
