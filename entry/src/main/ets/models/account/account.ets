import AccountTypeModel from '../accountType/AccountTypeModel';

export enum AccountExpensesType {
  MEALS,    // 餐食
  MEDICAL,  // 医疗
  TRANSPORT, // 交通
  HOUSE,    // 住房
  TOBACCO,  // 烟酒零食
  STUDY,    // 学习
  COMMUNICATE, // 通讯
  SOCIAL,    // 社交
  INVEST,    // 投资
  SHOPPING,  // 购物
  ENTERTAINMENT,  // 娱乐
  LOAN,      // 外借
  OTHER,    // 其他
}

export enum AccountIncomeType {
  SALARY,  // 工资
  BONUS,   // 奖金
  INTEREST,  // 利息
  INVEST,    // 投资
  PART_TIME, // 兼职
  RED_ENVELOP, // 红包转账
  BORROW,    // 借入
  OTHER,     //  其他
}

export enum AccountType {
  EXPENSES,
  INCOME,
}

export interface AccountInfo {
  type: number;
  accountType: AccountType;
  amount: number;
  time: number;
  description?: string;
  merchant?: string;
  source?: number;
  payTime?: number;
  createTime?: number;
}

// 数据库映射字段
export enum ColumnType {
  LONG,
  DOUBLE,
  STRING,
  BLOB,
}
export interface ColumnInfo {
  name: string;
  columnName: string;
  type: ColumnType;
}

export interface ItemRecordInfo {
  id: number;
  type: number;
  accountType: number;
  description?: string;
  createTime: number;
  amount: number;
  time: number;
  merchant?: string;
  source?: number;
  payTime?: number;
  info: AccountTypeModel;
}

/**
 * 收支金额累加结果的公共结构
 */
export interface AmountSummary {
  expenses: number;
  income: number;
}

export interface GroupByDate extends AmountSummary {
  time: number;
  records: ItemRecordInfo[]
}

export interface StatsByDate extends AmountSummary {
  time: number;
}

export interface StatsByType {
  amount: number;
  count: number;
  info: AccountTypeModel;
}

export interface StatsData<T> {
  expenses: T[];
  income: T[];
}

export interface StatsResultByDate {
  expenses: number;
  income: number;
  data: StatsData<StatsByDate>;
}

export interface StatsResultByType {
  expenses: number;
  income: number;
  data: StatsData<StatsByType>;
}