import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import { Configuration } from '@ohos.app.ability.Configuration';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import router from '@ohos.router';
import PreferenceUtil from '../utils/PreferenceUtil';
import DBUtil from '../utils/DBUtil';
import CategoryStore from '../models/accountType/CategoryStore';
import AuthService from '../service/AuthService';
import CloudInit from '../data/CloudInit';
import CloudSyncService from '../service/CloudSyncService';
import RecurringBillService from '../service/RecurringBillService';
import SecondTabStore from '../common/SecondTabStore';
import { ThemeKit } from '../common/theme/Theme';
import {
  ACCOUNT_CREATE_TABLE_SQL,
  LEDGER_CREATE_TABLE_SQL,
  LEDGER_RECORD_CREATE_TABLE_SQL,
  MERCHANT_CATEGORY_CREATE_TABLE_SQL,
  MIGRATION_STEPS
} from '../data/schema';
import * as CONSTANTS from '../common/constants';

export default class EntryAbility extends UIAbility {
  private selectPage: string = '';
  private currentWindowStage: window.WindowStage | null = null;

  // 解析卡片 router 事件传入的 targetPage 参数（无参数时清空，避免旧值残留）
  private readCardParam(want: Want): void {
    this.selectPage = '';
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
      // 恢复用户主题/深浅色/字号设置（首选项就绪后、页面加载前）
      await ThemeKit.init(this.context);
      // 加载用户自定义分类配置（增/减/恢复默认），页面加载前就绪
      await CategoryStore.init(this.context);
      // 恢复底部第二页签样式（AI 助手 / 账本），Index 据此渲染第二个页签
      const savedTabStyle = await PreferenceUtil.getPreferenceValue(
        CONSTANTS.PREF_SECOND_TAB_STYLE, CONSTANTS.SECOND_TAB_STYLE_AI);
      SecondTabStore.init(typeof savedTabStyle === 'string' ? savedTabStyle : CONSTANTS.SECOND_TAB_STYLE_AI);
      await DBUtil.initDB(this.context);
      // 先逐级迁移老库，再建表（IF NOT EXISTS 对新装生效、对老库为无操作）
      await DBUtil.migrate(MIGRATION_STEPS);
      await DBUtil.createTable(ACCOUNT_CREATE_TABLE_SQL);
      await DBUtil.createTable(MERCHANT_CATEGORY_CREATE_TABLE_SQL);
      await DBUtil.createTable(LEDGER_CREATE_TABLE_SQL);
      await DBUtil.createTable(LEDGER_RECORD_CREATE_TABLE_SQL);
      // 认证服务初始化；若已登录则继续初始化云开发服务以启用云端双写
      AuthService.init(this.context);
      const profile = await AuthService.getCurrentProfile();
      // 登录态写入 AppStorage，设置页账号栏据此切换“账号登录/头像+昵称+ID”显示
      AppStorage.setOrCreate('accountUid', profile ? profile.uid : '');
      AppStorage.setOrCreate('accountName', profile ? profile.displayName : '');
      AppStorage.setOrCreate('accountAvatar', profile ? profile.photoUrl : '');
      if (profile) {
        CloudInit.init(profile.uid);
        // 已登录：启动后做一次端云全量同步（恢复云端账单/分类/设置，上传本地新增），不阻塞启动
        CloudSyncService.syncAll(true);
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

    // 自定义分类配置就绪后再加载页面，避免首帧读到默认分类；
    // init 失败也必须加载页面（用默认分类兜底），否则应用白屏
    CategoryStore.init(this.context).catch((err: Error): void => {
      hilog.error(0x0000, 'testTag', 'CategoryStore init failed: %{public}s', err.message);
    }).then((): void => {
      if (this.selectPage === 'ai') {
        AppStorage.setOrCreate('quickTab', 1);
      }
      // 始终以 Index 为根页面，目标页用 router 压栈，保证返回键回到首页而非退出应用
      windowStage.loadContent('pages/Index', (err, data) => {
        if (err.code) {
          hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
          return;
        }
        hilog.info(0x0000, 'testTag', 'Succeeded in loading the content. Data: %{public}s', JSON.stringify(data) ?? '');
        if (this.selectPage === 'add') {
          router.pushUrl({ url: 'pages/AddAccount' });
        } else if (this.selectPage === 'recognize') {
          router.pushUrl({ url: 'pages/RecognizeBill' });
        }
      });
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onNewWant');
    this.readCardParam(want);
    // 应用已存活：在现有页面栈上导航，不重建窗口
    if (this.selectPage === 'add') {
      if (router.getState().path !== 'pages/AddAccount') {
        router.pushUrl({ url: 'pages/AddAccount' });
      }
    } else if (this.selectPage === 'recognize') {
      if (router.getState().path !== 'pages/RecognizeBill') {
        router.pushUrl({ url: 'pages/RecognizeBill' });
      }
    } else if (this.selectPage === 'ai') {
      AppStorage.setOrCreate('quickTab', 1);
      if (router.getState().path !== 'pages/Index') {
        router.back({ url: 'pages/Index' });
      }
    }
  }

  onWindowStageDestroy() {
    // Main window is destroyed, release UI related resources
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onWindowStageDestroy');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 系统深浅色变化时联动主题（仅“跟随系统”模式下生效）
    if (newConfig.colorMode !== undefined) {
      ThemeKit.onSystemColorModeChanged(newConfig.colorMode);
    }
  }

  onForeground() {
    // Ability has brought to foreground
    // 回前台立即检查一次重复性账单，避免后台期间错过的到点账单延迟记入
    RecurringBillService.start(this.context);
    // 回前台节流触发一次端云全量同步，多设备间保持数据最新
    CloudSyncService.syncAll();
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onForeground');
  }

  onBackground() {
    // Ability has back to background
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onBackground');
  }
}
