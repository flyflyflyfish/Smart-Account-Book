import dayjs from 'dayjs';
import router from '@ohos.router';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import AccountNavigator from '../components/Navigator';
import AccountService from '../service/account';
import BillImportService, { ImportedBill } from '../service/BillImportService';
import { AccountInfo, AccountType } from '../models/account/account';
import { SOURCE_IMPORT } from '../common/constants';
import BillStore from '../common/BillStore';
import DBUtil from '../utils/DBUtil';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

/**
 * 导入账单：选择支付宝/微信导出的账单文件（CSV/XLSX），
 * 解析后预览勾选，批量导入为记账记录
 */
@Entry
@Component
struct ImportBill {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  @State parsing: boolean = false;
  @State importing: boolean = false;
  @State fileName: string = '';
  @State sourceLabel: string = '';
  @State bills: ImportedBill[] = [];
  @State skippedCount: number = 0;
  @State incomeTotal: number = 0;
  @State expenseTotal: number = 0;
  @State dupCount: number = 0;
  @State selectedCount: number = 0;

  hasParsed(): boolean {
    return this.bills.length > 0 || this.skippedCount > 0;
  }

  // 拉起文件选择器：单选，按后缀过滤账单文件
  async pickFile(): Promise<void> {
    if (this.parsing) {
      return;
    }
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.csv', '.xlsx'];
      const documentPicker = new picker.DocumentViewPicker(getContext(this));
      const uris = await documentPicker.select(options);
      if (!uris || uris.length === 0) {
        return;
      }
      const uri = uris[0];
      // URI 末段即文件名，用于展示与格式校验
      const name = uri.substring(uri.lastIndexOf('/') + 1);
      if (!BillImportService.isSupportedFile(name)) {
        Toast.error($r('app.string.import_unsupported_file'));
        return;
      }
      this.fileName = decodeURIComponent(name);
      await this.doParse(uri);
    } catch (err) {
      Logger.error('选择账单文件失败', (err as Error).message);
      Toast.error($r('app.string.import_pick_failed'));
    }
  }

  // 解析账单文件：智能分类 + 与已有账单查重
  private async doParse(uri: string): Promise<void> {
    this.parsing = true;
    try {
      await DBUtil.ready;
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await BillImportService.parseFile(uri, context);
      this.bills = result.bills;
      this.sourceLabel = result.sourceLabel;
      this.skippedCount = result.skippedCount;
      this.incomeTotal = result.incomeTotal;
      this.expenseTotal = result.expenseTotal;
      let dup = 0;
      for (const bill of result.bills) {
        if (bill.duplicated) {
          dup++;
        }
      }
      this.dupCount = dup;
      this.refreshSelectedCount();
      if (result.bills.length === 0) {
        Toast.error($r('app.string.import_no_bills'));
      }
    } catch (err) {
      Logger.error('解析账单文件失败', (err as Error).message);
      this.bills = [];
      this.skippedCount = 0;
      Toast.error($r('app.string.import_parse_failed'));
    } finally {
      this.parsing = false;
    }
  }

  refreshSelectedCount(): void {
    let count = 0;
    for (const bill of this.bills) {
      if (bill.selected) {
        count++;
      }
    }
    this.selectedCount = count;
  }

  // 单笔勾选切换
  toggleBill(bill: ImportedBill): void {
    bill.selected = !bill.selected;
    this.bills = this.bills.slice();
    this.refreshSelectedCount();
  }

  // 全选/全不选
  toggleSelectAll(): void {
    const target = this.selectedCount < this.bills.length;
    for (const bill of this.bills) {
      bill.selected = target;
    }
    this.bills = this.bills.slice();
    this.refreshSelectedCount();
  }

  // 批量导入勾选的账单：静默插入后统一通知刷新
  async importBills(): Promise<void> {
    if (this.importing) {
      return;
    }
    if (this.selectedCount === 0) {
      Toast.error($r('app.string.import_none_selected'));
      return;
    }
    this.importing = true;
    try {
      await DBUtil.ready;
      let imported = 0;
      for (const bill of this.bills) {
        if (!bill.selected) {
          continue;
        }
        const info: AccountInfo = {
          accountType: bill.accountType,
          type: bill.categoryId,
          amount: bill.amount,
          time: dayjs(bill.payTime).startOf('day').valueOf(),
          merchant: bill.merchant,
          description: bill.description,
          source: SOURCE_IMPORT,
          payTime: bill.payTime
        };
        try {
          await AccountService.insertSilently(info);
          imported++;
        } catch (err) {
          Logger.error('导入单笔账单失败', (err as Error).message);
        }
      }
      if (imported > 0) {
        BillStore.notifyChanged();
        Toast.success($r('app.string.import_success', imported));
        router.back();
      } else {
        Toast.error($r('app.string.import_failed'));
      }
    } finally {
      this.importing = false;
    }
  }

  @Builder SectionCard(title: ResourceStr) {
    Text(title)
      .fontSize(this.fs(13))
      .fontColor(this.tk().textSecondary)
      .width('100%')
  }

  // 未选择文件时的引导卡片
  @Builder GuideCard() {
    Column({ space: SPACE_MEDIUM }) {
      Column({ space: SPACE_TINY }) {
        Text($r('app.string.import_supported_title'))
          .fontSize(this.fs(16))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().textPrimary)
        Text($r('app.string.import_supported_desc'))
          .fontSize(this.fs(12))
          .fontColor(this.tk().textSecondary)
      }
      .alignItems(HorizontalAlign.Center)
      .width('100%')

      Row({ space: SPACE_SMALL }) {
        Text($r('app.string.import_format_alipay'))
          .fontSize(this.fs(12))
          .fontColor(this.tk().primary)
          .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM, top: 6, bottom: 6 })
          .backgroundColor(this.tk().primarySoft)
          .borderRadius(SPACE_SMALL)
        Text($r('app.string.import_format_wechat'))
          .fontSize(this.fs(12))
          .fontColor(this.tk().primary)
          .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM, top: 6, bottom: 6 })
          .backgroundColor(this.tk().primarySoft)
          .borderRadius(SPACE_SMALL)
        Text($r('app.string.import_format_app'))
          .fontSize(this.fs(12))
          .fontColor(this.tk().primary)
          .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM, top: 6, bottom: 6 })
          .backgroundColor(this.tk().primarySoft)
          .borderRadius(SPACE_SMALL)
      }

      Text($r('app.string.import_privacy_tip'))
        .fontSize(this.fs(11))
        .fontColor(this.tk().textSecondary)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .padding(SPACE_LARGE)
    .backgroundColor(this.tk().surface)
    .borderRadius(RADIUS_CARD)
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
  }

  // 解析结果汇总卡片
  @Builder SummaryCard() {
    Column({ space: SPACE_MEDIUM }) {
      Row({ space: SPACE_SMALL }) {
        Text(this.sourceLabel)
          .fontSize(this.fs(13))
          .fontColor(this.tk().primary)
          .padding({ left: SPACE_SMALL, right: SPACE_SMALL, top: 3, bottom: 3 })
          .backgroundColor(this.tk().primarySoft)
          .borderRadius(SPACE_SMALL)
        Text(this.fileName)
          .fontSize(this.fs(12))
          .fontColor(this.tk().textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }.width('100%')

      Row() {
        Column({ space: SPACE_TINY }) {
          Text($r('app.string.export_total_expense'))
            .fontSize(this.fs(12))
            .fontColor(this.tk().textSecondary)
          Text('¥ ' + this.expenseTotal.toFixed(2))
            .fontSize(this.fs(18))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tk().danger)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        Column({ space: SPACE_TINY }) {
          Text($r('app.string.export_total_income'))
            .fontSize(this.fs(12))
            .fontColor(this.tk().textSecondary)
          Text('¥ ' + this.incomeTotal.toFixed(2))
            .fontSize(this.fs(18))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tk().primary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        Column({ space: SPACE_TINY }) {
          Text($r('app.string.import_total_count'))
            .fontSize(this.fs(12))
            .fontColor(this.tk().textSecondary)
          Text(this.bills.length.toString())
            .fontSize(this.fs(18))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tk().textPrimary)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }.width('100%')

      if (this.dupCount > 0 || this.skippedCount > 0) {
        Row({ space: SPACE_MEDIUM }) {
          if (this.dupCount > 0) {
            Text($r('app.string.import_dup_count', this.dupCount))
              .fontSize(this.fs(11))
              .fontColor(this.tk().warning)
          }
          if (this.skippedCount > 0) {
            Text($r('app.string.import_skipped_count', this.skippedCount))
              .fontSize(this.fs(11))
              .fontColor(this.tk().textSecondary)
          }
        }.width('100%')
      }
    }
    .width('100%')
    .padding(SPACE_LARGE)
    .backgroundColor(this.tk().surface)
    .borderRadius(RADIUS_CARD)
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
  }

  // 全选行
  @Builder SelectAllRow() {
    Row({ space: SPACE_SMALL }) {
      Checkbox()
        .select(this.selectedCount === this.bills.length && this.bills.length > 0)
        .onChange((checked: boolean) => {
          this.toggleSelectAll();
        })
      Text($r('app.string.import_select_all'))
        .fontSize(this.fs(14))
        .fontColor(this.tk().textPrimary)
      Text($r('app.string.import_selected_count', this.selectedCount))
        .fontSize(this.fs(12))
        .fontColor(this.tk().textSecondary)
        .layoutWeight(1)
      Text($r('app.string.import_repick'))
        .fontSize(this.fs(13))
        .fontColor(this.tk().primary)
        .onClick(() => {
          this.pickFile();
        })
    }
    .width('100%')
    .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM })
  }

  // 单笔账单卡片
  @Builder BillCard(bill: ImportedBill) {
    Column() {
      Row({ space: SPACE_SMALL }) {
        Checkbox()
          .select(bill.selected)
          .onChange((checked: boolean) => {
            this.toggleBill(bill);
          })
        Column({ space: SPACE_TINY }) {
          Row({ space: SPACE_SMALL }) {
            Text(bill.merchant)
              .fontSize(this.fs(14))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.tk().textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          Row({ space: SPACE_SMALL }) {
            Text(bill.accountType === AccountType.INCOME
              ? $r('app.string.import_direction_income') : $r('app.string.import_direction_expense'))
              .fontSize(this.fs(10))
              .fontColor(bill.accountType === AccountType.INCOME
                ? this.tk().primary : this.tk().danger)
              .padding({ left: SPACE_TINY, right: SPACE_TINY, top: 2, bottom: 2 })
              .borderRadius(4)
              .backgroundColor(bill.accountType === AccountType.INCOME
                ? this.tk().primarySoft : this.tk().dangerSoft)
            Text(bill.categoryName)
              .fontSize(this.fs(12))
              .fontColor(this.tk().textSecondary)
            Text(dayjs(bill.payTime).format('MM-DD HH:mm'))
              .fontSize(this.fs(12))
              .fontColor(this.tk().textSecondary)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .onClick(() => {
          this.toggleBill(bill);
        })

        Text('¥ ' + bill.amount.toFixed(2))
          .fontSize(this.fs(15))
          .fontWeight(FontWeight.Bold)
          .fontColor(bill.accountType === AccountType.INCOME ? this.tk().primary : this.tk().danger)
      }
      .width('100%')
      .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM, top: SPACE_SMALL, bottom: SPACE_SMALL })

      if (bill.duplicated) {
        Text($r('app.string.duplicated_tip'))
          .fontSize(this.fs(11))
          .fontColor(this.tk().warning)
          .width('100%')
          .padding({ left: SPACE_MEDIUM, bottom: SPACE_TINY })
      }
    }
    .width('100%')
    .backgroundColor(bill.duplicated ? this.tk().dangerSoft : this.tk().surface)
    .borderRadius(RADIUS_CARD)
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
  }

  build() {
    Stack() {
      Column() {
        AccountNavigator({ title: $r('app.string.import_bill_title') })
        Scroll() {
          Column({ space: SPACE_MEDIUM }) {
            if (!this.hasParsed()) {
              this.GuideCard()
            } else {
              this.SummaryCard()
              this.SelectAllRow()
              ForEach(this.bills, (bill: ImportedBill) => {
                this.BillCard(bill)
              }, (bill: ImportedBill) => 'bill_' + bill.uid + bill.selected)
            }
          }
          .width('100%')
          .padding({
            left: SPACE_LARGE, right: SPACE_LARGE,
            top: SPACE_LARGE, bottom: SPACE_LARGE
          })
        }
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .layoutWeight(1)

        // 底部操作区
        Column({ space: SPACE_SMALL }) {
          if (!this.hasParsed()) {
            Button($r('app.string.import_pick_file'))
              .width('100%')
              .height(48)
              .fontSize(this.fs(16))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.tk().surface)
              .backgroundColor(this.tk().primary)
              .type(ButtonType.Normal)
              .borderRadius(SPACE_SMALL)
              .enabled(!this.parsing)
              .opacity(this.parsing ? 0.6 : 1)
              .onClick(() => {
                this.pickFile();
              })
          } else {
            Button($r('app.string.import_do', this.selectedCount))
              .width('100%')
              .height(48)
              .fontSize(this.fs(16))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.tk().surface)
              .backgroundColor(this.tk().primary)
              .type(ButtonType.Normal)
              .borderRadius(SPACE_SMALL)
              .enabled(!this.importing && this.selectedCount > 0)
              .opacity(this.importing || this.selectedCount === 0 ? 0.6 : 1)
              .onClick(() => {
                this.importBills();
              })
          }
        }
        .width('100%')
        .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_MEDIUM, bottom: SPACE_LARGE })
        .backgroundColor(this.tk().surface)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.tk().background)

      // 解析中遮罩
      if (this.parsing) {
        Column({ space: SPACE_MEDIUM }) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.tk().primary)
          Text($r('app.string.import_parsing'))
            .fontSize(this.fs(14))
            .fontColor(this.tk().textPrimary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0, 0, 0, 0.2)')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }
}
