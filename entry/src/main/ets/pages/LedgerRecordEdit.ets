import router from '@ohos.router';
import dayjs from 'dayjs';
import AccountNavigator from '../components/Navigator';
import LedgerRepository from '../data/LedgerRepository';
import LedgerStore from '../common/LedgerStore';
import {
  LEDGER_RECORD_EXPENSE,
  LEDGER_RECORD_INCOME,
  LEDGER_RECORD_NO_CATEGORY
} from '../models/ledger/Ledger';
import AccountTypeModel from '../models/accountType/AccountTypeModel';
import CategoryStore from '../models/accountType/CategoryStore';
import { AccountInfo, AccountType } from '../models/account/account';
import AccountService from '../service/account';
import { PREF_LEDGER_SYNC_BILLS, SOURCE_MANUAL } from '../common/constants';
import PreferenceUtil from '../utils/PreferenceUtil';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import DBUtil from '../utils/DBUtil';
import BreakpointConstants from '../common/breakpoint';
import {
  RADIUS_CARD,
  SPACE_MEDIUM,
  SPACE_SMALL
} from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

/**
 * 账本内记一笔页路由参数：recordId 有值时为编辑模式
 */
interface LedgerRecordEditParams {
  id: string;
  recordId?: string;
}

// 数字键盘布局常量（与 AccountForm 保持一致）
const KEY_HEIGHT: number = 48;
const KEY_ROWS: number = 4;
const KEY_GAP: number = 8;
// 分类区最多展示的行数：超出部分在 Grid 内部滚动
const MAX_CATEGORY_ROWS: number = 4;

/**
 * 账本内记一笔/编辑：样式对齐正常记账（AddAccount / AccountForm），
 * 支出/收入大页签 + 分类网格 + 金额与自定义数字键盘 + 日期时间与备注行
 */
@Entry
@Component
struct LedgerRecordEdit {

  @StorageProp('themeSeq') themeSeq: number = 0;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  // 收支类型页签：0 支出 / 1 收入
  @State currentIndex: number = LEDGER_RECORD_EXPENSE;
  @State amountText: string = '';
  @State noteText: string = '';
  // 已选分类 id（-1 表示未选，可不选）
  @State selectedCategoryId: number = LEDGER_RECORD_NO_CATEGORY;
  // 记账日期与时间（精确到分）
  @State selectedDate: number = dayjs().startOf('day').valueOf();
  @State payTime: number = dayjs().second(0).millisecond(0).valueOf();
  // 数字键盘默认隐藏，点击金额行才弹出
  @State showKeyboard: boolean = false;
  // 新增模式下是否同步记入主账单（首页统计）；编辑模式只改账本记录，不显示该开关
  @State syncToBills: boolean = true;

