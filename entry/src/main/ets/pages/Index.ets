import router from '@ohos.router';
import window from '@ohos.window';
import dayjs from 'dayjs';
import { BusinessError } from '@kit.BasicServicesKit';
import Home from '../views/home';
import AiAssistant from '../views/aiAssistant';
import LedgerView from '../views/ledger';
import Stats from '../views/stats';
import SettingsView from '../views/settings';
import PreferenceUtil from '../utils/PreferenceUtil';
import DBUtil from '../utils/DBUtil';
import * as CONSTANTS from '../common/constants';
import { SECOND_TAB_STYLE_LEDGER } from '../common/constants';
import SecondTabStore, { SecondTabChangeListener } from '../common/SecondTabStore';
import BreakpointSystem from '../utils/BreakpointSystem';
import BreakpointConstants from '../common/breakpoint';
import BillStore, { BillChangeListener } from '../common/BillStore';
import BudgetService, { BudgetStatus } from '../service/BudgetService';
import { Logger } from '../utils/Logger';
import { SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';
import WidgetUpdater from '../common/widget/WidgetUpdater';

interface RecognizeSourceParam {
  source: string;
}

@Entry
@Component
struct Index {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  @State currentTab: number = 0;
  @State showAddMenu: boolean = false;
  @State keyboardVisible: boolean = false;
  // 底部第二页签样式：AI 助手 / 账本（外观-首页统计里可改，经 SecondTabStore 单例读取）
  @State secondTabStyle: string = SecondTabStore.current();

  // 第二页签是否为账本
  secondTabIsLedger(): boolean {
    return this.secondTabStyle === SECOND_TAB_STYLE_LEDGER;
  }
  private breakpointSystem: BreakpointSystem = new BreakpointSystem();
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  // 额度设置变更后重新检查是否超支
  @StorageProp('budgetVersion')
  @Watch('onBudgetChanged')
  budgetVersion: number = 0;
  // 第二页签样式变更：外观页切换时经 SecondTabStore 通知，即时刷新底部页签
  private secondTabListener: SecondTabChangeListener = () => {
    this.secondTabStyle = SecondTabStore.current();
  };
  // 卡片/外部拉起指定 Tab：应用存活时也能响应 quickTab 变化
  @StorageProp('quickTab')
  @Watch('onQuickTabChanged')
  quickTabWatch: number = -1;
  // 账单增删后检查本月支出是否越过消费额度，并同步刷新桌面小组件
  private billListener: BillChangeListener = () => {
    this.refreshBudgetAlert();
    WidgetUpdater.refreshAllForms(getContext(this), ThemeKit.palette());
  };
  // 持有窗口引用，销毁时取消键盘高度监听
  private mainWindow: window.Window | undefined = undefined;
  // 预算检查进行中标志：批量插账时多次 notifyChanged 并发触发，去重避免重复弹窗/通知
  private budgetChecking: boolean = false;

  async aboutToAppear() {
    this.breakpointSystem.register();
    this.registerKeyboardListener();
    const quickTab = AppStorage.get<number>('quickTab');
    if (typeof quickTab === 'number' && quickTab >= 0 && quickTab <= 3) {
      this.currentTab = quickTab;
      AppStorage.delete('quickTab');
    }
    await DBUtil.ready;
    // 数据库就绪说明 EntryAbility 已完成偏好加载，重读一次避免启动竞态读到默认值
    this.secondTabStyle = SecondTabStore.current();
    SecondTabStore.subscribe(this.secondTabListener);
    BillStore.subscribe(this.billListener);
    this.refreshBudgetAlert();
    WidgetUpdater.refreshAllForms(getContext(this), ThemeKit.palette());
    const firstUseTime = Number(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_USER_FIRST_KEY, 0));
    if (!firstUseTime) {
      PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_USER_FIRST_KEY, dayjs().valueOf())
        .catch((err: BusinessError): void => {
          Logger.error('记录首次使用时间失败', err.message);
        });
    }
  }

  aboutToDisappear() {
    this.breakpointSystem.unRegister();
    SecondTabStore.unsubscribe(this.secondTabListener);
    BillStore.unsubscribe(this.billListener);
    this.unregisterKeyboardListener();
  }

  // 从外观页等返回时重读第二页签样式，保证切换立即生效
  onPageShow(): void {
    this.secondTabStyle = SecondTabStore.current();
  }

  onBudgetChanged(): void {
    this.refreshBudgetAlert();
  }

  onQuickTabChanged(): void {
    if (this.quickTabWatch >= 0 && this.quickTabWatch <= 3) {
      this.currentTab = this.quickTabWatch;
    }
    AppStorage.delete('quickTab');
  }

  // 本月首次越过额度时弹窗提醒（系统通知由 BudgetService 发送）
  async refreshBudgetAlert(): Promise<void> {
    // 并发去重：批量插账会在短时间内触发多次检查，避免重复弹窗/重复通知
    if (this.budgetChecking) {
      return;
    }
    this.budgetChecking = true;
    try {
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
          fontColor: this.tk().primary,
          action: (): void => {
            router.pushUrl({ url: 'pages/BudgetSettings' }).catch((err: Error): void => {
              Logger.error('跳转消费额度设置失败', err.message);
            });
          }
        }
      });
    } finally {
      this.budgetChecking = false;
    }
  }

  // 键盘弹出时隐藏底部导航栏，避免导航栏被顶到键盘上方；收起时恢复
  async registerKeyboardListener(): Promise<void> {
    try {
      const win = await window.getLastWindow(getContext(this));
      this.mainWindow = win;
      win.on('keyboardHeightChange', (height: number) => {
        this.keyboardVisible = height > 0;
      });
    } catch (err) {
      Logger.error('监听键盘高度失败', (err as Error).message);
    }
  }

  // 取消键盘高度监听，避免窗口重建场景下重复注册
  unregisterKeyboardListener(): void {
    if (this.mainWindow) {
      this.mainWindow.off('keyboardHeightChange');
      this.mainWindow = undefined;
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
        .fillColor(this.currentTab === index ? this.tk().primary : this.tk().textSecondary)
      Text(label)
        .fontSize(this.fs(11))
        .fontColor(this.currentTab === index ? this.tk().primary : this.tk().textSecondary)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentTab = index;
    })
  }

  // 第二页签（AI 助手 / 账本）：@Builder 按值传参不随状态刷新，
  // 图标与文案必须在 Builder 体内直接读取 secondTabStyle 才能即时切换
  @Builder SecondTabItem() {
    Column({ space: 2 }) {
      Image(this.secondTabIsLedger() ? $r('app.media.ledger') : $r('app.media.ai'))
        .width(22)
        .height(22)
        .fillColor(this.currentTab === 1 ? this.tk().primary : this.tk().textSecondary)
      Text(this.secondTabIsLedger() ? $r('app.string.ledger') : $r('app.string.ai_assistant'))
        .fontSize(this.fs(11))
        .fontColor(this.currentTab === 1 ? this.tk().primary : this.tk().textSecondary)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentTab = 1;
    })
  }

  @Builder AddButton() {
    Column() {
      Image($r('app.media.add'))
        .width(26)
        .height(26)
        .fillColor(this.tk().surface)
    }
    .width(52)
    .height(52)
    .borderRadius(26)
    .backgroundColor(this.tk().primary)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .shadow({ radius: 12, color: this.tk().primaryShadow, offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.showAddMenu = true;
    })
  }

  @Builder AddMenuOption(icon: ResourceStr, label: ResourceStr, action: () => void,
    accent: string, accentSoft: string) {
    Row({ space: SPACE_MEDIUM }) {
      Column() {
        Image(icon)
          .width(22)
          .height(22)
          .fillColor(accent)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(accentSoft)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      Text(label)
        .fontSize(this.fs(16))
        .fontColor(this.tk().textPrimary)
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
        .backgroundColor(this.tk().scrim)
        .onClick(() => {
          this.showAddMenu = false;
        })
      Column({ space: SPACE_SMALL }) {
        Text($r('app.string.add_menu_title'))
          .fontSize(this.fs(16))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().textPrimary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: SPACE_MEDIUM, bottom: SPACE_SMALL })
        this.AddMenuOption($r('app.media.add'), $r('app.string.add_menu_manual'), (): void => {
          this.goAddAccount();
        }, this.tk().primary, this.tk().primarySoft)
        this.AddMenuOption($r('app.media.camera'), $r('app.string.pick_from_camera'), (): void => {
          this.goRecognize('camera');
        }, this.tk().accentBlue, this.tk().accentBlueSoft)
        this.AddMenuOption($r('app.media.gallery'), $r('app.string.pick_from_gallery'), (): void => {
          this.goRecognize('gallery');
        }, this.tk().accentOrange, this.tk().accentOrangeSoft)
        Button($r('app.string.cancel'))
          .width('100%')
          .height(44)
          .fontSize(this.fs(15))
          .fontColor(this.tk().textSecondary)
          .backgroundColor(this.tk().surfaceVariant)
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .margin({ left: SPACE_LARGE, right: SPACE_LARGE, bottom: SPACE_LARGE })
          .onClick(() => {
            this.showAddMenu = false;
          })
      }
      .width('100%')
      .backgroundColor(this.tk().surface)
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
            if (this.secondTabIsLedger()) {
              LedgerView()
            } else {
              AiAssistant()
            }
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
            this.SecondTabItem()
            this.AddButton()
            this.TabItem($r('app.media.stats'), $r('app.string.statistics'), 2)
            this.TabItem($r('app.media.settings'), $r('app.string.settings'), 3)
          }
          .width('100%')
          .height(60)
          .padding({ left: SPACE_SMALL, right: SPACE_SMALL })
          .backgroundColor(this.tk().surface)
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.tk().background)

      if (this.showAddMenu) {
        this.AddMenu()
      }
    }
    .width('100%')
    .height('100%')
  }
}
