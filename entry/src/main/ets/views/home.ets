import dayjs from 'dayjs';
import router from '@ohos.router';
import { BusinessError } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { GroupByDate, ItemRecordInfo } from '../models/account/account';
import { StatsType } from '../models/stats/stats';
import AccountService from '../service/account';
import StatsService from '../service/stats';
import BudgetService from '../service/BudgetService';
import BillStore, { BillChangeListener } from '../common/BillStore';
import GroupHeader from '../components/GroupHeader';
import PeriodPickerDialog from '../components/stats/PeriodPickerDialog';
import { Toast } from '../components/ToastDialog';
import AccountItem from '../components/AccountItem';
import DBUtil from '../utils/DBUtil';
import { Logger } from '../utils/Logger';
import {
  PAGE_PADDING,
  RADIUS_BADGE,
  RADIUS_CARD,
  SPACE_LARGE,
  SPACE_MEDIUM,
  SPACE_SMALL,
  SPACE_TINY
} from '../common/dimens';
import { ThemeKit, ThemePalette, HOME_SCOPE_DAY, HOME_SCOPE_MONTH } from '../common/theme/Theme';

@Extend(Text) function infoFont(fontSize: number, lineHeight: number) {
  .fontSize(fontSize)
  .lineHeight(lineHeight)
}

  @Component
  export default struct Home {

  @StorageProp('themeSeq') @Watch('onThemeSeqChanged') themeSeq: number = 0;
  // 额度配置保存/云端同步后刷新额度卡片，否则返回首页仍显示关闭前的旧状态
  @StorageProp('budgetVersion') @Watch('onBudgetVersionChanged') budgetVersion: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }
  @State accountList: GroupByDate[] = [];
  @State expenses: number = 0;
  @State income: number = 0;
  // 首帧加载状态：数据库就绪前显示加载中，避免冷启动时误显示“暂无账单”
  @State loading: boolean = true;
  // 月度消费额度状态，账单或额度设置变更后刷新
  @State budgetEnabled: boolean = false;
  @State budgetLimit: number = 0;
  @State budgetMonthExpenses: number = 0;
  // 首页所选日期，默认今天；按日口径看当天，按月口径看所在月
  @State selectedDate: number = dayjs().startOf('day').valueOf();
  // 批量删除模式
  @State batchMode: boolean = false;
  // 批量模式下勾选的账单 id
  @State selectedIds: string[] = [];
  // 月份选择弹窗（按月口径下顶部点击打开）
  monthPickerController = new CustomDialogController({
    builder: PeriodPickerDialog({
      mode: StatsType.MONTH,
      time: this.selectedDate,
      getTime: (): number => this.selectedDate,
      minYear: dayjs().year() - 4,
      onChange: (picked: number) => {
        this.selectedDate = dayjs(picked).startOf('month').valueOf();
        this.queryByDate();
      }
    }),
    customStyle: true,
    alignment: DialogAlignment.Center
  });
  // 账单增删后由 BillStore 通知刷新
  private billListener: BillChangeListener = () => {
    this.queryByDate();
  };

  async queryByDate(): Promise<void> {
    try {
      // 冷启动时数据库初始化与页面加载并行，先等待就绪再查询，避免查询失败误显示空态
      await DBUtil.ready;
      // 按日口径查当天，按月口径查所选日期所在月，列表与顶部汇总同口径
      const anchor = dayjs(this.selectedDate);
      const start = this.scopeIsMonth() ? anchor.startOf('month').valueOf() : anchor.startOf('day').valueOf();
      const end = this.scopeIsMonth() ? anchor.endOf('month').valueOf() : anchor.endOf('day').valueOf();
      const res = await AccountService.queryByDateRange(start, end);
      this.accountList = StatsService.groupByDate(res);
      const total = StatsService.statsConsume(res);
      this.expenses = total.expenses;
      this.income = total.income;
      this.refreshBudgetStatus();
    } catch (err) {
      Logger.error('查询记录失败', (err as Error).message);
    } finally {
      this.loading = false;
    }
  }

  // 首页汇总口径：按日 / 按月（设置页可改，默认按月）
  scopeIsMonth(): boolean {
    return ThemeKit.currentHomeScope() === HOME_SCOPE_MONTH;
  }

  // 外观设置（含汇总口径）变更后按新口径重查
  onThemeSeqChanged(): void {
    this.queryByDate();
  }

  // 额度设置页保存或云端同步额度后重查额度卡片
  onBudgetVersionChanged(): void {
    this.refreshBudgetStatus();
  }

  // 查询本月支出与消费额度使用情况
  async refreshBudgetStatus(): Promise<void> {
    try {
      const status = await BudgetService.loadStatus();
      this.budgetEnabled = status.enabled;
      this.budgetLimit = status.limit;
      this.budgetMonthExpenses = status.monthExpenses;
    } catch (err) {
      Logger.error('查询月度消费额度失败', (err as Error).message);
    }
  }

  budgetOver(): boolean {
    return this.budgetEnabled && this.budgetLimit > 0 && this.budgetMonthExpenses > this.budgetLimit;
  }

  budgetNear(): boolean {
    if (!this.budgetEnabled || this.budgetLimit <= 0 || this.budgetOver()) {
      return false;
    }
    return this.budgetMonthExpenses / this.budgetLimit >= 0.8;
  }

  budgetUsagePercent(): number {
    if (this.budgetLimit <= 0) {
      return 0;
    }
    return Math.min(100, this.budgetMonthExpenses / this.budgetLimit * 100);
  }

  budgetOverAmount(): number {
    return this.budgetMonthExpenses - this.budgetLimit;
  }

  budgetRemaining(): number {
    return this.budgetLimit - this.budgetMonthExpenses;
  }

  budgetProgressColor(): ResourceColor {
    if (this.budgetOver()) {
      return this.tk().danger;
    }
    if (this.budgetNear()) {
      return this.tk().warning;
    }
    return this.tk().primary;
  }

  aboutToAppear(): void {
    BillStore.subscribe(this.billListener);
    this.queryByDate();
    this.refreshBudgetStatus();
  }

  aboutToDisappear(): void {
    BillStore.unsubscribe(this.billListener);
  }

  balance(): number {
    return this.income - this.expenses;
  }

  isToday(): boolean {
    return dayjs(this.selectedDate).isSame(dayjs(), 'day');
  }

  isThisMonth(): boolean {
    return dayjs(this.selectedDate).isSame(dayjs(), 'month');
  }

  // 顶部时间段文案：按月口径显示“本月/YYYY-MM”，按日口径显示“今天/YYYY-MM-DD”
  periodLabel(): ResourceStr {
    if (this.scopeIsMonth()) {
      return this.isThisMonth() ? $r('app.string.home_month_current')
        : dayjs(this.selectedDate).format('YYYY-MM');
    }
    return this.isToday() ? $r('app.string.today')
      : dayjs(this.selectedDate).format('YYYY-MM-DD');
  }

  openMonthPicker(): void {
    this.monthPickerController.open();
  }

  // 长按「本月/本日」时间段：快捷切换首页统计口径（与 设置→外观→功能 同一数据源，双向同步）
  showScopeMenu(): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: $r('app.string.home_scope_menu_title'),
      buttons: [
        { text: $r('app.string.appearance_home_scope_day'), color: this.tk().textPrimary },
        { text: $r('app.string.appearance_home_scope_month'), color: this.tk().textPrimary }
      ]
    })
      .then((response: promptAction.ActionMenuSuccessResponse) => {
        const scope = response.index === 0 ? HOME_SCOPE_DAY : HOME_SCOPE_MONTH;
        if (scope !== ThemeKit.currentHomeScope()) {
          ThemeKit.setHomeScope(scope);
        }
      })
      .catch((err: BusinessError): void => {
        Logger.error('打开统计口径切换菜单失败', err.message);
      });
  }

  showDatePicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-1-1'),
      end: new Date(),
      selected: new Date(this.selectedDate),
      onDateAccept: (value: Date) => {
        this.selectedDate = dayjs(value).startOf('day').valueOf();
        this.queryByDate();
      }
    });
  }

  toggleBatchMode(): void {
    this.batchMode = !this.batchMode;
    this.selectedIds = [];
  }

  // 用 checked 入参做幂等更新，避免"全选"时因 onChange 反复取反导致 AppFreeze
  toggleSelect(id: string, checked: boolean): void {
    const idx = this.selectedIds.indexOf(id);
    if (checked) {
      if (idx < 0) {
        this.selectedIds.push(id);
        this.selectedIds = this.selectedIds.slice();
      }
    } else {
      if (idx >= 0) {
        this.selectedIds.splice(idx, 1);
        this.selectedIds = this.selectedIds.slice();
      }
    }
  }

  allRecordIds(): string[] {
    const ids: string[] = [];
    for (const group of this.accountList) {
      for (const record of group.records) {
        ids.push(record.id);
      }
    }
    return ids;
  }

  toggleSelectAll(): void {
    const all = this.allRecordIds();
    if (this.selectedIds.length === all.length) {
      this.selectedIds = [];
    } else {
      this.selectedIds = all.slice();
    }
  }

  confirmBatchDelete(): void {
    if (this.selectedIds.length === 0) {
      Toast.error($r('app.string.require_select'));
      return;
    }
    AlertDialog.show({
      title: $r('app.string.delete_confirm_title'),
      message: $r('app.string.batch_delete_confirm_msg', this.selectedIds.length),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: this.tk().danger,
        action: () => {
          this.batchDelete();
        }
      }
    });
  }

  async batchDelete(): Promise<void> {
    try {
      await AccountService.deleteByIds(this.selectedIds);
      this.selectedIds = [];
      this.batchMode = false;
    } catch (err) {
      Logger.error('批量删除失败', (err as Error).message);
      Toast.error($r('app.string.delete_failed'));
    }
  }

  deleteRecord(id: string): void {
    // 删除成功后由 BillStore 通知刷新，无需手动重新查询
    AccountService.deleteById(id).catch((err: Error): void => {
      Logger.error('删除记录失败', err.message);
      Toast.error($r('app.string.delete_failed'));
    })
  }

  // 删除前二次确认，避免误滑误删
  confirmDelete(record: ItemRecordInfo): void {
    AlertDialog.show({
      title: $r('app.string.delete_confirm_title'),
      message: $r('app.string.delete_confirm_msg'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: this.tk().danger,
        action: () => {
          this.deleteRecord(record.id);
        }
      }
    });
  }

  // 通过 AppStorage 把待编辑记录带给记账页，与现有页面传参方式保持一致
  openEditPage(record: ItemRecordInfo): void {
    AppStorage.setOrCreate('editRecord', record);
    router.pushUrl({ url: 'pages/AddAccount' }).catch((err: Error): void => {
      Logger.error('跳转编辑页失败', err.message);
    });
  }

  @Builder GroupHeaderBuilder(item: GroupByDate) {
    GroupHeader({ group: item })
  }

  @Builder AccountItemOperate(record: ItemRecordInfo) {
    Row() {
      Button($r('app.string.delete'))
        .type(ButtonType.Normal)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.tk().danger)
        .onClick(() => {
          this.confirmDelete(record)
        })
    }.height('100%')
    .margin({ left: SPACE_MEDIUM })
  }

  @Builder DateSelector() {
    Row({ space: SPACE_SMALL }) {
      Row({ space: SPACE_SMALL }) {
        Text(this.periodLabel())
          .fontSize(this.fs(16))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().textPrimary)
        Image($r('app.media.arrow_down'))
          .width(14)
          .objectFit(ImageFit.Contain)
          .fillColor(this.tk().textSecondary)
      }
      .onClick(() => {
        if (this.scopeIsMonth()) {
          this.openMonthPicker();
        } else {
          this.showDatePicker();
        }
      })
      .gesture(LongPressGesture({ repeat: false, duration: 300 })
        .onAction(() => {
          this.showScopeMenu();
        }))
      Blank()
      Row({ space: SPACE_MEDIUM }) {
        Text(this.batchMode ? $r('app.string.cancel') : $r('app.string.batch_manage'))
          .fontSize(this.fs(14))
          .fontColor(this.tk().primary)
          .onClick(() => {
            this.toggleBatchMode();
          })
        // 右上角搜索入口：跳转全局账单搜索页（36vp 圆形热区，方便点击）
        Row() {
          Image($r('app.media.search'))
            .width(20)
            .height(20)
            .objectFit(ImageFit.Contain)
            .fillColor(this.tk().textPrimary)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.tk().surfaceVariant)
        .onClick(() => {
          this.openSearchPage();
        })
      }.alignItems(VerticalAlign.Center)
    }.width('100%')
  }

  // 跳转全局账单搜索页
  openSearchPage(): void {
    router.pushUrl({ url: 'pages/BillSearch' }).catch((err: Error): void => {
      Logger.error('跳转搜索页失败', err.message);
    });
  }

  @Builder BatchOperateBar() {
    Row({ space: SPACE_MEDIUM }) {
      Button(this.selectedIds.length === this.allRecordIds().length ? $r('app.string.cancel_select_all') : $r('app.string.select_all'))
        .layoutWeight(1)
        .height(40)
        .fontSize(this.fs(15))
        .backgroundColor(this.tk().surface)
        .fontColor(this.tk().textPrimary)
        .type(ButtonType.Normal)
        .borderRadius(SPACE_SMALL)
        .onClick(() => {
          this.toggleSelectAll();
        })
      Button($r('app.string.batch_delete_count', this.selectedIds.length))
        .layoutWeight(1)
        .height(40)
        .fontSize(this.fs(15))
        .backgroundColor(this.tk().danger)
        .fontColor(this.tk().surface)
        .type(ButtonType.Normal)
        .borderRadius(SPACE_SMALL)
        .onClick(() => {
          this.confirmBatchDelete();
        })
    }.width('100%')
  }

  @Builder BalanceBadge() {
    Row({ space: SPACE_TINY }) {
      Text(this.scopeIsMonth() ? $r('app.string.month_balance_label') : $r('app.string.day_balance_label'))
        .fontSize(this.fs(12))
        .lineHeight(this.fs(15))
        .fontColor(this.balance() >= 0 ? this.tk().primary : this.tk().danger)
      Text((this.balance() >= 0 ? '+' : '-') + '¥ ' + Math.abs(this.balance()).toFixed(2))
        .fontSize(this.fs(12))
        .lineHeight(this.fs(15))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.balance() >= 0 ? this.tk().primary : this.tk().danger)
    }.padding({
      left: SPACE_SMALL,
      right: SPACE_SMALL,
      top: SPACE_TINY,
      bottom: SPACE_TINY
    })
    .backgroundColor(this.balance() >= 0 ? this.tk().primarySoft : this.tk().dangerSoft)
    .borderRadius(RADIUS_BADGE)
  }

  @Builder BudgetCard() {
    Column({ space: SPACE_SMALL }) {
      Row() {
        Text($r('app.string.budget_card_title'))
          .fontSize(this.fs(13))
          .fontColor(this.tk().textSecondary)
        Blank()
        if (this.budgetOver()) {
          Text($r('app.string.budget_over_row_label', this.budgetOverAmount().toFixed(2)))
            .fontSize(this.fs(13))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tk().danger)
        } else {
          Text($r('app.string.budget_remaining_label', this.budgetRemaining().toFixed(2)))
            .fontSize(this.fs(13))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.budgetNear() ? this.tk().warning : this.tk().primary)
        }
      }.width('100%')
      Progress({ value: this.budgetUsagePercent(), total: 100, type: ProgressType.Linear })
        .color(this.budgetProgressColor())
        .height(8)
        .borderRadius(4)
        .animation({ duration: 400, curve: Curve.EaseOut })
      Row() {
        Text($r('app.string.budget_usage_label',
          this.budgetMonthExpenses.toFixed(2), this.budgetLimit.toFixed(2)))
          .fontSize(this.fs(12))
          .fontColor(this.tk().textSecondary)
        Blank()
        Text(this.budgetUsagePercent().toFixed(0) + '%')
          .fontSize(this.fs(12))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.budgetProgressColor())
      }.width('100%')
      if (this.budgetOver()) {
        Text($r('app.string.budget_over_banner', this.budgetOverAmount().toFixed(2)))
          .width('100%')
          .fontSize(this.fs(12))
          .lineHeight(this.fs(17))
          .fontColor(this.tk().danger)
      }
    }
    .width('100%')
    .padding(SPACE_MEDIUM)
    .backgroundColor(this.budgetOver() ? this.tk().dangerSoft : this.tk().surface)
    .borderRadius(RADIUS_CARD)
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
  }

  @Builder LoadingView() {
    Column({ space: SPACE_MEDIUM }) {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(this.tk().primary)
      Text($r('app.string.loading_tip'))
        .fontSize(this.fs(13))
        .fontColor(this.tk().textSecondary)
    }.width('100%')
    .margin({ top: 60 })
  }

  @Builder EmptyView() {
    Column({ space: SPACE_LARGE }) {
      Image($r('app.media.empty'))
        .width(100)
        .objectFit(ImageFit.Contain)
      Column({ space: SPACE_SMALL }) {
        Text($r('app.string.empty_tip'))
          .fontSize(this.fs(13))
          .lineHeight(this.fs(18))
          .fontColor(this.tk().textSecondary)
        Text($r('app.string.empty_tip_sub'))
          .fontSize(this.fs(12))
          .lineHeight(this.fs(17))
          .fontColor(this.tk().textSecondary)
          .opacity(0.7)
      }
    }.width('100%')
    .margin({ top: 60 })
  }

  build() {
    Column({ space: SPACE_MEDIUM }) {
      this.DateSelector()
      Text(this.scopeIsMonth() ? $r('app.string.month_expenses') : $r('app.string.day_expenses'))
        .infoFont(this.fs(12), this.fs(15))
        .opacity(0.7)
      Text('¥ ' + this.expenses.toFixed(2))
        .infoFont(this.fs(36), this.fs(44))
        .fontWeight(FontWeight.Bold)
      Row({ space: SPACE_MEDIUM }) {
        Row({ space: SPACE_TINY }) {
          Text(this.scopeIsMonth() ? $r('app.string.home_income_label') : $r('app.string.day_income_label'))
            .infoFont(this.fs(12), this.fs(15))
            .opacity(0.7)
          Text('¥ ' + this.income.toFixed(2))
            .infoFont(this.fs(14), this.fs(18))
        }.alignItems(VerticalAlign.Center)
        this.BalanceBadge()
      }.alignItems(VerticalAlign.Center)
      if (this.budgetEnabled && this.budgetLimit > 0) {
        this.BudgetCard()
      }
      Column() {
        if (this.accountList.length) {
          List() {
            ForEach(this.accountList, (item: GroupByDate) => {
              ListItemGroup({
                header: this.GroupHeaderBuilder(item)
              }) {
                ForEach(item.records, (record: ItemRecordInfo) => {
                  ListItem() {
                    Row({ space: SPACE_SMALL }) {
                      if (this.batchMode) {
                        Checkbox()
                          .select(this.selectedIds.indexOf(record.id) >= 0)
                          .onChange((checked: boolean) => {
                            this.toggleSelect(record.id, checked);
                          })
                      }
                      AccountItem({ account: record })
                        .layoutWeight(1)
                    }.width('100%')
                  }.swipeAction({ end: this.AccountItemOperate(record) })
                  .onClick(() => {
                    if (!this.batchMode) {
                      this.openEditPage(record);
                    }
                  })
                }, (record: ItemRecordInfo): string => record.id)
              }.divider({ strokeWidth: 1, color: this.tk().surfaceVariant })
            }, (item: GroupByDate): string => item.time.toString() + '_' + JSON.stringify(item.records))
          }.divider({ strokeWidth: 1, color: this.tk().surfaceVariant })
          Divider().color(this.tk().surfaceVariant)
        } else if (this.loading) {
          this.LoadingView()
        } else {
          this.EmptyView()
        }
      }.width('100%')
      .backgroundColor(this.tk().surface)
      .layoutWeight(1)
      .borderRadius(RADIUS_CARD)
      .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
      .padding(SPACE_LARGE)
      if (this.batchMode) {
        this.BatchOperateBar()
      }
    }.width('100%')
    .height('100%')
    .padding(PAGE_PADDING)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }
}
