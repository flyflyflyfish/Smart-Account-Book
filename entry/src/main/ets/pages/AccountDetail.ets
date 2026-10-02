import router from '@ohos.router';
import Navigator from '../components/Navigator';
import AccountItem from '../components/AccountItem';
import GroupHeader from '../components/GroupHeader';
import { AccountType, GroupByDate, ItemRecordInfo } from '../models/account/account';
import AccountService from '../service/account';
import StatsService from '../service/stats';
import BillStore, { BillChangeListener } from '../common/BillStore';
import { Toast } from '../components/ToastDialog';
import BreakpointConstants from '../common/breakpoint';
import { Logger } from '../utils/Logger';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_XLARGE } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

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

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  @State accountType: number = AccountType.EXPENSES;
  @State accountList: GroupByDate[] = [];
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  private startTime: number = 0;
  private endTime: number = 0;
  // 账单增删后由 BillStore 通知刷新
  private billListener: BillChangeListener = () => {
    this.loadData();
  };

  async aboutToAppear(): Promise<void> {
    BillStore.subscribe(this.billListener);
    // 路由参数是不透明数据，统一校验类型后再使用
    const params = router.getParams() as AccountDetailParams | undefined;
    this.startTime = params && typeof params.startTime === 'number' ? params.startTime : 0;
    this.endTime = params && typeof params.endTime === 'number' ? params.endTime : 0;
    this.accountType = params && typeof params.accountType === 'number' ? params.accountType : AccountType.EXPENSES;
    await this.loadData();
  }

  aboutToDisappear(): void {
    BillStore.unsubscribe(this.billListener);
  }

  async loadData(): Promise<void> {
    try {
      const res = await AccountService.getRangeAccountByType(this.startTime, this.endTime, this.accountType);
      this.accountList = StatsService.groupByDate(res);
    } catch (err) {
      Logger.error('加载账单详情失败', (err as Error).message);
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

  // 通过 AppStorage 把待编辑记录带给记账页，与首页编辑方式保持一致
  openEditPage(record: ItemRecordInfo): void {
    AppStorage.setOrCreate('editRecord', record);
    router.pushUrl({ url: 'pages/AddAccount' }).catch((err: Error): void => {
      Logger.error('跳转编辑页失败', err.message);
    });
  }

  @Builder GroupHeaderBuilder(item: GroupByDate) {
    GroupHeader({ group: item, accountType: this.accountType })
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

  @Builder EmptyView() {
    Column({ space: SPACE_LARGE }) {
      Image($r('app.media.empty'))
        .width(100)
        .objectFit(ImageFit.Contain)
      Text($r('app.string.detail_empty_tip'))
        .fontSize(this.fs(13))
        .lineHeight(this.fs(18))
        .fontColor(this.tk().textSecondary)
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
                    }.swipeAction({ end: this.AccountItemOperate(record) })
                    .onClick(() => {
                      this.openEditPage(record);
                    })
                  })
                }.divider({ strokeWidth: 1, color: this.tk().surfaceVariant })
              })
            }.divider({ strokeWidth: 1, color: this.tk().surfaceVariant })
            Divider().color(this.tk().surfaceVariant)
          } else {
            this.EmptyView()
          }
        }.width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
        .backgroundColor(this.tk().surface)
        .borderRadius(RADIUS_CARD)
        .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
        .padding(SPACE_LARGE)
      }.padding({ left: SPACE_XLARGE, right: SPACE_XLARGE })
      .margin({ top: SPACE_LARGE })
    }.width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }
}
