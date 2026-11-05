import router from '@ohos.router';
import Navigator from '../components/Navigator';
import AccountItem from '../components/AccountItem';
import GroupHeader from '../components/GroupHeader';
import { AccountType, GroupByDate, ItemRecordInfo } from '../models/account/account';
import AccountPO from '../models/account/accountPO';
import AccountService from '../service/account';
import StatsService from '../service/stats';
import BillStore, { BillChangeListener } from '../common/BillStore';
import { Toast } from '../components/ToastDialog';
import BreakpointConstants from '../common/breakpoint';
import { Logger } from '../utils/Logger';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_XLARGE } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

/**
 * 账单详情页路由参数
 */
export interface AccountDetailParams {
  startTime: number;
  endTime: number;
  accountType: number;
  // 分类下钻：传则只展示该分类（type = 分类 id）的账单，不传展示全部
  typeId?: number;
  // 页面标题：分类下钻时传分类名，不传用默认“详情”
  title?: string;
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
  // 页面标题：分类下钻时为分类名
  @State detailTitle: ResourceStr = $r('app.string.detail');
  // 分类下钻过滤：-1 表示不过滤
  private typeId: number = -1;
  // 批量删除模式
  @State batchMode: boolean = false;
  // 批量模式下勾选的账单 id
  @State selectedIds: string[] = [];
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
    this.typeId = params && typeof params.typeId === 'number' ? params.typeId : -1;
    this.detailTitle = params && typeof params.title === 'string' && params.title.length > 0
      ? params.title : $r('app.string.detail');
    await this.loadData();
  }

  aboutToDisappear(): void {
    BillStore.unsubscribe(this.billListener);
  }

  async loadData(): Promise<void> {
    try {
      const res = await AccountService.getRangeAccountByType(this.startTime, this.endTime, this.accountType);
      // 分类下钻：只保留该分类的账单
      const filtered = this.typeId >= 0
        ? res.filter((item: AccountPO): boolean => item.type === this.typeId)
        : res;
      this.accountList = StatsService.groupByDate(filtered);
    } catch (err) {
      Logger.error('加载账单详情失败', (err as Error).message);
    }
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

  // 卡片上方的批量管理入口：仅在有账单时展示
  @Builder BatchToolbar() {
    Row() {
      Blank()
      Text(this.batchMode ? $r('app.string.cancel') : $r('app.string.batch_manage'))
        .fontSize(this.fs(14))
        .fontColor(this.tk().primary)
        .onClick(() => {
          this.toggleBatchMode();
        })
    }.width('100%')
    .margin({ bottom: SPACE_SMALL })
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
      Navigator({ title: this.detailTitle })
      Column() {
        if (this.accountList.length) {
          this.BatchToolbar()
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
              }, (item: GroupByDate): string => item.time.toString())
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
        .layoutWeight(1)
      }.padding({ left: SPACE_XLARGE, right: SPACE_XLARGE })
      .margin({ top: SPACE_LARGE })
      .layoutWeight(1)
      if (this.batchMode) {
        Row() {
          this.BatchOperateBar()
        }.padding({ left: SPACE_XLARGE, right: SPACE_XLARGE })
        .margin({ top: SPACE_MEDIUM })
      }
    }.width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }
}
