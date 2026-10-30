import router from '@ohos.router';
import dayjs from 'dayjs';
import { BusinessError } from '@kit.BasicServicesKit';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';
import LedgerRepository from '../data/LedgerRepository';
import LedgerStore, { LedgerChangeListener } from '../common/LedgerStore';
import {
  Ledger,
  LedgerRecord,
  LEDGER_RECORD_EXPENSE,
  LEDGER_RECORD_NO_CATEGORY
} from '../models/ledger/Ledger';
import LedgerEditDialog from '../components/ledger/LedgerEditDialog';
import { ledgerAccent, ledgerAccentSoft } from '../components/ledger/ledgerColors';
import CategoryStore from '../models/accountType/CategoryStore';
import { AccountType } from '../models/account/account';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import DBUtil from '../utils/DBUtil';
import BreakpointConstants from '../common/breakpoint';
import {
  PAGE_PADDING,
  RADIUS_CARD,
  RADIUS_ICON,
  SPACE_LARGE,
  SPACE_MEDIUM,
  SPACE_SMALL,
  SPACE_TINY
} from '../common/dimens';

/**
 * 账本详情页路由参数
 */
interface LedgerDetailParams {
  id: string;
}

/**
 * 账本详情页：单个账本的汇总与记录列表，支持记一笔 / 重命名 / 删除账本
 */
@Entry
@Component
struct LedgerDetail {

  @StorageProp('themeSeq') themeSeq: number = 0;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @State ledgerInfo: Ledger | null = null;
  @State recordList: LedgerRecord[] = [];
  @State expenses: number = 0;
  @State income: number = 0;
  @State loading: boolean = true;
  // 批量管理模式：勾选记录后批量删除
  @State batchMode: boolean = false;
  @State selectedIds: string[] = [];

  private ledgerId: string = '';
  private repository: LedgerRepository = new LedgerRepository();
  // 账本数据变更（含记一笔页新增）后自动重查
  private storeListener: LedgerChangeListener = () => {
    this.loadData();
  };
  // 重命名弹窗
  private renameDialogController: CustomDialogController = new CustomDialogController({
    builder: LedgerEditDialog({
      dialogTitle: $r('app.string.ledger_rename'),
      getInitialName: (): string => this.ledgerName(),
      getInitialColorKey: (): string => this.ledgerColorKey(),
      onConfirm: (name: string, colorKey: string): void => {
        this.renameLedger(name, colorKey);
      }
    }),
    customStyle: true,
    alignment: DialogAlignment.Center
  });

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  // 结余：收入 - 支出
  balance(): number {
    return this.income - this.expenses;
  }

  // 结余文案：正负带符号，样式对齐首页 BalanceBadge
  balanceText(): string {
    const balance = this.balance();
    return (balance >= 0 ? '+' : '-') + '¥ ' + Math.abs(balance).toFixed(2);
  }

  ledgerName(): string {
    return this.ledgerInfo ? this.ledgerInfo.name : '';
  }

  ledgerColorKey(): string {
    return this.ledgerInfo ? this.ledgerInfo.colorKey : 'green';
  }

  async aboutToAppear(): Promise<void> {
    LedgerStore.subscribe(this.storeListener);
    // 路由参数是不透明数据，统一校验类型后再使用
    const params = router.getParams() as LedgerDetailParams | undefined;
    this.ledgerId = params && typeof params.id === 'string' ? params.id : '';
    await this.loadData();
  }

  aboutToDisappear(): void {
    LedgerStore.unsubscribe(this.storeListener);
  }

  async loadData(): Promise<void> {
    try {
      await DBUtil.ready;
      const ledger = await this.repository.queryLedgerById(this.ledgerId);
      if (ledger === null) {
        // 账本已被删除（或参数异常）时直接返回，避免停留在空页
        router.back();
        return;
      }
      this.ledgerInfo = ledger;
      const records = await this.repository.queryRecords(this.ledgerId);
      this.recordList = records;
      let expenses = 0;
      let income = 0;
      records.forEach((record: LedgerRecord) => {
        if (record.type === LEDGER_RECORD_EXPENSE) {
          expenses += record.amount;
        } else {
          income += record.amount;
        }
      });
      this.expenses = expenses;
      this.income = income;
    } catch (err) {
      Logger.error('加载账本详情失败', (err as Error).message);
    } finally {
      this.loading = false;
    }
  }

