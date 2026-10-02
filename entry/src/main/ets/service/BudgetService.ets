import dayjs from 'dayjs';
import { notificationManager } from '@kit.NotificationKit';
import common from '@ohos.app.ability.common';
import PreferenceUtil from '../utils/PreferenceUtil';
import * as CONSTANTS from '../common/constants';
import AccountService from './account';
import StatsService from './stats';
import { Logger } from '../utils/Logger';

/**
 * 月度消费额度状态
 */
export interface BudgetStatus {
  enabled: boolean;
  limit: number;
  monthExpenses: number;
  exceeded: boolean;
  usage: number;
}

/**
 * 月度消费额度：配置存取、本月支出统计、超支时发送系统通知
 */
class BudgetService {
  async loadEnabled(): Promise<boolean> {
    const value = await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_BUDGET_ENABLED, false);
    return value === true;
  }

  async loadLimit(): Promise<number> {
    const raw = Number(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_BUDGET_LIMIT, 0));
    return Number.isFinite(raw) && raw > 0 ? raw : 0;
  }

  /**
   * 汇总本月支出并计算额度使用状态
   */
  async loadStatus(): Promise<BudgetStatus> {
    const enabled = await this.loadEnabled();
    const limit = await this.loadLimit();
    const records = await AccountService.getAccountByMonth(dayjs().valueOf());
    const total = StatsService.statsConsume(records);
    const usage = limit > 0 ? total.expenses / limit : 0;
    const status: BudgetStatus = {
      enabled: enabled && limit > 0,
      limit: limit,
      monthExpenses: total.expenses,
      exceeded: enabled && limit > 0 && total.expenses > limit,
      usage: usage
    };
    return status;
  }

  /**
   * 保存额度配置：清除当月提醒标记，调整额度后再次超支可重新提醒；递增 budgetVersion 通知界面刷新
   */
  async saveSettings(enabled: boolean, limit: number): Promise<void> {
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_BUDGET_ENABLED, enabled);
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_BUDGET_LIMIT, limit);
    await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_BUDGET_ALERT_MONTH, '');
    const version = AppStorage.get<number>('budgetVersion') ?? 0;
    AppStorage.setOrCreate('budgetVersion', version + 1);
  }

  /**
   * 检查是否超支：本月首次越过额度时发送系统通知，返回状态供应用内弹窗提醒
   */
  async checkAndAlert(context: common.Context): Promise<BudgetStatus | null> {
    try {
      const status = await this.loadStatus();
      if (!status.exceeded) {
        return null;
      }
      const monthKey = dayjs().format('YYYY-MM');
      const alerted = String(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_BUDGET_ALERT_MONTH, ''));
      if (alerted === monthKey) {
        return null;
      }
      await PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_BUDGET_ALERT_MONTH, monthKey);
      await this.publishOverNotification(context, status);
      return status;
    } catch (err) {
      Logger.error('检查月度消费额度失败', (err as Error).message);
      return null;
    }
  }

  // 用户关闭通知开关或发布失败时静默忽略，应用内弹窗仍会提醒
  private async publishOverNotification(context: common.Context, status: BudgetStatus): Promise<void> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      if (!enabled) {
        // 无参重载弹系统授权框（仅一次）；用户拒绝时 reject，由下方 catch 静默忽略
        await notificationManager.requestEnableNotification();
      }
      const overAmount = status.monthExpenses - status.limit;
      // 变参 getStringSync 重载在 ArkTS 严格模式不可用，先取模板再替换占位符
      const textTemplate = context.resourceManager.getStringSync($r('app.string.budget_notif_text'));
      const request: notificationManager.NotificationRequest = {
        id: CONSTANTS.BUDGET_NOTIFICATION_ID,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: context.resourceManager.getStringSync($r('app.string.budget_notif_title')),
            text: textTemplate
              .replace('%s', '¥' + status.monthExpenses.toFixed(2))
              .replace('%s', '¥' + overAmount.toFixed(2)),
            additionalText: context.resourceManager.getStringSync($r('app.string.budget_notif_additional'))
          }
        }
      };
      await notificationManager.publish(request);
    } catch (err) {
      Logger.debug('发送超支通知失败', (err as Error).message);
    }
  }
}

export default new BudgetService();
