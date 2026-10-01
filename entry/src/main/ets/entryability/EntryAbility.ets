import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import PreferenceUtil from '../utils/PreferenceUtil';
import DBUtil from '../utils/DBUtil';
import {
  ACCOUNT_CREATE_TABLE_SQL,
  DB_VERSION,
  MERCHANT_CATEGORY_CREATE_TABLE_SQL,
  MIGRATE_1_TO_2_SQLS
} from '../data/schema';

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    try {
      // 依次等待首选项与数据库初始化完成
      await PreferenceUtil.loadPreference(this.context);
      await DBUtil.initDB(this.context);
      // 先迁移老库补列，再建表（IF NOT EXISTS 对新装生效、对老库为无操作）
      await DBUtil.migrateIfNeeded(DB_VERSION, MIGRATE_1_TO_2_SQLS);
      await DBUtil.createTable(ACCOUNT_CREATE_TABLE_SQL);
      await DBUtil.createTable(MERCHANT_CATEGORY_CREATE_TABLE_SQL);
    } catch (err) {
      const e = err as Error;
      hilog.error(0x0000, 'testTag', '初始化失败: %{private}s', e.message);
    } finally {
      // 无论成功失败都决议 ready，避免页面一直等待
      DBUtil.markReady();
    }
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onCreate');
  }

  onDestroy() {
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    // Main window is created, set main page for this ability
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err, data) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{private}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'testTag', 'Succeeded in loading the content. Data: %{private}s', JSON.stringify(data) ?? '');
    });
  }

  onWindowStageDestroy() {
    // Main window is destroyed, release UI related resources
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onWindowStageDestroy');
  }

  onForeground() {
    // Ability has brought to foreground
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onForeground');
  }

  onBackground() {
    // Ability has back to background
    hilog.info(0x0000, 'testTag', '%{private}s', 'Ability onBackground');
  }
}
