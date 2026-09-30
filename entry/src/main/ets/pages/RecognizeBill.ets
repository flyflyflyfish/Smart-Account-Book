import router from '@ohos.router';
import dayjs from 'dayjs';
import cameraPicker from '@ohos.multimedia.cameraPicker';
import camera from '@ohos.multimedia.camera';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import AccountNavigator from '../components/Navigator';
import AccountTypeModel from '../models/accountType/AccountTypeModel';
import CategoryRegistry from '../models/accountType/CategoryRegistry';
import { AccountInfo, AccountType } from '../models/account/account';
import { RecognitionResult } from '../models/recognition/RecognitionResult';
import { RecognizerFactory } from '../service/recognition/RecognizerFactory';
import AccountService from '../service/account';
import { SOURCE_IMAGE } from '../common/constants';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import BreakpointConstants from '../common/breakpoint';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_XLARGE } from '../common/dimens';

// 识别流程步骤：选图 -> 识别中 -> 结果确认
const STEP_PICK: number = 0;
const STEP_RECOGNIZING: number = 1;
const STEP_CONFIRM: number = 2;

@Entry
@Component
struct RecognizeBill {
  @State step: number = STEP_PICK;
  @State imageUri: string = '';
  @State accountType: AccountType = AccountType.EXPENSES;
  @State amountText: string = '';
  @State merchant: string = '';
  @State selectedDate: number = dayjs().startOf('day').valueOf();
  // 识别出的支付时间（含时分），修改日期时保留时分
  @State payTime: number = Date.now();
  @State selectType: AccountTypeModel | undefined = undefined;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  // 从相册选择账单图片：走系统选择器，无需相册权限
  async pickFromGallery(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await picker.select(options);
      if (result.photoUris.length > 0) {
        this.startRecognize(result.photoUris[0]);
      }
    } catch (error) {
      Logger.error('选择图片失败', (error as Error).message);
      Toast.error($r('app.string.pick_image_failed'));
    }
  }

  // 拉起系统相机拍照：走系统选择器，无需相机权限
  async pickFromCamera(): Promise<void> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const result = await cameraPicker.pick(getContext(this), [cameraPicker.PickerMediaType.PHOTO], profile);
      // 用户取消时 resultCode 非 0，直接停留在本页
      if (result.resultCode === 0 && result.resultUri.length > 0) {
        this.startRecognize(result.resultUri);
      }
    } catch (error) {
      Logger.error('拍照失败', (error as Error).message);
      Toast.error($r('app.string.camera_failed'));
    }
  }

  // 调用识别器并处理结果：云端错误文案直接展示，其余回退通用提示
  async startRecognize(uri: string): Promise<void> {
    this.imageUri = uri;
    this.step = STEP_RECOGNIZING;
    try {
      const recognizer = await RecognizerFactory.create();
      const result = await recognizer.recognize(uri);
      if (!result.isBill) {
        Toast.error($r('app.string.not_a_bill'));
        this.step = STEP_PICK;
        return;
      }
      this.fillResult(result);
      this.step = STEP_CONFIRM;
    } catch (error) {
      const err = error as Error;
      Logger.error('识别账单失败', err.message);
      Toast.error(err.message ? err.message : $r('app.string.recognize_failed'));
      this.step = STEP_PICK;
    }
  }

  // 识别结果回填表单，等待用户确认修改
  fillResult(result: RecognitionResult): void {
    this.accountType = result.accountType;
    this.amountText = result.amount.toFixed(2);
    this.merchant = result.merchant;
    this.selectedDate = dayjs(result.payTime).startOf('day').valueOf();
    this.payTime = result.payTime;
    this.selectType = this.matchCategory(result.categoryName, result.accountType);
  }

  // 分类按名称映射到注册表，映射不到时回退到约定的最后一项“其他”
  matchCategory(name: string, accountType: AccountType): AccountTypeModel | undefined {
    const matched = CategoryRegistry.getByName(name, accountType);
    if (matched) {
      return matched;
    }
    const list = CategoryRegistry.list(accountType);
    return list[list.length - 1];
  }

  // 切换收支后原分类不再适用，回退到该侧的“其他”
  onAccountTypeChange(accountType: AccountType): void {
    if (accountType === this.accountType) {
      return;
    }
    this.accountType = accountType;
    this.selectType = this.matchCategory('', accountType);
  }

  showDatePicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-1-1'),
      end: new Date(),
      selected: new Date(this.selectedDate),
      onDateAccept: (value: Date) => {
        this.selectedDate = dayjs(value).startOf('day').valueOf();
        // 仅替换日期，保留识别出的时分
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

  // 确认入账：标记来源为图片识别，保存成功后由 BillStore 通知首页刷新
  async onConfirm(): Promise<void> {
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
      merchant: this.merchant,
      source: SOURCE_IMAGE,
      payTime: this.payTime
    };
    try {
      await AccountService.insert(info);
      Toast.success($r('app.string.save_success'));
      router.back();
    } catch (error) {
      Logger.error('保存识别账单失败', (error as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  // Grid 是滚动容器，必须显式给定高度
  getGridHeight(): number {
    const rows = Math.ceil(CategoryRegistry.list(this.accountType).length / 4);
    if (rows <= 0) {
      return 0;
    }
    return rows * 55 + (rows - 1) * 16;
  }

  @Builder PickPanel() {
    Column({ space: SPACE_MEDIUM }) {
      Text($r('app.string.recognize_entry_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.font_1'))
      Text($r('app.string.pick_tip'))
        .fontSize(13)
        .fontColor($r('app.color.font_2'))
        .textAlign(TextAlign.Center)
      Button($r('app.string.pick_from_camera'))
        .width('100%')
        .height(48)
        .fontSize(16)
        .backgroundColor($r('app.color.green'))
        .fontColor($r('app.color.white'))
        .type(ButtonType.Normal)
        .borderRadius(SPACE_SMALL)
        .margin({ top: SPACE_LARGE })
        .onClick(() => {
          this.pickFromCamera();
        })
      Button($r('app.string.pick_from_gallery'))
        .width('100%')
        .height(48)
        .fontSize(16)
        .backgroundColor($r('app.color.white'))
        .fontColor($r('app.color.font_3'))
        .type(ButtonType.Normal)
        .borderRadius(SPACE_SMALL)
        .onClick(() => {
          this.pickFromGallery();
        })
      // 识别引擎与云端接口配置入口
      Text($r('app.string.settings_entry'))
        .fontSize(14)
        .fontColor($r('app.color.green'))
        .margin({ top: SPACE_SMALL })
        .onClick(() => {
          router.pushUrl({ url: 'pages/Settings' }).catch((err: Error): void => {
            Logger.error('跳转设置页失败', err.message);
          });
        })
    }
    .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: SPACE_XLARGE, right: SPACE_XLARGE })
  }

  @Builder RecognizingPanel() {
    Column({ space: SPACE_MEDIUM }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color($r('app.color.green'))
      Text($r('app.string.recognizing'))
        .fontSize(15)
        .fontColor($r('app.color.font_1'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder ConfirmPanel() {
    Scroll() {
      Column({ space: SPACE_MEDIUM }) {
        Text($r('app.string.recognize_confirm_title'))
          .width('100%')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.font_1'))
        Image(this.imageUri)
          .width('100%')
          .height(160)
          .objectFit(ImageFit.Cover)
          .borderRadius(RADIUS_CARD)
          .backgroundColor($r('app.color.grey_1'))

        // 金额 / 商家 / 时间，全部可编辑
        Column() {
          Row() {
            Text($r('app.string.amount_label'))
              .width(64)
              .fontSize(14)
              .fontColor($r('app.color.font_3'))
            TextInput({ text: this.amountText, placeholder: $r('app.string.amount_placeholder') })
              .type(InputType.NUMBER_DECIMAL)
              .fontSize(16)
              .fontColor($r('app.color.font_3'))
              .textAlign(TextAlign.End)
              .layoutWeight(1)
              .backgroundColor($r('app.color.white'))
              .onChange((value: string) => {
                this.amountText = value;
              })
          }.width('100%').height(44)
          Divider().color($r('app.color.grey_1'))
          Row() {
            Text($r('app.string.merchant_label'))
              .width(64)
              .fontSize(14)
              .fontColor($r('app.color.font_3'))
            TextInput({ text: this.merchant, placeholder: $r('app.string.merchant_placeholder') })
              .fontSize(16)
              .fontColor($r('app.color.font_3'))
              .textAlign(TextAlign.End)
              .layoutWeight(1)
              .backgroundColor($r('app.color.white'))
              .onChange((value: string) => {
                this.merchant = value;
              })
          }.width('100%').height(44)
          Divider().color($r('app.color.grey_1'))
          Row({ space: SPACE_SMALL }) {
            Image($r('app.media.date'))
              .width(14)
              .objectFit(ImageFit.Contain)
            Text(dayjs(this.selectedDate).format('YYYY-MM-DD'))
              .fontSize(14)
              .fontColor($r('app.color.font_3'))
          }.width('100%').height(44)
          .onClick(() => {
            this.showDatePicker();
          })
        }
        .width('100%')
        .padding(SPACE_LARGE)
        .backgroundColor($r('app.color.white'))
        .borderRadius(RADIUS_CARD)

        // 收支切换
        Row({ space: SPACE_MEDIUM }) {
          Button($r('app.string.expenditure'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor(this.accountType === AccountType.EXPENSES ? $r('app.color.white') : $r('app.color.font_2'))
            .backgroundColor(this.accountType === AccountType.EXPENSES ? $r('app.color.green') : $r('app.color.white'))
            .type(ButtonType.Normal)
            .borderRadius(SPACE_SMALL)
            .onClick(() => {
              this.onAccountTypeChange(AccountType.EXPENSES);
            })
          Button($r('app.string.income'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor(this.accountType === AccountType.INCOME ? $r('app.color.white') : $r('app.color.font_2'))
            .backgroundColor(this.accountType === AccountType.INCOME ? $r('app.color.green') : $r('app.color.white'))
            .type(ButtonType.Normal)
            .borderRadius(SPACE_SMALL)
            .onClick(() => {
              this.onAccountTypeChange(AccountType.INCOME);
            })
        }.width('100%')

        // 分类选择
        Column() {
          Grid() {
            ForEach(CategoryRegistry.list(this.accountType), (item: AccountTypeModel) => {
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
        }
        .width('100%')
        .padding(SPACE_LARGE)
        .backgroundColor($r('app.color.white'))
        .borderRadius(RADIUS_CARD)

        Button($r('app.string.confirm_save'))
          .width('100%')
          .height(44)
          .fontSize(16)
          .backgroundColor($r('app.color.green'))
          .fontColor($r('app.color.white'))
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .margin({ bottom: SPACE_MEDIUM })
          .onClick(() => {
            this.onConfirm();
          })
      }
      .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
      .padding({ left: SPACE_XLARGE, right: SPACE_XLARGE, top: SPACE_MEDIUM })
    }
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .layoutWeight(1)
  }

  build() {
    Column() {
      AccountNavigator()
      if (this.step === STEP_PICK) {
        this.PickPanel()
      } else if (this.step === STEP_RECOGNIZING) {
        this.RecognizingPanel()
      } else {
        this.ConfirmPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }
}