  async renameLedger(name: string, colorKey: string): Promise<void> {
    try {
      if (!this.ledgerInfo) {
        return;
      }
      if (name !== this.ledgerInfo.name) {
        await this.repository.renameLedger(this.ledgerId, name);
      }
      // 颜色 key 存于账本行，重命名弹窗里改色时同步更新：仅颜色变化时无需重命名
      if (colorKey !== this.ledgerInfo.colorKey) {
        await this.repository.updateLedgerColor(this.ledgerId, colorKey);
      }
      // 通知订阅方刷新（含本页 storeListener 重查详情）
      LedgerStore.notifyChanged();
    } catch (err) {
      Logger.error('重命名账本失败', (err as Error).message);
    }
  }

  deleteRecord(record: LedgerRecord): void {
    this.repository.deleteRecord(record.id)
      .then((): void => {
        // 通知订阅方刷新：本页重查记录列表，账本列表卡片重查汇总
        LedgerStore.notifyChanged();
      })
      .catch((err: Error): void => {
        Logger.error('删除账本记录失败', err.message);
      });
  }

  // 进入/退出批量管理模式
  toggleBatchMode(): void {
    this.batchMode = !this.batchMode;
    this.selectedIds = [];
  }

  // 用 checked 入参做幂等更新，避免“全选”时因 onChange 反复取反导致 AppFreeze
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

  toggleSelectAll(): void {
    if (this.selectedIds.length === this.recordList.length) {
      this.selectedIds = [];
    } else {
      this.selectedIds = this.recordList.map((record: LedgerRecord): string => record.id);
    }
  }

