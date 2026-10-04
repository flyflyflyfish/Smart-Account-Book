import dayjs from 'dayjs';
import { webview } from '@kit.ArkWeb';
import { picker, fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import AccountNavigator from '../components/Navigator';
import AccountService from '../service/account';
import DBUtil from '../utils/DBUtil';
import BillExportService, { ExportOptions } from '../service/BillExportService';
import AccountPO from '../models/account/accountPO';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

// 导出格式：0 Word 文档，1 PDF 文档
const FORMAT_WORD: number = 0;
const FORMAT_PDF: number = 1;

interface PresetOption {
  key: string;
  label: ResourceStr;
}

@Entry
@Component
struct ExportBill {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  @State startDate: number = dayjs().startOf('month').valueOf();
  @State endDate: number = dayjs().valueOf();
  @State activePreset: string = 'month';
  @State formatIndex: number = FORMAT_WORD;
  @State optSummary: boolean = true;
  @State optCategory: boolean = true;
  @State optDetail: boolean = true;
  @State optGroup: boolean = true;
  @State records: AccountPO[] = [];
  @State summaryExpenses: number = 0;
  @State summaryIncome: number = 0;
  @State summaryBalance: number = 0;
  @State summaryCount: number = 0;

  private presets: PresetOption[] = [
    { key: 'month', label: $r('app.string.export_range_month') },
    { key: 'last', label: $r('app.string.export_range_last') },
    { key: 'quarter', label: $r('app.string.export_range_quarter') },
    { key: 'year', label: $r('app.string.export_range_year') }
  ];

  // PDF 导出：可见 Web 组件承载账单 HTML，渲染完成后经 createPdf 生成 PDF
  private webController: webview.WebviewController = new webview.WebviewController();
  private pendingPdfAction: string = '';
  private pdfSrc: string = '';
  // 渲染等待定时器：关闭预览或离开页面时必须取消，否则会对已销毁的 Web 调 createPdf
  private pdfTimerId: number = -1;
  private pdfConfig: webview.PdfConfiguration = {
    width: 8.27,
    height: 11.69,
    marginTop: 0,
    marginBottom: 0,
    marginRight: 0,
    marginLeft: 0,
    shouldPrintBackground: true
  };
  @State pdfPreview: boolean = false;

  aboutToAppear(): void {
    this.loadRecords();
  }

  aboutToDisappear(): void {
    // 离开页面时取消未触发的 PDF 生成定时器
    this.cancelPdfTimer();
  }

  private cancelPdfTimer(): void {
    if (this.pdfTimerId >= 0) {
      clearTimeout(this.pdfTimerId);
      this.pdfTimerId = -1;
    }
  }

  // 将字节写入指定文件/URI 并确保关闭句柄：写失败时 fd 也不泄漏
  private writeBytesSync(pathOrUri: string, bytes: Uint8Array, mode: number): void {
    const file = fs.openSync(pathOrUri, mode);
    try {
      fs.writeSync(file.fd, bytes.buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  async loadRecords(): Promise<void> {
    try {
      // 等待数据库初始化完成，避免进程冷启动期间查询抛错导致汇总为 0
      await DBUtil.ready;
      const start = dayjs(this.startDate).startOf('day').valueOf();
      const end = dayjs(this.endDate).endOf('day').valueOf();
      const res = await AccountService.queryByDateRange(start, end);
      this.records = res;
      const summary = BillExportService.summarize(res);
      this.summaryExpenses = summary.expenses;
      this.summaryIncome = summary.income;
      this.summaryBalance = summary.balance;
      this.summaryCount = summary.count;
    } catch (err) {
      Logger.error('查询账单失败', (err as Error).message);
    }
  }

  applyPreset(preset: PresetOption): void {
    const now = dayjs();
    if (preset.key === 'month') {
      this.startDate = now.startOf('month').valueOf();
      this.endDate = now.valueOf();
    } else if (preset.key === 'last') {
      this.startDate = now.subtract(1, 'month').startOf('month').valueOf();
      this.endDate = now.subtract(1, 'month').endOf('month').valueOf();
    } else if (preset.key === 'quarter') {
      this.startDate = now.subtract(2, 'month').startOf('month').valueOf();
      this.endDate = now.valueOf();
    } else if (preset.key === 'year') {
      this.startDate = now.startOf('year').valueOf();
      this.endDate = now.valueOf();
    }
    this.activePreset = preset.key;
    this.loadRecords();
  }

  pickStartDate(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(2020, 0, 1),
      end: new Date(),
      selected: new Date(this.startDate),
      onDateAccept: (value: Date) => {
        this.startDate = dayjs(value).startOf('day').valueOf();
        if (this.startDate > this.endDate) {
          this.endDate = this.startDate;
        }
        this.activePreset = 'custom';
        this.loadRecords();
      }
    });
  }

  pickEndDate(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(2020, 0, 1),
      end: new Date(),
      selected: new Date(this.endDate),
      onDateAccept: (value: Date) => {
        this.endDate = dayjs(value).endOf('day').valueOf();
        if (this.endDate < this.startDate) {
          this.startDate = dayjs(value).startOf('day').valueOf();
        }
        this.activePreset = 'custom';
        this.loadRecords();
      }
    });
  }

  private fileName(ext: string): string {
    const s = dayjs(this.startDate).format('YYYYMMDD');
    const e = dayjs(this.endDate).format('YYYYMMDD');
    return `账单_${s}-${e}.${ext}`;
  }

  private exportOptions(): ExportOptions {
    return {
      includeSummary: this.optSummary,
      includeCategory: this.optCategory,
      includeDetail: this.optDetail,
      groupByDay: this.optGroup
    };
  }

  private hasContent(): boolean {
    return this.optSummary || this.optCategory || this.optDetail;
  }

  private buildHtml(forWord: boolean): string {
    return BillExportService.buildHtml(this.records, this.startDate, this.endDate, this.exportOptions(), forWord);
  }

  // Word 导出：生成 .docx（OOXML），经系统文件选择器保存
  async exportWord(): Promise<void> {
    if (this.records.length === 0) {
      Toast.error($r('app.string.export_empty'));
      return;
    }
    if (!this.hasContent()) {
      Toast.error($r('app.string.export_no_content'));
      return;
    }
    try {
      const docxBytes = BillExportService.buildDocx(this.records, this.startDate, this.endDate, this.exportOptions());
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [this.fileName('docx')];
      saveOptions.fileSuffixChoices = ['Word 文档|.docx'];
      const documentPicker = new picker.DocumentViewPicker(getContext(this));
      const uris = await documentPicker.save(saveOptions);
      if (!uris || uris.length === 0) {
        return;
      }
      this.writeBytesSync(uris[0], docxBytes, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      Toast.success($r('app.string.export_saved'));
    } catch (err) {
      Logger.error('导出 Word 账单失败', (err as Error).message);
      Toast.error($r('app.string.export_failed'));
    }
  }

  // PDF 导出：弹出全屏预览（可见 Web 才会被渲染），加载完成后自动生成 PDF 并保存
  exportPdf(): void {
    if (this.records.length === 0) {
      Toast.error($r('app.string.export_empty'));
      return;
    }
    if (!this.hasContent()) {
      Toast.error($r('app.string.export_no_content'));
      return;
    }
    this.preparePdf('save');
  }

  // 把账单 HTML 写入缓存文件，Web 组件用 src 直接加载（创建时加载，createPdf 才能捕获内容）
  private preparePdf(action: string): void {
    try {
      const html = this.buildHtml(false);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const path = `${context.cacheDir}/bill_preview.html`;
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, html);
      } finally {
        fs.closeSync(file);
      }
      this.pdfSrc = `file://${path}`;
      this.pendingPdfAction = action;
      this.pdfPreview = true;
    } catch (err) {
      this.pendingPdfAction = '';
      this.pdfPreview = false;
      Logger.error('载入账单 HTML 失败', (err as Error).message);
      Toast.error($r('app.string.export_failed'));
    }
  }

  // 页面加载完成后延迟生成 PDF（等待渲染完成），再按动作分发到保存或分享
  private generatePdf(): void {
    const action = this.pendingPdfAction;
    this.pendingPdfAction = '';
    this.cancelPdfTimer();
    this.pdfTimerId = setTimeout(() => {
      this.pdfTimerId = -1;
      this.doGeneratePdf(action);
    }, 500);
  }

  private async doGeneratePdf(action: string): Promise<void> {
    // 用户已关闭预览（Web 已销毁）时直接放弃，避免对已销毁组件调用抛错
    if (!this.pdfPreview) {
      return;
    }
    try {
      this.webController.onActive();
      const pdfData = await this.webController.createPdf(this.pdfConfig);
      const bytes = pdfData.pdfArrayBuffer();
      this.pdfPreview = false;
      if (action === 'save') {
        await this.savePdfBytes(bytes);
      } else if (action === 'share') {
        await this.sharePdfBytes(bytes);
      }
    } catch (err) {
      this.pdfPreview = false;
      Logger.error('生成 PDF 失败', (err as Error).message);
      Toast.error($r('app.string.export_failed'));
    }
  }

  private async savePdfBytes(bytes: Uint8Array): Promise<void> {
    const saveOptions = new picker.DocumentSaveOptions();
    saveOptions.newFileNames = [this.fileName('pdf')];
    saveOptions.fileSuffixChoices = ['PDF 文档|.pdf'];
    const documentPicker = new picker.DocumentViewPicker(getContext(this));
    const uris = await documentPicker.save(saveOptions);
    if (!uris || uris.length === 0) {
      return;
    }
    this.writeBytesSync(uris[0], bytes, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    Toast.success($r('app.string.export_saved'));
  }

  private async sharePdfBytes(bytes: Uint8Array): Promise<void> {
    const name = this.fileName('pdf');
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const path = `${context.cacheDir}/${name}`;
    this.writeBytesSync(path, bytes, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    const utdTypeId = utd.getUniformDataTypeByFilenameExtension('.pdf', utd.UniformDataType.PDF);
    const shareData = new systemShare.SharedData({
      utd: utdTypeId,
      uri: fileUri.getUriFromPath(path),
      title: name
    });
    const controller = new systemShare.ShareController(shareData);
    await controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DETAIL,
      selectionMode: systemShare.SelectionMode.SINGLE
    });
  }

  // 分享：按所选格式分享（Word 为 .docx，PDF 经 createPdf 生成后分享）
  async shareBill(): Promise<void> {
    if (this.records.length === 0) {
      Toast.error($r('app.string.export_empty'));
      return;
    }
    if (!this.hasContent()) {
      Toast.error($r('app.string.export_no_content'));
      return;
    }
    if (this.formatIndex === FORMAT_PDF) {
      this.preparePdf('share');
      return;
    }
    try {
      const docxBytes = BillExportService.buildDocx(this.records, this.startDate, this.endDate, this.exportOptions());
      const name = this.fileName('docx');
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const path = `${context.cacheDir}/${name}`;
      this.writeBytesSync(path, docxBytes, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const utdTypeId = utd.getUniformDataTypeByFilenameExtension('.docx', utd.UniformDataType.WORDPROCESSINGML_DOCUMENT);
      const shareData = new systemShare.SharedData({
        utd: utdTypeId,
        uri: fileUri.getUriFromPath(path),
        title: name
      });
      const controller = new systemShare.ShareController(shareData);
      await controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
    } catch (err) {
      Logger.error('分享账单失败', (err as Error).message);
      Toast.error($r('app.string.export_share_failed'));
    }
  }

  onExport(): void {
    if (this.formatIndex === FORMAT_PDF) {
      this.exportPdf();
    } else {
      this.exportWord();
    }
  }

  private fmtDate(t: number): string {
    return dayjs(t).format('YYYY-MM-DD');
  }

  @Builder PresetChips() {
    Row({ space: SPACE_SMALL }) {
      ForEach(this.presets, (item: PresetOption) => {
        Text(item.label)
          .fontSize(this.fs(13))
          .fontColor(this.activePreset === item.key ? this.tk().surface : this.tk().textPrimary)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor(this.activePreset === item.key ? this.tk().primary : this.tk().surfaceVariant)
          .borderRadius(18)
          .onClick(() => {
            this.applyPreset(item);
          })
      })
    }.width('100%')
  }

  @Builder DateRow() {
    Row({ space: SPACE_SMALL }) {
      Row({ space: SPACE_TINY }) {
        Text(this.fmtDate(this.startDate))
          .fontSize(this.fs(15))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().textPrimary)
        Image($r('app.media.arrow_down'))
          .width(12)
          .objectFit(ImageFit.Contain)
          .fillColor(this.tk().textSecondary)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .padding(SPACE_MEDIUM)
      .backgroundColor(this.tk().background)
      .borderRadius(SPACE_SMALL)
      .onClick(() => {
        this.pickStartDate();
      })

      Text('~')
        .fontSize(this.fs(14))
        .fontColor(this.tk().textSecondary)

      Row({ space: SPACE_TINY }) {
        Text(this.fmtDate(this.endDate))
          .fontSize(this.fs(15))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().textPrimary)
        Image($r('app.media.arrow_down'))
          .width(12)
          .objectFit(ImageFit.Contain)
          .fillColor(this.tk().textSecondary)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .padding(SPACE_MEDIUM)
      .backgroundColor(this.tk().background)
      .borderRadius(SPACE_SMALL)
      .onClick(() => {
        this.pickEndDate();
      })
    }.width('100%')
  }

  @Builder FormatOption(index: number, icon: ResourceStr, label: ResourceStr, desc: ResourceStr) {
    Row({ space: SPACE_SMALL }) {
      Column() {
        Image(icon)
          .width(22)
          .height(22)
          .fillColor(this.formatIndex === index ? this.tk().primary : this.tk().textSecondary)
      }
      .width(44)
      .height(44)
      .borderRadius(12)
      .backgroundColor(this.formatIndex === index ? this.tk().primarySoft : this.tk().surfaceVariant)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      Column({ space: 2 }) {
        Text(label)
          .fontSize(this.fs(15))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.formatIndex === index ? this.tk().textPrimary : this.tk().textPrimary)
        Text(desc)
          .fontSize(this.fs(12))
          .fontColor(this.tk().textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.formatIndex === index) {
        Text('✓')
          .fontSize(this.fs(16))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tk().primary)
      }
    }
    .width('100%')
    .padding(SPACE_MEDIUM)
    .borderRadius(SPACE_SMALL)
    .border({
      width: 1.5,
      color: this.formatIndex === index ? this.tk().primary : this.tk().surfaceVariant
    })
    .backgroundColor(this.tk().surface)
    .onClick(() => {
      this.formatIndex = index;
    })
  }

  @Builder OptionRow(label: ResourceStr, desc: ResourceStr, isOn: boolean, onToggle: (v: boolean) => void) {
    Row({ space: SPACE_MEDIUM }) {
      Column({ space: 2 }) {
        Text(label)
          .fontSize(this.fs(15))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().textPrimary)
        Text(desc)
          .fontSize(this.fs(12))
          .fontColor(this.tk().textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(this.tk().primary)
        .onChange((value: boolean) => {
          onToggle(value);
        })
    }
    .width('100%')
    .padding({ top: SPACE_SMALL, bottom: SPACE_SMALL })
  }

  @Builder SectionCard(title: ResourceStr) {
    Text(title)
      .fontSize(this.fs(13))
      .fontColor(this.tk().textSecondary)
      .width('100%')
  }

  build() {
    Stack() {
      Column() {
        AccountNavigator({ title: $r('app.string.export_bill_title') })
      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          // 时间跨度
          Column({ space: SPACE_MEDIUM }) {
            this.SectionCard($r('app.string.export_range_label'))
            this.PresetChips()
            this.DateRow()
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          // 导出格式
          Column({ space: SPACE_MEDIUM }) {
            this.SectionCard($r('app.string.export_format_label'))
            this.FormatOption(FORMAT_WORD, $r('app.media.settings'), $r('app.string.export_format_word'),
              $r('app.string.export_format_word_desc'))
            this.FormatOption(FORMAT_PDF, $r('app.media.ai'), $r('app.string.export_format_pdf'),
              $r('app.string.export_format_pdf_desc'))
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          // 导出内容
          Column({ space: SPACE_MEDIUM }) {
            this.SectionCard($r('app.string.export_content_label'))
            this.OptionRow($r('app.string.export_opt_summary'), $r('app.string.export_opt_summary_desc'),
              this.optSummary, (v: boolean) => {
                this.optSummary = v;
              })
            this.OptionRow($r('app.string.export_opt_category'), $r('app.string.export_opt_category_desc'),
              this.optCategory, (v: boolean) => {
                this.optCategory = v;
              })
            this.OptionRow($r('app.string.export_opt_detail'), $r('app.string.export_opt_detail_desc'),
              this.optDetail, (v: boolean) => {
                this.optDetail = v;
              })
            if (this.optDetail) {
              this.OptionRow($r('app.string.export_opt_group'), $r('app.string.export_opt_group_desc'),
                this.optGroup, (v: boolean) => {
                  this.optGroup = v;
                })
            }
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          // 汇总预览
          Column({ space: SPACE_MEDIUM }) {
            this.SectionCard($r('app.string.export_summary_label'))
            Row() {
              Column({ space: SPACE_TINY }) {
                Text($r('app.string.export_total_expense'))
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().textSecondary)
                Text('¥ ' + this.summaryExpenses.toFixed(2))
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
                Text('¥ ' + this.summaryIncome.toFixed(2))
                  .fontSize(this.fs(18))
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.tk().primary)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Center)
              Column({ space: SPACE_TINY }) {
                Text($r('app.string.export_balance'))
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().textSecondary)
                Text('¥ ' + this.summaryBalance.toFixed(2))
                  .fontSize(this.fs(18))
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.tk().textPrimary)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Center)
            }.width('100%')
            Row() {
              Text($r('app.string.export_total_count', this.summaryCount))
                .fontSize(this.fs(12))
                .fontColor(this.tk().textSecondary)
            }.width('100%')
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          if (this.formatIndex === FORMAT_PDF) {
            Text($r('app.string.export_pdf_hint'))
              .fontSize(this.fs(12))
              .fontColor(this.tk().textSecondary)
              .width('100%')
          }
        }
        .width('100%')
        .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_LARGE, bottom: SPACE_LARGE })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .layoutWeight(1)

      // 底部操作区
      Column({ space: SPACE_SMALL }) {
        Button($r('app.string.export_do'))
          .width('100%')
          .height(48)
          .fontSize(this.fs(16))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().surface)
          .backgroundColor(this.tk().primary)
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .onClick(() => {
            this.onExport();
          })
        Button($r('app.string.export_share'))
          .width('100%')
          .height(44)
          .fontSize(this.fs(15))
          .fontColor(this.tk().primary)
          .backgroundColor(this.tk().primarySoft)
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .onClick(() => {
            this.shareBill();
          })
      }
      .width('100%')
      .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_MEDIUM, bottom: SPACE_LARGE })
      .backgroundColor(this.tk().surface)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.tk().background)

      // PDF 全屏预览：可见 Web 承载账单 HTML，加载完成后自动调起打印
      if (this.pdfPreview) {
        Column() {
          Row() {
            Text($r('app.string.export_preview_title'))
              .fontSize(this.fs(16))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.tk().textPrimary)
              .layoutWeight(1)
            Text($r('app.string.export_preview_close'))
              .fontSize(this.fs(14))
              .fontColor(this.tk().textSecondary)
              .padding({ left: SPACE_MEDIUM, right: SPACE_LARGE, top: SPACE_SMALL, bottom: SPACE_SMALL })
               .onClick(() => {
                this.pendingPdfAction = '';
                this.pdfPreview = false;
                // 取消未触发的生成定时器，真正停止本次导出
                this.cancelPdfTimer();
              })
          }
          .width('100%')
          .padding({ top: SPACE_MEDIUM, bottom: SPACE_SMALL })

          Web({ src: this.pdfSrc, controller: this.webController, renderMode: RenderMode.SYNC_RENDER })
            .width('100%')
            .layoutWeight(1)
            .fileAccess(true)
            .javaScriptAccess(true)
            .onPageEnd(() => {
              if (this.pendingPdfAction !== '') {
                this.generatePdf();
              }
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.tk().surface)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }
}
