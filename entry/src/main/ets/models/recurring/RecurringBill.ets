/**
 * 重复频率：每天 / 周一至周五 / 每周指定日 / 每月指定日
 */
export enum RecurringRepeatMode {
  EVERY_DAY = 0,
  WEEKDAYS = 1,
  WEEKLY = 2,
  MONTHLY = 3,
}

/**
 * 快捷记账模板：可一键添加立即记入一笔账单，也可到达设定时间自动记入
 * 例如：设置一笔 2 元的地铁支出，一键添加即在当前时间记入一笔
 */
export class RecurringBill {
  id: string = '';
  // 分类 id
  type: number = 0;
  // 0 支出 / 1 收入
  accountType: number = 0;
  amount: number = 0;
  description: string = '';
  // 重复频率，取值见 RecurringRepeatMode
  repeatMode: number = RecurringRepeatMode.EVERY_DAY;
  // 每周模式命中的星期（0=周日 ... 6=周六），可多选
  weekdays: number[] = [1];
  // 每月模式命中的日期（1-28），可多选
  monthDays: number[] = [1];
  // 记入时刻（24 小时制）
  hour: number = 8;
  minute: number = 0;
  // 自动记入成功后是否发送系统通知提醒
  notify: boolean = true;
  // 规则开关，停用期间不记入也不补记
  enabled: boolean = true;
  // 上次已记入的发生时间戳，0 表示从未记入
  lastTriggerTime: number = 0;
  createTime: number = 0;

  /**
   * 星期按周一至周日排序（展示用）
   */
  static sortWeekdays(days: number[]): number[] {
    const order: number[] = [1, 2, 3, 4, 5, 6, 0];
    return order.filter((day: number): boolean => days.indexOf(day) >= 0);
  }

  /**
   * 日期升序排序（展示用）
   */
  static sortMonthDays(days: number[]): number[] {
    return days.slice().sort((a: number, b: number): number => a - b);
  }
}
