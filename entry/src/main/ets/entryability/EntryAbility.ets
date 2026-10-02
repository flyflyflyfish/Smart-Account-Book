import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import PreferenceUtil from '../utils/PreferenceUtil';
import DBUtil from '../utils/DBUtil';
import CategoryStore from '../models/accountType/CategoryStore';
import AuthService from '../service/AuthService';
import CloudInit from '../data/CloudInit';
import RecurringBillService from '../service/RecurringBillService';
import {
  ACCOUNT_CREATE_TABLE_SQL,
  MERCHANT_CATEGORY_CREATE_TABLE_SQL,
  MIGRATION_STEPS
} from '../data/schema';

export default class EntryAbility extends UIAbility {
  private selectPage: string = '';
  private currentWindowStage: window.WindowStage | null = null;

  // 解析卡片 router 事件传入的 targetPage 参数
  private readCardParam(want: Want): void {
    if (want && want.parameters) {
      const raw = want.parameters['params'];
      if (typeof raw === 'string') {
        try {
          const params = JSON.parse(raw) as Record<string, Object>;
          const target = params['targetPage'];
          if (typeof target === 'string') {
            this.selectPage = target;
          }
        } catch (err) {
          const e = err as Error;
          hilog.error(0x0000, 'testTag', '解析卡片参数失败: %{private}s', e.message);
        }
      }
    }
  }

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    this.readCardParam(want);
    try {
      // 依次等待首选项与数据库初始化完成
      await PreferenceUtil.loadPreference(this.context);
      // 加载用户自定义分类配置（增/减/恢复默认），页面加载前就绪
      await CategoryStore.init(this.context);
      await DBUtil.initDB(this.context);
      // 先逐级迁移老库，再建表（IF NOT EXISTS 对新装生效、对老库为无操作）
      await DBUtil.migrate(MIGRATION_STEPS);
      await DBUtil.createTable(ACCOUNT_CREATE_TABLE_SQL);
      await DBUtil.createTable(MERCHANT_CATEGORY_CREATE_TABLE_SQL);
      // 认证服务初始化；若已登录则继续初始化云开发服务以启用云端双写
      AuthService.init(this.context);
      const uid = await AuthService.getCurrentUid();
      if (uid) {
        CloudInit.init();
      }
    } catch (err) {
      const e = err as Error;
      hilog.error(0x0000, 'testTag', '初始化失败: %{private}s', e.message);
    } finally {
      // 无论成功失败都决议 ready，避免页面一直等待
      DBUtil.markReady();
    }
    // 重复性账单：启动时补记到期账单，并周期检查，应用存活期间到点自动记入
    RecurringBillService.start(this.context);
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onCreate');
  }

  onDestroy() {
    RecurringBillService.stop();
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    // Main window is created, set main page for this ability
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onWindowStageCreate');
    this.currentWindowStage = windowStage;

    // 自定义分类配置就绪后再加载页面，避免首帧读到默认分类
    CategoryStore.init(this.context).then((): void => {
      let targetPage = 'pages/Index';
      if (this.selectPage === 'add') {
        targetPage = 'pages/AddAccount';
      } else if (this.selectPage === 'recognize') {
        targetPage = 'pages/RecognizeBill';
      } else if (this.selectPage === 'ai') {
        AppStorage.setOrCreate('quickTab', 1);
        targetPage = 'pages/Index';
      }

      windowStage.loadContent(targetPage, (err, data) => {
        if (err.code) {
          hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{private}s', JSON.stringify(err) ?? '');
          return;
        }
        hilog.info(0x0000, 'testTag', 'Succeeded in loading the content. Data: %{private}s', JSON.stringify(data) ?? '');
      });
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onNewWant');
    this.readCardParam(want);
    if (this.currentWindowStage !== null) {
      this.onWindowStageCreate(this.currentWindowStage);
    }
  }

  onWindowStageDestroy() {
    // Main window is destroyed, release UI related resources
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onWindowStageDestroy');
  }

  onForeground() {
    // Ability has brought to foreground
    // 回前台立即检查一次重复性账单，避免后台期间错过的到点账单延迟记入
    RecurringBillService.start(this.context);
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onForeground');
  }

  onBackground() {
    // Ability has back to background
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onBackground');
  }
}
