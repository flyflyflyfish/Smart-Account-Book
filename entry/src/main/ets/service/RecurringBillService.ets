import dayjs from 'dayjs';
import util from '@ohos.util';
import { notificationManager } from '@kit.NotificationKit';
import common from '@ohos.app.ability.common';
import PreferenceUtil from '../utils/PreferenceUtil';
import * as CONSTANTS from '../common/constants';
import AccountService from './account';
import BillStore from '../common/BillStore';
import CategoryStore from '../models/accountType/CategoryStore';
import CloudSettingSync from './CloudSettingSync';
import { RecurringBill, RecurringRepeatMode } from '../models/recurring/RecurringBill';
import { AccountInfo, AccountType } from '../models/account/account';
import { Logger } from '../utils/Logger';

// 应用存活期间的周期检查间隔（毫秒）
const SYNC_INTERVAL_MS: number = 60000;
// 补记扫描的最大回溯天数，避免异常历史数据导致超长循环
const MAX_BACKFILL_DAYS: number = 366;
// 计算下次记入时间时最多向后探测的天数（覆盖每月 31 日等场景）
const MAX_LOOKUP_DAYS: number = 62;
// 每月模式可选日期范围 1-28 日
const MONTH_DAY_MIN: number = 1;
const MONTH_DAY_MAX: number = 31;

/**
 * 快捷记账（原重复性账单）：规则存取、一键添加、到期补记、记入成功通知与周期检查
 * 一键添加：按模板立即记入一笔时间为当前的账单；
 * 到达设定时间自动调用 AccountService.insert 记入账单；
 * 应用启动/回前台时补记停机期间错过的账单
 */
class RecurringBillService {
  private timerId: number = -1;
  private syncing: boolean = false;