  // 批量删除前二次确认
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
        action: (): void => {
          this.batchDelete();
        }
      }
    });
  }

  async batchDelete(): Promise<void> {
    try {
      await this.repository.deleteRecords(this.selectedIds);
      this.selectedIds = [];
      this.batchMode = false;
      LedgerStore.notifyChanged();
    } catch (err) {
      Logger.error('批量删除账本记录失败', (err as Error).message);
      Toast.error($r('app.string.delete_failed'));
    }
  }

  // 点击记录进入编辑页（新增模式外的编辑模式，复用记一笔页）
  openEditRecord(record: LedgerRecord): void {
    const param: Record<string, Object> = { 'id': this.ledgerId, 'recordId': record.id };
    router.pushUrl({ url: 'pages/LedgerRecordEdit', params: param })
      .catch((err: BusinessError): void => {
        Logger.error('跳转记录编辑页失败', err.message);
      });
  }

  // 记录的分类名称：未选分类返回空串
  recordCategoryName(record: LedgerRecord): string {
    if (record.category === LEDGER_RECORD_NO_CATEGORY) {
      return '';
    }
    const accountType = record.type === LEDGER_RECORD_EXPENSE
      ? AccountType.EXPENSES : AccountType.INCOME;
    return CategoryStore.nameText(record.category, accountType);
  }

  // 删除前二次确认，避免误删
  confirmDeleteRecord(record: LedgerRecord): void {
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
        action: (): void => {
          this.deleteRecord(record);
        }
      }
    });
  }

  // 删除账本：账本与其中记录一并删除，需更强提示
  confirmDeleteLedger(): void {
    AlertDialog.show({
      title: $r('app.string.delete_confirm_title'),
      message: $r('app.string.ledger_delete_confirm'),
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
        action: (): void => {
          this.deleteLedger();
        }
      }
    });
  }

  async deleteLedger(): Promise<void> {
    try {
      // 先取消订阅再通知：避免本页收到通知后因账本已删而再次触发返回
      LedgerStore.unsubscribe(this.storeListener);
      await this.repository.deleteLedger(this.ledgerId);
      LedgerStore.notifyChanged();
      router.back();
    } catch (err) {
      Logger.error('删除账本失败', (err as Error).message);
    }
  }

  // 跳转账本内记一笔页（样式对齐正常记账）
  goAddRecord(): void {
    const param: Record<string, Object> = { 'id': this.ledgerId };
    router.pushUrl({ url: 'pages/LedgerRecordEdit', params: param })
      .catch((err: BusinessError): void => {
        Logger.error('跳转账本记一笔失败', err.message);
      });
  }

  // 跳转“从现有账单勾选导入”页
  goImportFromBills(): void {
    const param: Record<string, Object> = { 'id': this.ledgerId };
    router.pushUrl({ url: 'pages/LedgerBillPicker', params: param })
      .catch((err: BusinessError): void => {
        Logger.error('跳转账单导入页失败', err.message);
      });
  }

  // 跳转图片识别页：识别入账时同步复制进本账本
  goRecognize(): void {
    const param: Record<string, Object> = { 'ledgerId': this.ledgerId };
    router.pushUrl({ url: 'pages/RecognizeBill', params: param })
      .catch((err: BusinessError): void => {
        Logger.error('跳转图片识别页失败', err.message);
      });
  }

  // 记录行金额文案：支出 -，收入 +（对齐首页 AccountItem）
  recordAmountText(record: LedgerRecord): string {
    return (record.type === LEDGER_RECORD_EXPENSE ? '-' : '+') + record.amount.toFixed(2);
  }

  // 记录行备注：无备注时优先显示分类名，无分类按类型显示 支出/收入
  recordNoteText(record: LedgerRecord): string {
    if (record.note.length > 0) {
      return record.note;
    }
    const categoryName = this.recordCategoryName(record);
    if (categoryName.length > 0) {
      return categoryName;
    }
    return record.type === LEDGER_RECORD_EXPENSE ? '支出' : '收入';
  }

  @Builder HeaderBar() {
    Row({ space: SPACE_MEDIUM }) {
      Column() {
        Image($r('app.media.arrow_left'))
          .height(14)
          .objectFit(ImageFit.Contain)
          .fillColor(this.tk().textPrimary)
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.tk().surfaceVariant)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        router.back();
      })

      Text(this.ledgerName())
        .fontSize(this.fs(17))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tk().textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Text($r('app.string.ledger_rename'))
        .fontSize(this.fs(13))
        .fontColor(this.tk().primary)
        .onClick(() => {
          this.renameDialogController.open();
        })
      Text($r('app.string.delete'))
        .fontSize(this.fs(13))
        .fontColor(this.tk().danger)
        .onClick(() => {
          this.confirmDeleteLedger();
        })
    }
    .width('100%')
    .height(56)
  }

  @Builder SummaryCard() {
    Column({ space: SPACE_SMALL }) {
      Row({ space: SPACE_SMALL }) {
        Column() {
          Image($r('app.media.ledger'))
            .width(18)
            .height(18)
            .fillColor(ledgerAccent(this.tk(), this.ledgerColorKey()))
        }
        .width(30)
        .height(30)
        .borderRadius(15)
        .backgroundColor(this.tk().surface)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Text(this.ledgerName())
          .fontSize(this.fs(14))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().textPrimary)
          .layoutWeight(1)
        Text($r('app.string.ledger_record_count', this.recordList.length))
          .fontSize(this.fs(12))
          .fontColor(this.tk().textSecondary)
      }
      .width('100%')

      Text($r('app.string.ledger_balance_label'))
        .fontSize(this.fs(12))
        .fontColor(this.tk().textSecondary)
      Text(this.balanceText())
        .fontSize(this.fs(34))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.balance() >= 0 ? this.tk().textPrimary : this.tk().danger)
      Row({ space: SPACE_MEDIUM }) {
        Row({ space: SPACE_TINY }) {
          Text($r('app.string.expenditure'))
            .fontSize(this.fs(12))
            .fontColor(this.tk().textSecondary)
            .opacity(0.7)
          Text('-¥ ' + this.expenses.toFixed(2))
            .fontSize(this.fs(13))
            .fontColor(this.tk().textPrimary)
        }.alignItems(VerticalAlign.Center)
        Row({ space: SPACE_TINY }) {
          Text($r('app.string.income'))
            .fontSize(this.fs(12))
            .fontColor(this.tk().textSecondary)
            .opacity(0.7)
          Text('+¥ ' + this.income.toFixed(2))
            .fontSize(this.fs(13))
            .fontColor(this.tk().primary)
        }.alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(SPACE_LARGE)
    .borderRadius(RADIUS_CARD)
    .backgroundColor(ledgerAccentSoft(this.tk(), this.ledgerColorKey()))
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
  }

  @Builder RecordSwipeAction(record: LedgerRecord) {
    Row() {
      Button($r('app.string.delete'))
        .type(ButtonType.Normal)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.tk().danger)
        .onClick(() => {
          this.confirmDeleteRecord(record);
        })
    }
    .height('100%')
    .margin({ left: SPACE_MEDIUM })
  }

  @Builder RecordItem(record: LedgerRecord) {
    // 行样式对齐首页 AccountItem：圆形图标 + 两行文字 + 右侧金额，行高 56
    Row({ space: SPACE_MEDIUM }) {
      if (this.batchMode) {
        // 纯展示勾选态：不响应触摸，避免 Checkbox.onChange 与行 onClick 冒泡双取反导致勾不上
        Checkbox()
          .select(this.selectedIds.indexOf(record.id) >= 0)
          .hitTestBehavior(HitTestMode.None)
      }
      // 已选分类：分类图标 + 分类色；未选分类：账本图标 + 账本色
      if (record.category !== LEDGER_RECORD_NO_CATEGORY) {
        Column() {
          Image(this.recordCategoryIcon(record))
            .width(16)
            .objectFit(ImageFit.Contain)
            .fillColor(this.tk().surface)
        }.width(36)
        .height(36)
        .backgroundColor(this.recordCategoryColor(record))
        .borderRadius(RADIUS_ICON)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Image($r('app.media.ledger'))
            .width(16)
            .fillColor(this.tk().surface)
        }.width(36)
        .height(36)
        .backgroundColor(ledgerAccent(this.tk(), this.ledgerColorKey()))
        .borderRadius(RADIUS_ICON)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }

      Column({ space: SPACE_TINY }) {
        Text(this.recordNoteText(record))
          .fontColor(this.tk().textPrimary)
          .fontSize(this.fs(15))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(dayjs(record.time).format('YYYY-MM-DD HH:mm'))
          .fontSize(this.fs(12))
          .lineHeight(this.fs(14))
          .fontColor(this.tk().textSecondary)
      }.alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 支出深色、收入主题色，并带收支符号便于扫读
      Text(this.recordAmountText(record))
        .fontColor(record.type === LEDGER_RECORD_EXPENSE ? this.tk().textPrimary : this.tk().primary)
        .fontWeight(FontWeight.Medium)
        .fontSize(this.fs(16))
    }.width('100%')
    .height(56)
  }

  // 已选分类的图标与颜色（经 CategoryStore 反查，含被隐藏分类）
  recordCategoryIcon(record: LedgerRecord): ResourceStr {
    const accountType = record.type === LEDGER_RECORD_EXPENSE
      ? AccountType.EXPENSES : AccountType.INCOME;
    return CategoryStore.getById(record.category, accountType).icon;
  }

  recordCategoryColor(record: LedgerRecord): string {
    const accountType = record.type === LEDGER_RECORD_EXPENSE
      ? AccountType.EXPENSES : AccountType.INCOME;
    return CategoryStore.getById(record.category, accountType).activeColor;
  }

  @Builder BatchOperateBar() {
    Row({ space: SPACE_MEDIUM }) {
      Button(this.selectedIds.length === this.recordList.length
        ? $r('app.string.cancel_select_all') : $r('app.string.select_all'))
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

  @Builder EmptyView() {
    Column({ space: SPACE_MEDIUM }) {
      Image($r('app.media.empty'))
        .width(80)
        .objectFit(ImageFit.Contain)
      Text($r('app.string.ledger_record_empty'))
        .fontSize(this.fs(13))
        .lineHeight(this.fs(18))
        .fontColor(this.tk().textSecondary)
    }
    .width('100%')
    .margin({ top: 60 })
  }

  build() {
    Column({ space: SPACE_LARGE }) {
      this.HeaderBar()
      Scroll() {
        Column({ space: SPACE_LARGE }) {
          if (this.ledgerInfo !== null) {
            this.SummaryCard()
            if (this.recordList.length > 0) {
              // 批量管理入口：右对齐，进入后变为取消
              Row() {
                Blank()
                Text(this.batchMode ? $r('app.string.cancel') : $r('app.string.batch_manage'))
                  .fontSize(this.fs(13))
                  .fontColor(this.batchMode ? this.tk().danger : this.tk().primary)
                  .onClick(() => {
                    this.toggleBatchMode();
                  })
              }.width('100%')

              // 记录列表卡片：包裹样式与间距对齐首页
              List() {
                ForEach(this.recordList, (record: LedgerRecord) => {
                  ListItem() {
                    this.RecordItem(record)
                  }
                  .swipeAction({ end: this.RecordSwipeAction(record) })
                  .onClick(() => {
                    if (this.batchMode) {
                      // 批量模式：点击行即勾选/取消勾选
                      this.toggleSelect(record.id, !(this.selectedIds.indexOf(record.id) >= 0));
                    } else {
                      this.openEditRecord(record);
                    }
                  })
                }, (record: LedgerRecord): string => 'ledger_record_' + record.id + '_' + record.amount +
                  '_' + record.type + '_' + record.note + '_' + record.time + '_' + record.category +
                  '_' + (this.selectedIds.indexOf(record.id) >= 0 ? 1 : 0))
              }
              .width('100%')
              .divider({ strokeWidth: 1, color: this.tk().surfaceVariant })
              .backgroundColor(this.tk().surface)
              .borderRadius(RADIUS_CARD)
              .padding(SPACE_LARGE)
              .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
            } else if (this.loading) {
              Column({ space: SPACE_MEDIUM }) {
                LoadingProgress()
                  .width(36)
                  .height(36)
                  .color(this.tk().primary)
                Text($r('app.string.loading_tip'))
                  .fontSize(this.fs(13))
                  .fontColor(this.tk().textSecondary)
              }
              .width('100%')
              .margin({ top: 60 })
            } else {
              this.EmptyView()
            }

            if (this.batchMode && this.recordList.length > 0) {
              this.BatchOperateBar()
            } else {
              // 账单来源三入口：记一笔 / 从现有账单勾选导入 / 图片识别
              Row({ space: SPACE_SMALL }) {
                Button($r('app.string.ledger_record_add'))
                  .type(ButtonType.Normal)
                  .layoutWeight(1)
                  .height(44)
                  .borderRadius(22)
                  .padding({ left: SPACE_TINY, right: SPACE_TINY })
                  .backgroundColor(this.tk().primary)
                  .fontColor(this.tk().onPrimary)
                  .fontSize(this.fs(13))
                  .onClick(() => {
                    this.goAddRecord();
                  })
                Button($r('app.string.ledger_import_from_bills'))
                  .type(ButtonType.Normal)
                  .layoutWeight(1)
                  .height(44)
                  .borderRadius(22)
                  .padding({ left: SPACE_TINY, right: SPACE_TINY })
                  .backgroundColor(this.tk().surfaceVariant)
                  .fontColor(this.tk().textPrimary)
                  .fontSize(this.fs(13))
                  .onClick(() => {
                    this.goImportFromBills();
                  })
                Button($r('app.string.ledger_recognize'))
                  .type(ButtonType.Normal)
                  .layoutWeight(1)
                  .height(44)
                  .borderRadius(22)
                  .padding({ left: SPACE_TINY, right: SPACE_TINY })
                  .backgroundColor(this.tk().surfaceVariant)
                  .fontColor(this.tk().textPrimary)
                  .fontSize(this.fs(13))
                  .onClick(() => {
                    this.goRecognize();
                  })
              }
              .width('100%')
              .margin({ bottom: SPACE_LARGE })
            }
          }
        }
        .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
        .alignItems(HorizontalAlign.Start)
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING, bottom: SPACE_LARGE })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }
}
