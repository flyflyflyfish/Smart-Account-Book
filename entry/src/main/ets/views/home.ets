import dayjs from 'dayjs';
import router from '@ohos.router';
import { GroupByDate, ItemRecordInfo } from '../models/account/account';
import AccountService from '../service/account';
import StatsService from '../service/stats';
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
  // 账单增删后由 BillStore 通知刷新
  private billListener: BillChangeListener = () => {
    this.queryCurrentMonthAccountRecords();
  };

  async queryCurrentMonthAccountRecords(): Promise<void> {
    try {
      const currentTime = dayjs().valueOf();
      const res = await AccountService.getAccountByMonth(currentTime);
      this.accountList = StatsService.groupByDate(res);
      const total = StatsService.statsConsume(res);
      this.expenses = total.expenses;
      this.income = total.income;
    } catch (err) {
      Logger.error('查询本月记录失败', (err as Error).message);
    }
  }

  aboutToAppear(): void {
    BillStore.subscribe(this.billListener);
    this.queryCurrentMonthAccountRecords();
  }

  aboutToDisappear(): void {
    BillStore.unsubscribe(this.billListener);
  }

  balance(): number {
    return this.income - this.expenses;
  }

  deleteRecord(id: number): void {
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

  @Builder BalanceBadge() {
    Row({ space: SPACE_TINY }) {
      Text($r('app.string.month_balance_label'))
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
      Text($r('app.string.month_expenses'))
        .infoFont(12, 15)
        .opacity(0.7)
      Text('¥ ' + this.expenses.toFixed(2))
        .infoFont(36, 44)
        .fontWeight(FontWeight.Bold)
      Row({ space: SPACE_MEDIUM }) {
        Row({ space: SPACE_TINY }) {
          Text($r('app.string.home_income_label'))
            .infoFont(12, 15)
            .opacity(0.7)
          Text('¥ ' + this.income.toFixed(2))
            .infoFont(14, 18)
        }.alignItems(VerticalAlign.Center)
        this.BalanceBadge()
      }.alignItems(VerticalAlign.Center)
      Column() {
        if (this.accountList.length) {
          List() {
            ForEach(this.accountList, (item: GroupByDate) => {
              ListItemGroup({
                header: this.GroupHeaderBuilder(item)
              }) {
                ForEach(item.records, (record: ItemRecordInfo) => {
                  ListItem() {
                    AccountItem({ account: record })
                  }.swipeAction({ end: this.AccountItemOperate(record) })
                  .onClick(() => {
                    this.openEditPage(record);
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
    }.width('100%')
    .height('100%')
    .padding(PAGE_PADDING)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }
}
