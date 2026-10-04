import dayjs from 'dayjs';
import {
  AccountType,
  AmountSummary,
  GroupByDate,
  ItemRecordInfo,
  StatsByDate,
  StatsByType,
  StatsResultByDate,
  StatsResultByType
} from '../models/account/account';
import AccountPO from '../models/account/accountPO';
import CategoryRegistry from '../models/accountType/CategoryRegistry';

/**
 * 按收支类型累加金额，消除各统计方法中重复的 if/else。
 * 金额以 DOUBLE 存储存在二进制浮点误差（0.1+0.2≠0.3），
 * 每次累加后四舍五入到分，避免统计/预算比较出现 ±0.01 级偏差
 */
function accumulate(summary: AmountSummary, accountType: number, amount: number): void {
  if (accountType === AccountType.EXPENSES) {
    summary.expenses = Math.round((summary.expenses + amount) * 100) / 100;
  } else {
    summary.income = Math.round((summary.income + amount) * 100) / 100;
  }
}

/**
 * 分桶函数：把记录时间归并到统计桶（如按日、按月）
 */
type BucketFunc = (time: number) => number;

class StatsService {
  /**
   * 按日期分组账单记录
   */
  groupByDate(records: AccountPO[]): GroupByDate[] {
    const groupList: GroupByDate[] = [];
    records.forEach((item: AccountPO) => {
      let group: GroupByDate | undefined = groupList.find((g: GroupByDate): boolean => g.time === item.time);
      if (!group) {
        group = {
          time: item.time,
          expenses: 0,
          income: 0,
          records: []
        };
        groupList.push(group);
      }
      accumulate(group, item.accountType, item.amount);
      const typeInfo = CategoryRegistry.getById(item.type, item.accountType);
      // 数据中的分类 id 已失效，跳过避免界面渲染崩溃
      if (!typeInfo) {
        return;
      }
      const record: ItemRecordInfo = {
        id: item.id,
        type: item.type,
        accountType: item.accountType,
        description: item.description,
        createTime: item.createTime,
        amount: item.amount,
        time: item.time,
        merchant: item.merchant,
        source: item.source,
        payTime: item.payTime,
        info: typeInfo
      };
      group.records.push(record);
    });
    groupList.sort((a: GroupByDate, b: GroupByDate): number => b.time - a.time);
    return groupList;
  }

  /**
   * 统计收支总额
   */
  statsConsume(records: AccountPO[]): AmountSummary {
    const total: AmountSummary = { expenses: 0, income: 0 };
    records.forEach((record: AccountPO) => {
      accumulate(total, record.accountType, record.amount);
    });
    return total;
  }

  /**
   * 按分桶函数聚合统计，按日/按月统计共用此实现
   */
  private statsByBucket(records: AccountPO[], bucketFn: BucketFunc): StatsResultByDate {
    const statsList: StatsByDate[] = [];
    records.forEach((item: AccountPO) => {
      const bucketTime = bucketFn(item.time);
      let stats: StatsByDate | undefined = statsList.find((s: StatsByDate): boolean => s.time === bucketTime);
      if (!stats) {
        stats = { time: bucketTime, expenses: 0, income: 0 };
        statsList.push(stats);
      }
      accumulate(stats, item.accountType, item.amount);
    });
    statsList.sort((a: StatsByDate, b: StatsByDate): number => b.time - a.time);
    const total = this.statsConsume(records);
    const result: StatsResultByDate = {
      expenses: total.expenses,
      income: total.income,
      data: {
        expenses: statsList.filter((item: StatsByDate): boolean => item.expenses > 0),
        income: statsList.filter((item: StatsByDate): boolean => item.income > 0),
      }
    };
    return result;
  }

  /**
   * 按日期统计消费
   */
  statsConsumeByDate(records: AccountPO[]): StatsResultByDate {
    return this.statsByBucket(records, (time: number): number => time);
  }

  /**
   * 按月份统计消费
   */
  statsConsumeByMonth(records: AccountPO[]): StatsResultByDate {
    return this.statsByBucket(records, (time: number): number => dayjs(time).startOf('month').valueOf());
  }

  /**
   * 按类型统计消费
   */
  statsConsumeByType(records: AccountPO[]): StatsResultByType {
    const expensesStats: StatsByType[] = [];
    const incomeStats: StatsByType[] = [];
    records.forEach((item: AccountPO) => {
      const activeStats: StatsByType[] = item.accountType === AccountType.EXPENSES ? expensesStats : incomeStats;
      const existing: StatsByType | undefined = activeStats.find((s: StatsByType): boolean => s.info.id === item.type);
      if (existing) {
        existing.amount = Math.round((existing.amount + item.amount) * 100) / 100;
        existing.count += 1;
      } else {
        const info = CategoryRegistry.getById(item.type, item.accountType);
        // 数据中的分类 id 已失效，跳过避免界面渲染崩溃
        if (!info) {
          return;
        }
        activeStats.push({
          count: 1,
          amount: item.amount,
          info: info
        });
      }
    });
    const total = this.statsConsume(records);
    const result: StatsResultByType = {
      expenses: total.expenses,
      income: total.income,
      data: {
        expenses: expensesStats,
        income: incomeStats,
      }
    };
    return result;
  }
}

export default new StatsService();