  /**
   * 读取全部重复性账单规则
   */
  async loadAll(): Promise<RecurringBill[]> {
    try {
      const raw = await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_RECURRING_BILLS, '');
      if (typeof raw !== 'string' || raw.length === 0) {
        return [];
      }
      return this.parseList(raw);
    } catch (err) {
      Logger.error('加载重复性账单失败', (err as Error).message);
      return [];
    }
  }

  // 反序列化并逐字段校验，非法数据跳过
  private parseList(text: string): RecurringBill[] {
    const result: RecurringBill[] = [];
    try {
      const raw = JSON.parse(text) as RecurringBill[];
      if (!Array.isArray(raw)) {
        return result;
      }
      raw.forEach((item: RecurringBill) => {
        if (!item || typeof item.id !== 'string' || item.id.length === 0) {
          return;
        }
        const bill = new RecurringBill();
        bill.id = item.id;
        bill.type = typeof item.type === 'number' && item.type >= 0 ? item.type : 0;
        bill.accountType = item.accountType === AccountType.INCOME ? AccountType.INCOME : AccountType.EXPENSES;
        bill.amount = typeof item.amount === 'number' && item.amount > 0 ? item.amount : 0;
        bill.description = typeof item.description === 'string' ? item.description : '';
        bill.repeatMode = this.normalizeMode(item.repeatMode);
        bill.weekdays = this.parseNumberList(item.weekdays, 0, 6, [1]);
        bill.monthDays = this.parseNumberList(item.monthDays, MONTH_DAY_MIN, MONTH_DAY_MAX, [1]);
        bill.hour = typeof item.hour === 'number' && item.hour >= 0 && item.hour <= 23 ? item.hour : 8;
        bill.minute = typeof item.minute === 'number' && item.minute >= 0 && item.minute <= 59 ? item.minute : 0;
        bill.notify = item.notify === true;
        bill.enabled = item.enabled !== false;
        bill.lastTriggerTime = typeof item.lastTriggerTime === 'number' && item.lastTriggerTime > 0
          ? item.lastTriggerTime : 0;
        bill.createTime = typeof item.createTime === 'number' && item.createTime > 0 ? item.createTime : 0;
        result.push(bill);
      });
    } catch (err) {
      Logger.error('解析重复性账单失败', (err as Error).message);
    }
    return result;
  }

  private normalizeMode(mode: number): number {
    if (mode === RecurringRepeatMode.EVERY_DAY || mode === RecurringRepeatMode.WEEKDAYS ||
      mode === RecurringRepeatMode.WEEKLY || mode === RecurringRepeatMode.MONTHLY) {
      return mode;
    }
    return RecurringRepeatMode.EVERY_DAY;
  }

  // 反序列化数字数组：过滤越界与重复值，为空时回退默认值
  private parseNumberList(raw: number[] | undefined, min: number, max: number, fallback: number[]): number[] {
    const result: number[] = [];
    if (raw && Array.isArray(raw)) {
      raw.forEach((value: number) => {
        if (typeof value === 'number' && value >= min && value <= max && result.indexOf(value) < 0) {
          result.push(value);
        }
      });
    }
    return result.length > 0 ? result : fallback;
  }

  private async saveAll(list: RecurringBill[]): Promise<void> {
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_RECURRING_BILLS, JSON.stringify(list));
    // 云同步：快捷记账规则即时上传，未登录静默跳过
    CloudSettingSync.pushSetting(CONSTANTS.PREF_RECURRING_BILLS, JSON.stringify(list));
  }

  /**
   * 新建规则：从现在起生效，历史时间不补记
   */
  async add(bill: RecurringBill): Promise<void> {
    const list = await this.loadAll();
    bill.id = util.generateRandomUUID();
    bill.createTime = Date.now();
    bill.lastTriggerTime = 0;
    list.push(bill);
    await this.saveAll(list);
  }

  /**
   * 更新规则：重新以当前时间为基准，仅记入之后到期的账单
   */
  async update(bill: RecurringBill): Promise<void> {
    const list = await this.loadAll();
    const index = list.findIndex((item: RecurringBill): boolean => item.id === bill.id);
    if (index >= 0) {
      bill.lastTriggerTime = Date.now();
      list[index] = bill;
      await this.saveAll(list);
    }
  }

  /**
   * 删除规则：已记入的账单不受影响
   */
  async remove(id: string): Promise<void> {
    const list = await this.loadAll();
    const rest = list.filter((item: RecurringBill): boolean => item.id !== id);
    await this.saveAll(rest);
  }

  /**
   * 启停规则：重新开启时从当前时间起生效，停用期间不补记
   */
  async setEnabled(id: string, enabled: boolean): Promise<void> {
    const list = await this.loadAll();
    const matched = list.find((item: RecurringBill): boolean => item.id === id);
    if (!matched) {
      return;
    }
    matched.enabled = enabled;
    if (enabled && matched.lastTriggerTime < Date.now()) {
      matched.lastTriggerTime = Date.now();
    }
    await this.saveAll(list);
  }

  /**
   * 一键添加：按模板立即记入一笔账单，支付时间与记入时间均为当前时间
   * 与规则的开关状态、定时自动记入互不影响
   */
  async recordNow(bill: RecurringBill): Promise<boolean> {
    if (!bill || bill.amount <= 0) {
      return false;
    }
    try {
      const now = Date.now();
      // time 为首页分组用的日桶，需归一到当天零点；payTime 为实际支付时间（现在）
      const today = dayjs(now).startOf('day').valueOf();
      const info: AccountInfo = {
        type: bill.type,
        accountType: bill.accountType === AccountType.INCOME ? AccountType.INCOME : AccountType.EXPENSES,
        amount: bill.amount,
        time: today,
        description: bill.description,
        source: CONSTANTS.SOURCE_RECURRING,
        payTime: now,
        createTime: now
      };
      await AccountService.insert(info);
      return true;
    } catch (err) {
      Logger.error('一键添加快捷账单失败', (err as Error).message);
      return false;
    }
  }

  /**
   * 某天是否命中重复规则
   */
  static matchesDay(bill: RecurringBill, dayTime: number): boolean {
    const day = dayjs(dayTime);
    switch (bill.repeatMode) {
      case RecurringRepeatMode.EVERY_DAY:
        return true;
      case RecurringRepeatMode.WEEKDAYS: {
        const week = day.day();
        return week >= 1 && week <= 5;
      }
      case RecurringRepeatMode.WEEKLY:
        return bill.weekdays.indexOf(day.day()) >= 0;
      case RecurringRepeatMode.MONTHLY:
        return bill.monthDays.indexOf(day.date()) >= 0;
      default:
        return false;
    }
  }

  /**
   * 计算下次记入时间；已停用或探测不到返回 -1
   */
  nextOccurrence(bill: RecurringBill, from: number): number {
    if (!bill.enabled) {
      return -1;
    }
    let dayTime = dayjs(from).startOf('day').valueOf();
    for (let i = 0; i < MAX_LOOKUP_DAYS; i++) {
      if (RecurringBillService.matchesDay(bill, dayTime)) {
        const occurrence = dayjs(dayTime).hour(bill.hour).minute(bill.minute).second(0).millisecond(0).valueOf();
        if (occurrence > from) {
          return occurrence;
        }
      }
      dayTime = dayjs(dayTime).add(1, 'day').valueOf();
    }
    return -1;
  }

  /**
   * 同步到期账单：补记 (上次记入, 当前时间] 内所有错过的账单
   */
  async syncDueBills(context: common.Context): Promise<void> {
    if (this.syncing) {
      return;
    }
    this.syncing = true;
    try {
      const list = await this.loadAll();
      const now = Date.now();
      let changed = false;
      for (const bill of list) {
        let inserted = 0;
        try {
          inserted = await this.backfillBill(bill, list, now);
        } catch (err) {
          // 单条规则失败不影响其他规则；进度已随每笔插入持久化，不会重复
          Logger.error('补记单条规则失败', (err as Error).message);
        }
        if (inserted > 0) {
          changed = true;
          if (bill.notify) {
            await this.publishAddedNotification(context, bill, inserted);
          }
        }
      }
      if (changed) {
        // 补记走静默插入，这里统一广播一次，避免逐笔触发 UI/卡片刷新风暴
        BillStore.notifyChanged();
      }
    } catch (err) {
      Logger.error('同步重复性账单失败', (err as Error).message);
    } finally {
      this.syncing = false;
    }
  }

  // 逐天扫描补记窗口，命中规则且未记入的账单逐条插入
  private async backfillBill(bill: RecurringBill, list: RecurringBill[], now: number): Promise<number> {
    if (!bill.enabled || bill.amount <= 0) {
      return 0;
    }
    const anchor = bill.lastTriggerTime > 0 ? bill.lastTriggerTime : bill.createTime;
    if (anchor <= 0 || anchor >= now) {
      return 0;
    }
    const today = dayjs(now).startOf('day');
    let day = dayjs(anchor).startOf('day');
    const earliest = today.subtract(MAX_BACKFILL_DAYS - 1, 'day');
    if (day.isBefore(earliest)) {
      day = earliest;
    }
    let inserted = 0;
    while (!day.isAfter(today)) {
      const dayTime = day.valueOf();
      if (RecurringBillService.matchesDay(bill, dayTime)) {
        const occurrence = day.hour(bill.hour).minute(bill.minute).second(0).millisecond(0).valueOf();
        if (occurrence > anchor && occurrence <= now) {
          const info: AccountInfo = {
            type: bill.type,
            accountType: bill.accountType === AccountType.INCOME ? AccountType.INCOME : AccountType.EXPENSES,
            amount: bill.amount,
            time: dayTime,
            description: bill.description,
            source: CONSTANTS.SOURCE_RECURRING,
            payTime: occurrence,
            createTime: Date.now()
          };
          try {
            await AccountService.insertSilently(info);
            bill.lastTriggerTime = occurrence;
            inserted += 1;
            // 每笔插入后立即持久化进度：后续某笔失败或进程被杀，
            // 已成功笔不会被下轮 sync 重复插入
            await this.saveAll(list);
          } catch (err) {
            // 本笔失败：中断本规则，下轮 sync 从已持久化的 lastTriggerTime 继续
            Logger.error('补记账单中断', (err as Error).message);
            break;
          }
        }
      }
      day = day.add(1, 'day');
    }
    return inserted;
  }

  // 用户关闭通知开关或发布失败时静默忽略，账单仍正常记入
  private async publishAddedNotification(context: common.Context, bill: RecurringBill, count: number): Promise<void> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      if (!enabled) {
        // 无参重载弹系统授权框（仅一次）；用户拒绝时 reject，由下方 catch 静默忽略
        await notificationManager.requestEnableNotification();
      }
      const name = CategoryStore.nameText(bill.type, bill.accountType);
      // 变参 getStringSync 重载在 ArkTS 严格模式不可用，先取模板再替换占位符
      const textTemplate = context.resourceManager.getStringSync($r('app.string.recurring_notif_text'));
      const request: notificationManager.NotificationRequest = {
        id: RecurringBillService.notificationIdOf(bill),
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: context.resourceManager.getStringSync($r('app.string.recurring_notif_title')),
            text: textTemplate
              .replace('%s', name)
              .replace('%s', '¥' + (bill.amount * count).toFixed(2)),
            additionalText: context.resourceManager.getStringSync($r('app.string.recurring_notif_additional'))
          }
        }
      };
      await notificationManager.publish(request);
    } catch (err) {
      Logger.debug('发送重复性账单通知失败', (err as Error).message);
    }
  }

  // 由规则 id 派生稳定的通知 id：多规则同轮触发时通知互不覆盖
  private static notificationIdOf(bill: RecurringBill): number {
    let hash = 0;
    const id = bill.id;
    for (let i = 0; i < id.length; i++) {
      hash = (hash * 31 + id.charCodeAt(i)) % 100000;
    }
    return CONSTANTS.RECURRING_NOTIFICATION_ID + hash;
  }

  /**
   * 应用启动/回前台时调用：立即同步一次，并周期检查到点自动记入
   */
  start(context: common.Context): void {
    this.syncDueBills(context);
    if (this.timerId >= 0) {
      return;
    }
    this.timerId = setInterval(() => {
      this.syncDueBills(context);
    }, SYNC_INTERVAL_MS);
  }

  /**
   * 应用销毁时停止周期检查
   */
  stop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }
}

export default new RecurringBillService();
