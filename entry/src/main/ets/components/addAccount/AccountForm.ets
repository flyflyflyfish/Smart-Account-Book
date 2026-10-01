import AccountTypeModel from '../../models/accountType/AccountTypeModel';
import AccountService from '../../service/account';
import { AccountInfo, AccountType, ItemRecordInfo } from '../../models/account/account';
import { Toast } from '../ToastDialog';
import { Logger } from '../../utils/Logger';
import router from '@ohos.router';
import dayjs from 'dayjs';
import {
  RADIUS_CARD,
  SPACE_MEDIUM,
  SPACE_SMALL,
  SPACE_LARGE
} from '../../common/dimens';

// 数字键盘布局常量
const KEY_HEIGHT: number = 48;
const KEY_ROWS: number = 4;
const KEY_GAP: number = 8;

@Component
export default struct AccountForm {
  private accountTypeList: AccountTypeModel[] = [];
  private accountType: AccountType = AccountType.EXPENSES;
  // 编辑模式：由首页经 AddAccount 传入，仅当收支类型匹配本表单时生效
  editRecord: ItemRecordInfo | undefined = undefined;
  @State selectedDate: number = dayjs().startOf('day').valueOf();
  @State selectType: AccountTypeModel | undefined = undefined;
  @State amountText: string = '';
  @State description: string = '';
  // 数字键盘默认隐藏，点击金额行才弹出，避免挤压表单
  @State showKeyboard: boolean = false;
  private keypadKeys: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '删'];

  aboutToAppear(): void {
    const record = this.editRecord;
    if (record && record.accountType === this.accountType) {
      this.selectType = record.info;
      this.amountText = record.amount.toFixed(2);
      this.description = record.description ?? '';
      this.selectedDate = dayjs(record.time).startOf('day').valueOf();
    }
  }

  isEditing(): boolean {
    return !!this.editRecord && this.editRecord.accountType === this.accountType;
  }

  // 使用系统日期选择弹窗：自定义弹窗的 CustomDialogController 注入失败会导致闪退
  showDatePicker(): void {
    this.showKeyboard = false;
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-1-1'),
      end: new Date(),
      selected: new Date(this.selectedDate),
      onDateAccept: (value: Date) => {
        this.selectedDate = dayjs(value).startOf('day').valueOf();
      }
    });
  }

  // 自定义数字键盘输入：限制单个小数点、两位小数、整数位长度，避免系统键盘遮挡表单
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
    const selectType = this.selectType;
    if (!this.validateAmount() || !selectType) {
      Toast.error($r('app.string.require_amount_type'));
      return;
    }
    const info: AccountInfo = {
      accountType: this.accountType,
      type: selectType.id,
      amount: parseFloat(this.amountText),
      time: this.selectedDate,
      description: this.description
    };
    try {
      const record = this.editRecord;
      if (this.isEditing() && record) {
        // 编辑时保留原有的商家、来源、支付时间与创建时间
        info.merchant = record.merchant ?? '';
        info.source = record.source ?? 0;
        info.payTime = record.payTime ?? 0;
        info.createTime = record.createTime;
        await AccountService.update(record.id, info);
        Toast.success($r('app.string.save_success'));
        router.back();
      } else {
        await AccountService.insert(info);
        Toast.success($r('app.string.save_success'));
        this.resetAccountForm();
      }
    } catch (err) {
      Logger.error('保存记账记录失败', (err as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  resetAccountForm(): void {
    this.selectType = undefined;
    this.description = '';
    this.amountText = '';
    this.selectedDate = dayjs().startOf('day').valueOf();
    this.showKeyboard = false;
  }

  getRows(): number {
    return Math.ceil(this.accountTypeList.length / 4);
  }

  // Grid 是滚动容器，在高度 100% 的 Column 中会被拉满剩余空间，必须显式给定高度
  getGridHeight(): number {
    const rows = this.getRows();
    if (rows <= 0) {
      return 0;
    }
    return rows * 55 + (rows - 1) * 16;
  }

  getKeyboardHeight(): number {
    return KEY_ROWS * KEY_HEIGHT + (KEY_ROWS - 1) * KEY_GAP;
  }

  @Builder KeyButton(label: string) {
    Text(label)
      .fontSize(label === '删' ? 16 : 20)
      .fontColor($r('app.color.font_3'))
      .fontWeight(FontWeight.Medium)
      .textAlign(TextAlign.Center)
      .width('100%')
      .height(KEY_HEIGHT)
      .backgroundColor($r('app.color.white'))
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
      // 键盘内提供显式收起入口，不依赖再次点击金额行
      Button($r('app.string.confirm'))
        .width('100%')
        .height(40)
        .fontSize(15)
        .backgroundColor($r('app.color.green'))
        .fontColor($r('app.color.white'))
        .type(ButtonType.Normal)
        .borderRadius(SPACE_SMALL)
        .onClick(() => {
          this.showKeyboard = false;
        })
    }.margin({ top: SPACE_MEDIUM })
  }

  build() {
    // 键盘弹出时整体可滚动，避免按钮被挤出屏幕
    Scroll() {
      Column() {
        Column() {
          Row() {
            Text($r('app.string.bill_amount'))
              .fontSize(14)
              .fontColor($r('app.color.font_3'))
            Text(this.amountText.length ? '¥ ' + this.amountText : '¥ 0.00')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.amountText.length ? $r('app.color.font_3') : $r('app.color.font_2'))
              .textAlign(TextAlign.End)
              .layoutWeight(1)
          }.width('100%')
          .height(40)
          .onClick(() => {
            this.showKeyboard = !this.showKeyboard;
          })
          Divider().color($r('app.color.grey_1'))
            .margin({ top: 14, bottom: 14 })
          Grid() {
            ForEach(this.accountTypeList, (item: AccountTypeModel) => {
              GridItem() {
                Column({ space: 4 }) {
                  Column() {
                    Image(item.icon)
                      .width(16)
                      .objectFit(ImageFit.Contain)
                      .fillColor(this.selectType?.id === item.id ? $r('app.color.white') : $r('app.color.font_2'))
                  }.width(36)
                  .height(36)
                  .borderRadius(18)
                  .alignItems(HorizontalAlign.Center)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(this.selectType?.id === item.id ? item.activeColor : $r('app.color.grey_1'))
                  Text(item.name).fontSize(12)
                    .fontColor(this.selectType?.id === item.id ? $r('app.color.font_3') : $r('app.color.font_2'))
                    .lineHeight(15)
                }.onClick(() => {
                  this.selectType = item;
                })
              }.width('100%')
            }, (item: AccountTypeModel) => item.id.toString())
          }.columnsTemplate('1fr 1fr 1fr 1fr')
          .rowsGap(16)
          .width('100%')
          .height(this.getGridHeight())
          Divider().color($r('app.color.grey_1'))
            .margin({ top: 14, bottom: 4 })
          Row({ space: 20 }) {
            Row({ space: 4 }) {
              Image($r('app.media.date'))
                .width(14)
                .objectFit(ImageFit.Contain)
              Text(dayjs(this.selectedDate).format('YYYY-MM-DD'))
                .fontSize(12)
                .fontColor($r('app.color.font_3'))
                .lineHeight(17)
            }.onClick(() => {
              this.showDatePicker();
            })
            TextInput({ placeholder: $r('app.string.description_placeholder'), text: this.description })
              .placeholderColor($r('app.color.font_2'))
              .placeholderFont({ size: 12 })
              .fontSize(12)
              .layoutWeight(1)
              .backgroundColor($r('app.color.white'))
              .onChange((val: string) => {
                this.description = val;
              })
          }.height(40).padding({ left: 10 })
          Divider().color($r('app.color.grey_1'))
            .margin({ top: 4 })
        }.width('100%')
        .padding(SPACE_LARGE)
        .backgroundColor($r('app.color.white'))
        .borderRadius(RADIUS_CARD)

        if (this.showKeyboard) {
          this.KeyboardPanel()
        }

        Row({ space: SPACE_MEDIUM }) {
          Button($r('app.string.save'))
            .backgroundColor($r('app.color.green'))
            .fontColor($r('app.color.white'))
            .type(ButtonType.Normal)
            .borderRadius(4)
            .layoutWeight(1)
            .onClick(() => {
              this.onSave();
            })
          Button($r('app.string.clear'))
            .backgroundColor($r('app.color.grey_2'))
            .fontColor($r('app.color.white'))
            .type(ButtonType.Normal)
            .borderRadius(4)
            .onClick(() => {
              this.resetAccountForm();
            })
        }.width('100%')
        .margin({ top: SPACE_MEDIUM, bottom: SPACE_MEDIUM })
      }.width('100%')
    }
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .width('100%')
    .height('100%')
  }
}
