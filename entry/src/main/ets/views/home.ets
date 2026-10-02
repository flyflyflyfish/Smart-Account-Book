import dayjs from 'dayjs';
import router from '@ohos.router';
import { GroupByDate, ItemRecordInfo } from '../models/account/account';
import AccountService from '../service/account';
import StatsService from '../service/stats';
import BudgetService from '../service/BudgetService';
import BillStore, { BillChangeListener } from '../common/BillStore';
import GroupHeader from '../components/GroupHeader';
import { Toast } from '../components/ToastDialog';
import AccountItem from '../components/AccountItem';
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

@Extend(Text) function infoFont(fontSize: number, lineHeight: number) {
  .fontSize(fontSize)
  .lineHeight(lineHeight)
  .fontColor($r('app.color.font_1'))
}

@Component
export default struct Home {
  @State accountList: GroupByDate[] = [];
  @State expenses: number = 0;
  @State income: number = 0;
  // 月度消费额度状态，账单或额度设置变更后刷新
  @State budgetEnabled: boolean = false;
  @State budgetLimit: number = 0;
  @State budgetMonthExpenses: number = 0;
  // 首页所选日期，默认今天，可切换查看其他日期
  @State selectedDate: number = dayjs().startOf('day').valueOf();
  // 批量删除模式
  @State batchMode: boolean = false;
  // 批量模式下勾选的账单 id
  @State selectedIds: string[] = [];
  // 账单增删后由 BillStore 通知刷新
  private billListener: BillChangeListener = () => {
    this.queryByDate();
  };

