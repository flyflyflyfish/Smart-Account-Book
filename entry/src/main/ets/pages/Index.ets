import router from '@ohos.router';
import window from '@ohos.window';
import dayjs from 'dayjs';
import Home from '../views/home';
import AiAssistant from '../views/aiAssistant';
import Stats from '../views/stats';
import SettingsView from '../views/settings';
import PreferenceUtil from '../utils/PreferenceUtil';
import DBUtil from '../utils/DBUtil';
import * as CONSTANTS from '../common/constants';
import BreakpointSystem from '../utils/BreakpointSystem';
import BreakpointConstants from '../common/breakpoint';
import BillStore, { BillChangeListener } from '../common/BillStore';
import BudgetService, { BudgetStatus } from '../service/BudgetService';
import { Logger } from '../utils/Logger';
import { SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL } from '../common/dimens';

interface RecognizeSourceParam {
  source: string;
}

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State showAddMenu: boolean = false;
  @State keyboardVisible: boolean = false;
  private breakpointSystem: BreakpointSystem = new BreakpointSystem();
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  // 额度设置变更后重新检查是否超支
  @StorageProp('budgetVersion')
  @Watch('onBudgetChanged')
  budgetVersion: number = 0;
  // 账单增删后检查本月支出是否越过消费额度
  private billListener: BillChangeListener = () => {
    this.refreshBudgetAlert();
  };

  async aboutToAppear() {
    this.breakpointSystem.register();
    this.registerKeyboardListener();
    const quickTab = AppStorage.get<number>('quickTab');
    if (typeof quickTab === 'number' && quickTab >= 0 && quickTab <= 3) {
      this.currentTab = quickTab;
      AppStorage.delete('quickTab');
    }
    await DBUtil.ready;
    BillStore.subscribe(this.billListener);
    this.refreshBudgetAlert();
    const firstUseTime = Number(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_USER_FIRST_KEY, 0));
    if (!firstUseTime) {
      PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_USER_FIRST_KEY, dayjs().valueOf());
    }
  }

  aboutToDisappear() {
    this.breakpointSystem.unRegister();
    BillStore.unsubscribe(this.billListener);
  }

  onBudgetChanged(): void {
    this.refreshBudgetAlert();
  }

  // 本月首次越过额度时弹窗提醒（系统通知由 BudgetService 发送）
  async refreshBudgetAlert(): Promise<void> {
    const status = await BudgetService.checkAndAlert(getContext(this));
    if (status === null) {
      return;
    }
    AlertDialog.show({
      title: $r('app.string.budget_alert_title'),
      message: $r('app.string.budget_alert_msg',
        status.monthExpenses.toFixed(2), (status.monthExpenses - status.limit).toFixed(2)),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.confirm'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.budget_adjust_action'),
        fontColor: $r('app.color.green'),
        action: (): void => {
          router.pushUrl({ url: 'pages/BudgetSettings' }).catch((err: Error): void => {
            Logger.error('跳转消费额度设置失败', err.message);
          });
        }
      }
    });
  }

  // 键盘弹出时隐藏底部导航栏，避免导航栏被顶到键盘上方；收起时恢复
  async registerKeyboardListener(): Promise<void> {
    try {
      const win = await window.getLastWindow(getContext(this));
      win.on('keyboardHeightChange', (height: number) => {
        this.keyboardVisible = height > 0;
      });
    } catch (err) {
      Logger.error('监听键盘高度失败', (err as Error).message);
    }
  }

  goAddAccount(): void {
    this.showAddMenu = false;
    router.pushUrl({ url: 'pages/AddAccount' });
  }

  goRecognize(source: string): void {
    this.showAddMenu = false;
    const param: RecognizeSourceParam = { source: source };
    router.pushUrl({ url: 'pages/RecognizeBill', params: param });
  }

  @Builder TabItem(icon: ResourceStr, label: ResourceStr, index: number) {
    Column({ space: 2 }) {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(this.currentTab === index ? $r('app.color.green') : $r('app.color.font_2'))
      Text(label)
        .fontSize(11)
        .fontColor(this.currentTab === index ? $r('app.color.green') : $r('app.color.font_2'))
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentTab = index;
    })
  }

  @Builder AddButton() {
    Column() {
      Image($r('app.media.add'))
        .width(26)
        .height(26)
        .fillColor($r('app.color.white'))
    }
    .width(52)
    .height(52)
    .borderRadius(26)
    .backgroundColor($r('app.color.green'))
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .shadow({ radius: 12, color: '#3313C791', offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.showAddMenu = true;
    })
  }

  @Builder AddMenuOption(icon: ResourceStr, label: ResourceStr, action: () => void) {
    Row({ space: SPACE_MEDIUM }) {
      Column() {
        Image(icon)
          .width(22)
          .height(22)
          .fillColor($r('app.color.green'))
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.green_alpha'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      Text(label)
        .fontSize(16)
        .fontColor($r('app.color.font_3'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .padding({ left: SPACE_LARGE, right: SPACE_LARGE })
    .onClick(action)
  }

  @Builder AddMenu() {
    Column() {
      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#66000000')
        .onClick(() => {
          this.showAddMenu = false;
        })
      Column({ space: SPACE_SMALL }) {
        Text($r('app.string.add_menu_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.font_3'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: SPACE_MEDIUM, bottom: SPACE_SMALL })
        this.AddMenuOption($r('app.media.add'), $r('app.string.add_menu_manual'), (): void => {
          this.goAddAccount();
        })
        this.AddMenuOption($r('app.media.camera'), $r('app.string.pick_from_camera'), (): void => {
          this.goRecognize('camera');
        })
        this.AddMenuOption($r('app.media.gallery'), $r('app.string.pick_from_gallery'), (): void => {
          this.goRecognize('gallery');
        })
        Button($r('app.string.cancel'))
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor($r('app.color.font_2'))
          .backgroundColor($r('app.color.grey_1'))
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .margin({ left: SPACE_LARGE, right: SPACE_LARGE, bottom: SPACE_LARGE })
          .onClick(() => {
            this.showAddMenu = false;
          })
      }
      .width('100%')
      .backgroundColor($r('app.color.white'))
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Column() {
        Column() {
          if (this.currentTab === 0) {
            Home()
          } else if (this.currentTab === 1) {
            AiAssistant()
          } else if (this.currentTab === 2) {
            Stats()
          } else {
            SettingsView()
          }
        }
        .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
        .layoutWeight(1)

        if (!this.keyboardVisible) {
          Row() {
            this.TabItem($r('app.media.home'), $r('app.string.home'), 0)
            this.TabItem($r('app.media.ai'), $r('app.string.ai_assistant'), 1)
            this.AddButton()
            this.TabItem($r('app.media.stats'), $r('app.string.statistics'), 2)
            this.TabItem($r('app.media.settings'), $r('app.string.settings'), 3)
          }
          .width('100%')
          .height(60)
          .padding({ left: SPACE_SMALL, right: SPACE_SMALL })
          .backgroundColor($r('app.color.white'))
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.bg'))

      if (this.showAddMenu) {
        this.AddMenu()
      }
    }
    .width('100%')
    .height('100%')
  }
}