  private ledgerId: string = '';
  // 编辑模式：待编辑记录 id，空串表示新增
  private editRecordId: string = '';
  private repository: LedgerRepository = new LedgerRepository();
  private keypadKeys: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '删'];

  isEditingRecord(): boolean {
    return this.editRecordId.length > 0;
  }

  aboutToAppear(): void {
    const params = router.getParams() as LedgerRecordEditParams | undefined;
    this.ledgerId = params && typeof params.id === 'string' ? params.id : '';
    const recordId = params?.recordId;
    if (typeof recordId === 'string' && recordId.length > 0) {
      this.editRecordId = recordId;
      this.loadRecord(recordId);
    } else {
      // 新增模式：同步开关初值读设置（设置页可配置，默认开）
      this.loadSyncDefault();
    }
  }

  // 读取“同步记入主账单”的默认开关；读取失败保持默认 true
  async loadSyncDefault(): Promise<void> {
    try {
      const value = await PreferenceUtil.getPreferenceValue(PREF_LEDGER_SYNC_BILLS, true);
      this.syncToBills = value === true;
    } catch (err) {
      Logger.error('读取账本同步默认设置失败', (err as Error).message);
    }
  }

  // 编辑模式：按 id 加载原记录并回填表单
  async loadRecord(recordId: string): Promise<void> {
    try {
      await DBUtil.ready;
      const record = await this.repository.queryRecordById(recordId);
      if (record === null) {
        return;
      }
      this.currentIndex = record.type === LEDGER_RECORD_INCOME ? LEDGER_RECORD_INCOME : LEDGER_RECORD_EXPENSE;
      this.amountText = record.amount.toFixed(2);
      this.noteText = record.note;
      this.selectedCategoryId = record.category;
      this.selectedDate = dayjs(record.time).startOf('day').valueOf();
      this.payTime = record.time;
    } catch (err) {
      Logger.error('加载账本记录失败', (err as Error).message);
    }
  }


  // 默认记账时间：所选日期叠加当前时分
  defaultPayTime(dateTime: number): number {
    const now = dayjs();
    return dayjs(dateTime)
      .hour(now.hour())
      .minute(now.minute())
      .second(0)
      .millisecond(0)
      .valueOf();
  }

  showDatePicker(): void {
    this.showKeyboard = false;
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-1-1'),
      end: new Date(),
      selected: new Date(this.selectedDate),
      onDateAccept: (value: Date) => {
        this.selectedDate = dayjs(value).startOf('day').valueOf();
        // 改日期保留已选时分
        const origin = dayjs(this.payTime);
        this.payTime = dayjs(this.selectedDate)
          .hour(origin.hour())
          .minute(origin.minute())
          .second(0)
          .millisecond(0)
          .valueOf();
      }
    });
  }

  showTimePicker(): void {
    this.showKeyboard = false;
    this.getUIContext().showTimePickerDialog({
      selected: new Date(this.payTime),
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        if (value.hour === undefined || value.minute === undefined) {
          return;
        }
        this.payTime = dayjs(this.selectedDate)
          .hour(value.hour)
          .minute(value.minute)
          .second(0)
          .millisecond(0)
          .valueOf();
      }
    });
  }

  // 自定义数字键盘输入：限制单个小数点、两位小数、整数位长度
  onKeyPress(key: string): void {
    const current = this.amountText;
    if (key === '删') {
      this.amountText = current.length > 0 ? current.substring(0, current.length - 1) : '';
      return;
    }
    if (key === '.') {
      if (current.includes('.')) {
        return;
      }
      this.amountText = current.length === 0 ? '0.' : current + '.';
      return;
    }
    const dotIndex = current.indexOf('.');
    if (dotIndex >= 0 && current.length - dotIndex > 2) {
      return;
    }
    if (dotIndex < 0 && current.length >= 7) {
      return;
    }
    // 避免 "00" 这类前导零
    this.amountText = current === '0' ? key : current + key;
  }

  // 校验金额：大于 0 且最多两位小数
  validateAmount(): boolean {
    const value = this.amountText;
    if (!value) {
      return false;
    }
    const amount = parseFloat(value);
    if (amount <= 0) {
      return false;
    }
    const regex = /^\d+(\.\d{1,2})?$/;
    return regex.test(value);
  }

  async onSave(): Promise<void> {
    this.showKeyboard = false;
    if (!this.validateAmount()) {
      Toast.error($r('app.string.ledger_amount_required'));
      return;
    }
    const recordType = this.currentIndex === LEDGER_RECORD_INCOME ? LEDGER_RECORD_INCOME : LEDGER_RECORD_EXPENSE;
    const amount = Math.round(parseFloat(this.amountText) * 100) / 100;
    const note = this.noteText.trim();
    try {
      const editing = this.isEditingRecord();
      // 新增且开关打开：先写主账单（首页统计）并取新账单 id 关联，账本记录据此防重复导入
      let billId = '';
      if (!editing && this.syncToBills) {
        const accountType = recordType === LEDGER_RECORD_INCOME ? AccountType.INCOME : AccountType.EXPENSES;
        const categoryId = this.selectedCategoryId === LEDGER_RECORD_NO_CATEGORY
          ? CategoryStore.getOther(accountType).id : this.selectedCategoryId;
        const info: AccountInfo = {
          accountType: accountType,
          type: categoryId,
          amount: amount,
          time: this.payTime,
          description: note,
          merchant: note,
          source: SOURCE_MANUAL,
          payTime: this.payTime
        };
        billId = await AccountService.insert(info);
      }
      if (editing) {
        await this.repository.updateRecord(this.editRecordId, recordType, amount,
          note, this.payTime, this.selectedCategoryId);
      } else {
        await this.repository.insertRecord(this.ledgerId, recordType, amount,
          note, this.payTime, this.selectedCategoryId, billId);
      }
      LedgerStore.notifyChanged();
      Toast.success($r('app.string.save_success'));
      router.back();
    } catch (err) {
      Logger.error('保存账本记录失败', (err as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  // 当前收支侧可选分类：支出/收入切换后跟随变化
  categoryList(): AccountTypeModel[] {
    return CategoryStore.list(this.currentIndex === LEDGER_RECORD_EXPENSE
      ? AccountType.EXPENSES : AccountType.INCOME);
  }

  getRows(): number {
    return Math.ceil(this.categoryList().length / 4);
  }

  // Grid 是滚动容器：高度按内容行数计算并设上限，分类多时在内部滚动
  getCategoryGridHeight(): number {
    const rows = Math.min(this.getRows(), MAX_CATEGORY_ROWS);
    if (rows <= 0) {
      return 0;
    }
    return rows * 55 + (rows - 1) * 16;
  }

  // 切换支出/收入页签：已选分类 id 在两侧含义不同（如 0 在支出侧是餐食、收入侧是工资），一律清空
  switchTab(index: number): void {
    if (this.currentIndex === index) {
      return;
    }
    this.currentIndex = index;
    this.showKeyboard = false;
    this.selectedCategoryId = LEDGER_RECORD_NO_CATEGORY;
  }

  resetForm(): void {
    this.amountText = '';
    this.noteText = '';
    this.selectedCategoryId = LEDGER_RECORD_NO_CATEGORY;
    this.selectedDate = dayjs().startOf('day').valueOf();
    this.payTime = this.defaultPayTime(this.selectedDate);
    this.showKeyboard = false;
  }

  getKeyboardHeight(): number {
    return KEY_ROWS * KEY_HEIGHT + (KEY_ROWS - 1) * KEY_GAP;
  }

  // 分类网格：样式对齐 AccountForm，可不选（保持“未分类”）
  @Builder CategoryGrid() {
    Grid() {
      ForEach(this.categoryList(), (item: AccountTypeModel) => {
        GridItem() {
          Column({ space: 4 }) {
            Column() {
              Image(item.icon)
                .width(16)
                .objectFit(ImageFit.Contain)
                .fillColor(this.selectedCategoryId === item.id ? this.tk().surface : this.tk().textSecondary)
            }.width(36)
            .height(36)
            .borderRadius(18)
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.selectedCategoryId === item.id
              ? item.activeColor : this.tk().surfaceVariant)
            Text(item.name).fontSize(this.fs(12))
              .fontColor(this.selectedCategoryId === item.id ? this.tk().textPrimary : this.tk().textSecondary)
              .lineHeight(this.fs(15))
          }.onClick(() => {
            // 再点一次取消选择，回到未分类
            this.selectedCategoryId = this.selectedCategoryId === item.id
              ? LEDGER_RECORD_NO_CATEGORY : item.id;
            this.showKeyboard = false;
          })
        }.width('100%')
      }, (item: AccountTypeModel) => this.currentIndex + '_' + item.id.toString())
    }
    .columnsTemplate('1fr 1fr 1fr 1fr')
    .rowsGap(16)
    .width('100%')
    .height(this.getCategoryGridHeight())
  }

  @Builder TabHeader(name: ResourceStr, index: number) {
    Column() {
      Text(name)
        .fontColor(this.currentIndex === index ? this.tk().textPrimary : this.tk().textSecondary)
        .fontSize(this.fs(18))
        .lineHeight(this.fs(20))
        .margin({ top: 17, bottom: 7 })
      Divider()
        .strokeWidth(2)
        .color(this.tk().textPrimary)
        .opacity(this.currentIndex === index ? 1 : 0)
    }.layoutWeight(1)
    .onClick(() => {
      this.switchTab(index);
    })
  }

  @Builder KeyButton(label: string) {
    Text(label)
      .fontSize(label === '删' ? 16 : 20)
      .fontColor(this.tk().textPrimary)
      .fontWeight(FontWeight.Medium)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(KEY_HEIGHT)
      .backgroundColor(this.tk().surface)
      .borderRadius(SPACE_SMALL)
      .onClick(() => {
        this.onKeyPress(label);
      })
  }

  @Builder KeyboardPanel() {
    Column({ space: KEY_GAP }) {
      Grid() {
        ForEach(this.keypadKeys, (key: string) => {
          GridItem() {
            this.KeyButton(key)
          }
        }, (key: string) => key)
      }.columnsTemplate('1fr 1fr 1fr')
      .columnsGap(KEY_GAP)
      .rowsGap(KEY_GAP)
      .width('100%')
      .height(this.getKeyboardHeight())
    }
    .width('100%')
    .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM, top: SPACE_MEDIUM, bottom: SPACE_MEDIUM })
    .backgroundColor(this.tk().background)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        AccountNavigator({ title: this.isEditingRecord() ? $r('app.string.edit') : $r('app.string.ledger_record_add') })
        Column() {
          // 支出 / 收入 大页签（对齐 AddAccount）
          Row() {
            this.TabHeader($r('app.string.expenditure'), LEDGER_RECORD_EXPENSE)
            this.TabHeader($r('app.string.income'), LEDGER_RECORD_INCOME)
          }.width('100%')

          // 表单卡：金额 + 日期时间行 + 备注行（对齐 AccountForm）
          Column() {
            Row() {
              Text($r('app.string.bill_amount'))
                .fontSize(this.fs(14))
                .fontColor(this.tk().textPrimary)
              Text(this.amountText.length ? '¥ ' + this.amountText : '¥ 0.00')
                .fontSize(this.fs(24))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.amountText.length ? this.tk().textPrimary : this.tk().textSecondary)
                .textAlign(TextAlign.End)
                .layoutWeight(1)
            }.width('100%')
            .height(40)
            .onClick(() => {
              this.showKeyboard = !this.showKeyboard;
            })

            Divider().color(this.tk().surfaceVariant)
              .margin({ top: 14, bottom: 14 })

            // 分类网格（对齐 AccountForm，可不选）
            this.CategoryGrid()

            Divider().color(this.tk().surfaceVariant)
              .margin({ top: 14, bottom: 4 })

            Row({ space: 20 }) {
              Row({ space: 4 }) {
                Image($r('app.media.date'))
                  .width(14)
                  .objectFit(ImageFit.Contain)
                Text(dayjs(this.selectedDate).format('YYYY-MM-DD'))
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().textPrimary)
                  .lineHeight(this.fs(17))
              }.onClick(() => {
                this.showDatePicker();
              })
              Row({ space: 4 }) {
                Image($r('app.media.date'))
                  .width(14)
                  .objectFit(ImageFit.Contain)
                Text(dayjs(this.payTime).format('HH:mm'))
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().textPrimary)
                  .lineHeight(this.fs(17))
              }.onClick(() => {
                this.showTimePicker();
              })
            }.height(40).padding({ left: 10 })

            // 备注：独立整行（对齐 AccountForm 加大样式，点击区域与字号一致）
            TextInput({ placeholder: $r('app.string.ledger_note_placeholder'), text: this.noteText })
              .placeholderColor(this.tk().textSecondary)
              .placeholderFont({ size: this.fs(14) })
              .fontSize(this.fs(14))
              .fontColor(this.tk().textPrimary)
              .width('100%')
              .height(46)
              .padding({ left: 12, right: 12 })
              .backgroundColor(this.tk().surface)
              .borderRadius(SPACE_SMALL)
              .maxLength(50)
              .onChange((val: string) => {
                this.noteText = val;
              })
              .onClick(() => {
                this.showKeyboard = false;
              })

            // 同步记入主账单开关：关闭时只进账本，不进首页统计（仅新增模式）
            if (!this.isEditingRecord()) {
              Divider().color(this.tk().surfaceVariant)
                .margin({ top: 14, bottom: 14 })

              Row() {
                Text($r('app.string.ledger_sync_to_bills'))
                  .fontSize(this.fs(13))
                  .fontColor(this.tk().textPrimary)
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.syncToBills })
                  .selectedColor(this.tk().primary)
                  .onChange((isOn: boolean) => {
                    this.syncToBills = isOn;
                    this.showKeyboard = false;
                  })
              }.width('100%')
            }
          }.width('100%')
          .padding(16)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          // 保存 / 清空
          Row({ space: SPACE_MEDIUM }) {
            Button($r('app.string.save'))
              .backgroundColor(this.tk().primary)
              .fontColor(this.tk().surface)
              .type(ButtonType.Normal)
              .borderRadius(4)
              .layoutWeight(1)
              .onClick(() => {
                this.onSave();
              })
            Button($r('app.string.clear'))
              .backgroundColor(this.tk().outline)
              .fontColor(this.tk().surface)
              .type(ButtonType.Normal)
              .borderRadius(4)
              .onClick(() => {
                this.resetForm();
              })
          }.width('100%')
          .margin({ top: SPACE_MEDIUM, bottom: SPACE_MEDIUM })
        }
        .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
        .padding({ left: 24, right: 24 })
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')

      // 键盘浮层：覆盖在底部，点键盘外任意处收起
      if (this.showKeyboard) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.showKeyboard = false;
            })
          this.KeyboardPanel()
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }
}