  async queryByDate(): Promise<void> {
    try {
      const start = dayjs(this.selectedDate).startOf('day').valueOf();
      const end = dayjs(this.selectedDate).endOf('day').valueOf();
      const res = await AccountService.queryByDateRange(start, end);
      this.accountList = StatsService.groupByDate(res);
      const total = StatsService.statsConsume(res);
      this.expenses = total.expenses;
      this.income = total.income;
      this.refreshBudgetStatus();
    } catch (err) {
      Logger.error('查询当日记录失败', (err as Error).message);
    }
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
      return $r('app.color.red');
    }
    if (this.budgetNear()) {
      return $r('app.color.orange');
    }
    return $r('app.color.green');
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
        fontColor: $r('app.color.red'),
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
        fontColor: $r('app.color.red'),
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
        .backgroundColor($r('app.color.red'))
        .onClick(() => {
          this.confirmDelete(record)
        })
    }.height('100%')
    .margin({ left: SPACE_MEDIUM })
  }

  @Builder DateSelector() {
    Row({ space: SPACE_SMALL }) {
      Row({ space: SPACE_SMALL }) {
        Text(this.isToday() ? $r('app.string.today') : dayjs(this.selectedDate).format('YYYY-MM-DD'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.font_1'))
        Image($r('app.media.arrow_down'))
          .width(14)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.font_2'))
      }
      .onClick(() => {
        this.showDatePicker();
      })
      Blank()
      Text(this.batchMode ? $r('app.string.cancel') : $r('app.string.batch_manage'))
        .fontSize(14)
        .fontColor($r('app.color.green'))
        .onClick(() => {
          this.toggleBatchMode();
        })
    }.width('100%')
  }

  @Builder BatchOperateBar() {
    Row({ space: SPACE_MEDIUM }) {
      Button(this.selectedIds.length === this.allRecordIds().length ? $r('app.string.cancel_select_all') : $r('app.string.select_all'))
        .layoutWeight(1)
        .height(40)
        .fontSize(15)
        .backgroundColor($r('app.color.white'))
        .fontColor($r('app.color.font_3'))
        .type(ButtonType.Normal)
        .borderRadius(SPACE_SMALL)
        .onClick(() => {
          this.toggleSelectAll();
        })
      Button($r('app.string.batch_delete_count', this.selectedIds.length))
        .layoutWeight(1)
        .height(40)
        .fontSize(15)
        .backgroundColor($r('app.color.red'))
        .fontColor($r('app.color.white'))
        .type(ButtonType.Normal)
        .borderRadius(SPACE_SMALL)
        .onClick(() => {
          this.confirmBatchDelete();
        })
    }.width('100%')
  }

  @Builder BalanceBadge() {
    Row({ space: SPACE_TINY }) {
      Text($r('app.string.day_balance_label'))
        .fontSize(12)
        .lineHeight(15)
        .fontColor(this.balance() >= 0 ? $r('app.color.green') : $r('app.color.red'))
      Text((this.balance() >= 0 ? '+' : '-') + '¥ ' + Math.abs(this.balance()).toFixed(2))
        .fontSize(12)
        .lineHeight(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.balance() >= 0 ? $r('app.color.green') : $r('app.color.red'))
    }.padding({
      left: SPACE_SMALL,
      right: SPACE_SMALL,
      top: SPACE_TINY,
      bottom: SPACE_TINY
    })
    .backgroundColor(this.balance() >= 0 ? $r('app.color.green_alpha') : $r('app.color.red_alpha'))
    .borderRadius(RADIUS_BADGE)
  }

  @Builder BudgetCard() {
    Column({ space: SPACE_SMALL }) {
      Row() {
        Text($r('app.string.budget_card_title'))
          .fontSize(13)
          .fontColor($r('app.color.font_2'))
        Blank()
        if (this.budgetOver()) {
          Text($r('app.string.budget_over_row_label', this.budgetOverAmount().toFixed(2)))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.red'))
        } else {
          Text($r('app.string.budget_remaining_label', this.budgetRemaining().toFixed(2)))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.budgetNear() ? $r('app.color.orange') : $r('app.color.green'))
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
          .fontSize(12)
          .fontColor($r('app.color.font_2'))
        Blank()
        Text(this.budgetUsagePercent().toFixed(0) + '%')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.budgetProgressColor())
      }.width('100%')
      if (this.budgetOver()) {
        Text($r('app.string.budget_over_banner', this.budgetOverAmount().toFixed(2)))
          .width('100%')
          .fontSize(12)
          .lineHeight(17)
          .fontColor($r('app.color.red'))
      }
    }
    .width('100%')
    .padding(SPACE_MEDIUM)
    .backgroundColor(this.budgetOver() ? $r('app.color.red_alpha') : $r('app.color.white'))
    .borderRadius(RADIUS_CARD)
  }

  @Builder EmptyView() {
    Column({ space: SPACE_LARGE }) {
      Image($r('app.media.empty'))
        .width(100)
        .objectFit(ImageFit.Contain)
      Column({ space: SPACE_SMALL }) {
        Text($r('app.string.empty_tip'))
          .fontSize(13)
          .lineHeight(18)
          .fontColor($r('app.color.font_2'))
        Text($r('app.string.empty_tip_sub'))
          .fontSize(12)
          .lineHeight(17)
          .fontColor($r('app.color.font_2'))
          .opacity(0.7)
      }
    }.width('100%')
    .margin({ top: 60 })
  }

  build() {
    Column({ space: SPACE_MEDIUM }) {
      this.DateSelector()
      Text($r('app.string.day_expenses'))
        .infoFont(12, 15)
        .opacity(0.7)
      Text('¥ ' + this.expenses.toFixed(2))
        .infoFont(36, 44)
        .fontWeight(FontWeight.Bold)
      Row({ space: SPACE_MEDIUM }) {
        Row({ space: SPACE_TINY }) {
          Text($r('app.string.day_income_label'))
            .infoFont(12, 15)
            .opacity(0.7)
          Text('¥ ' + this.income.toFixed(2))
            .infoFont(14, 18)
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
                })
              }.divider({ strokeWidth: 1, color: $r('app.color.grey_1') })
            })
          }.divider({ strokeWidth: 1, color: $r('app.color.grey_1') })
          Divider().color($r('app.color.grey_1'))
        } else {
          this.EmptyView()
        }
      }.width('100%')
      .backgroundColor($r('app.color.white'))
      .layoutWeight(1)
      .borderRadius(RADIUS_CARD)
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
