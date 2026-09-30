import router from '@ohos.router';
import Navigator from '../components/Navigator';
import AccountItem from '../components/AccountItem';
import GroupHeader from '../components/GroupHeader';
import { AccountType, GroupByDate, ItemRecordInfo } from '../models/account/account';
import AccountService from '../service/account';
import StatsService from '../service/stats';
import BreakpointConstants from '../common/breakpoint';
import { Logger } from '../utils/Logger';
import { RADIUS_CARD, SPACE_LARGE, SPACE_XLARGE } from '../common/dimens';

/**
 * 账单详情页路由参数
 */
export interface AccountDetailParams {
  startTime: number;
  endTime: number;
  accountType: number;
}

@Entry
@Component
struct AccountDetail {
  @State accountType: number = AccountType.EXPENSES;
  @State accountList: GroupByDate[] = [];
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  async aboutToAppear(): Promise<void> {
    try {
      // 路由参数是不透明数据，统一校验类型后再使用
      const params = router.getParams() as AccountDetailParams | undefined;
      const startTime = params && typeof params.startTime === 'number' ? params.startTime : 0;
      const endTime = params && typeof params.endTime === 'number' ? params.endTime : 0;
      this.accountType = params && typeof params.accountType === 'number' ? params.accountType : AccountType.EXPENSES;
      const res = await AccountService.getRangeAccountByType(startTime, endTime, this.accountType);
      this.accountList = StatsService.groupByDate(res);
    } catch (err) {
      Logger.error('加载账单详情失败', (err as Error).message);
    }
  }

  @Builder GroupHeaderBuilder(item: GroupByDate) {
    GroupHeader({ group: item, accountType: this.accountType })
  }

  @Builder EmptyView() {
    Column({ space: SPACE_LARGE }) {
      Image($r('app.media.empty'))
        .width(100)
        .objectFit(ImageFit.Contain)
      Text($r('app.string.detail_empty_tip'))
        .fontSize(13)
        .lineHeight(18)
        .fontColor($r('app.color.font_2'))
    }.width('100%')
    .padding({ top: 60, bottom: 60 })
  }

  build() {
    Column() {
      Navigator({ title: $r('app.string.detail') })
      Column() {
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
                    }
                  })
                }.divider({ strokeWidth: 1, color: $r('app.color.grey_1') })
              })
            }.divider({ strokeWidth: 1, color: $r('app.color.grey_1') })
            Divider().color($r('app.color.grey_1'))
          } else {
            this.EmptyView()
          }
        }.width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
        .backgroundColor($r('app.color.white'))
        .borderRadius(RADIUS_CARD)
        .padding(SPACE_LARGE)
      }.padding({ left: SPACE_XLARGE, right: SPACE_XLARGE })
      .margin({ top: SPACE_LARGE })
    }.width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }
}
