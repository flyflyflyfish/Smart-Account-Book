import router from '@ohos.router';
import dayjs from 'dayjs';
import AccountNavigator from '../components/Navigator';
import RecurringBillService from '../service/RecurringBillService';
import { RecurringBill, RecurringRepeatMode } from '../models/recurring/RecurringBill';
import CategoryStore from '../models/accountType/CategoryStore';
import AccountTypeModel from '../models/accountType/AccountTypeModel';
import { AccountType } from '../models/account/account';
import { Toast } from '../components/ToastDialog';
import BreakpointConstants from '../common/breakpoint';
import {
  RADIUS_CARD,
  SPACE_LARGE,
  SPACE_MEDIUM,
  SPACE_SMALL,
  SPACE_TINY,
  SPACE_XLARGE
} from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';
import { AMOUNT_MAX } from '../utils/AmountGuard';

const AMOUNT_PATTERN: RegExp = /^\d+(\.\d{1,2})?$/;
// 分类区最多展示的行数：超出部分在 Grid 内部滚动
const MAX_CATEGORY_ROWS: number = 4;
// 每月模式可选日期范围 1-28 日
const MONTH_DAY_MIN: number = 1;
const MONTH_DAY_MAX: number = 31;

/**
 * 重复性账单编辑：设置金额、分类、重复频率（每天/周一至周五/每周/每月）、
 * 记入时刻与记入成功通知；经 AppStorage 传入规则则进入编辑模式
 */
@Entry
@Component
struct RecurringBillEdit {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  @State accountType: number = AccountType.EXPENSES;
  @State selectedCategoryId: number = -1;
  @State amountText: string = '';
  @State description: string = '';
  @State repeatMode: number = RecurringRepeatMode.EVERY_DAY;
  @State selectedWeekdays: number[] = [1];
  @State selectedMonthDays: number[] = [1];
  @State hour: number = 8;
  @State minute: number = 0;
  @State notifyOn: boolean = true;
  @State editId: string = '';
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  // 分类列表来自分类存储，支持用户自定义分类
  @State expenseTypeList: AccountTypeModel[] = CategoryStore.list(AccountType.EXPENSES);
  @State incomeTypeList: AccountTypeModel[] = CategoryStore.list(AccountType.INCOME);
  // 周 chips 展示顺序：周一至周六、周日
  private weekdayOrder: number[] = [1, 2, 3, 4, 5, 6, 0];
  // 每月可选日期：1~31（短月里选不到的日期自然跳过，如 2 月的 30/31）
  private monthDayOptions: number[] =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31];
  // 编辑时保留管理页上的规则开关状态，不在本页重复提供启停入口
  private enabledSaved: boolean = true;

  aboutToAppear(): void {
    const bill = AppStorage.get<RecurringBill>('recurringEditBill');
    if (bill) {
      this.editId = bill.id;
      this.accountType = bill.accountType;
      this.amountText = bill.amount.toFixed(2);
      this.description = bill.description;
      this.repeatMode = bill.repeatMode;
      this.selectedWeekdays = RecurringBill.sortWeekdays(bill.weekdays);
      this.selectedMonthDays = RecurringBill.sortMonthDays(bill.monthDays);
      this.hour = bill.hour;
      this.minute = bill.minute;
      this.notifyOn = bill.notify;
      this.enabledSaved = bill.enabled;
      this.selectedCategoryId = bill.type;
      AppStorage.delete('recurringEditBill');
    } else {
      const list = CategoryStore.list(this.accountType);
      this.selectedCategoryId = list.length > 0 ? list[0].id : -1;
    }
  }

  currentList(): AccountTypeModel[] {
    return this.accountType === AccountType.INCOME ? this.incomeTypeList : this.expenseTypeList;
  }

  switchAccountType(type: number): void {
    if (this.accountType === type) {
      return;
    }
    this.accountType = type;
    const list = this.currentList();
    this.selectedCategoryId = list.length > 0 ? list[0].id : -1;
  }

  // Grid 是滚动容器：高度按内容行数计算并设上限，分类多时在内部滚动
  categoryGridHeight(): number {
    const rows = Math.min(Math.ceil(this.currentList().length / 4), MAX_CATEGORY_ROWS);
    if (rows <= 0) {
      return 0;
    }
    return rows * 55 + (rows - 1) * 16;
  }

  timeText(): string {
    return dayjs().hour(this.hour).minute(this.minute).format('HH:mm');
  }

  showTimePicker(): void {
    this.getUIContext().showTimePickerDialog({
      selected: new Date(2020, 0, 1, this.hour, this.minute),
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        this.hour = value.hour;
        this.minute = value.minute;
      }
    });
  }

  // 多选切换星期，整组替换数组以保证状态刷新
  toggleWeekday(day: number): void {
    if (this.selectedWeekdays.indexOf(day) >= 0) {
      this.selectedWeekdays = this.selectedWeekdays.filter((item: number): boolean => item !== day);
    } else {
      this.selectedWeekdays = this.selectedWeekdays.concat([day]);
    }
  }

  // 多选切换每月日期
  toggleMonthDay(day: number): void {
    if (this.selectedMonthDays.indexOf(day) >= 0) {
      this.selectedMonthDays = this.selectedMonthDays.filter((item: number): boolean => item !== day);
    } else {
      this.selectedMonthDays = this.selectedMonthDays.concat([day]);
    }
  }

  async onSave(): Promise<void> {
    const text = this.amountText.trim();
    if (!AMOUNT_PATTERN.test(text) || Number(text) <= 0) {
      Toast.error($r('app.string.recurring_amount_invalid'));
      return;
    }
    if (Number(text) > AMOUNT_MAX) {
      Toast.error($r('app.string.amount_too_large'));
      return;
    }
    if (this.selectedCategoryId < 0) {
      Toast.error($r('app.string.require_amount_type'));
      return;
    }
    if (this.repeatMode === RecurringRepeatMode.WEEKLY && this.selectedWeekdays.length === 0) {
      Toast.error($r('app.string.recurring_weekly_empty'));
      return;
    }
    if (this.repeatMode === RecurringRepeatMode.MONTHLY && this.selectedMonthDays.length === 0) {
      Toast.error($r('app.string.recurring_monthly_empty'));
      return;
    }
    const bill = new RecurringBill();
    bill.type = this.selectedCategoryId;
    bill.accountType = this.accountType;
    bill.amount = Math.round(Number(text) * 100) / 100;
    bill.description = this.description.trim();
    bill.repeatMode = this.repeatMode;
    bill.weekdays = RecurringBill.sortWeekdays(this.selectedWeekdays);
    bill.monthDays = RecurringBill.sortMonthDays(this.selectedMonthDays);
    bill.hour = this.hour;
    bill.minute = this.minute;
    bill.notify = this.notifyOn;
    bill.enabled = this.enabledSaved;
    try {
      if (this.editId.length > 0) {
        bill.id = this.editId;
        await RecurringBillService.update(bill);
      } else {
        await RecurringBillService.add(bill);
      }
      Toast.success($r('app.string.save_success'));
      router.back();
    } catch (err) {
      Toast.error($r('app.string.save_failed'));
    }
  }

  @Builder SectionTitle(label: ResourceStr) {
    Text(label)
      .width('100%')
      .fontSize(this.fs(14))
      .fontWeight(FontWeight.Medium)
      .fontColor(this.tk().textPrimary)
  }

  @Builder TypeChip(label: ResourceStr, type: number) {
    Text(label)
      .fontSize(this.fs(14))
      .fontWeight(FontWeight.Medium)
      .fontColor(this.accountType === type ? this.tk().surface : this.tk().textPrimary)
      .textAlign(TextAlign.Center)
      .height(34)
      .layoutWeight(1)
      .backgroundColor(this.accountType === type ? this.tk().primary : this.tk().surfaceVariant)
      .borderRadius(17)
      .onClick(() => {
        this.switchAccountType(type);
      })
  }

  @Builder CategoryItem(item: AccountTypeModel) {
    Column({ space: 4 }) {
      Column() {
        Image(item.icon)
          .width(16)
          .objectFit(ImageFit.Contain)
          .fillColor(this.selectedCategoryId === item.id ? this.tk().surface : this.tk().textSecondary)
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.selectedCategoryId === item.id ? item.activeColor : this.tk().surfaceVariant)
      Text(item.name)
        .fontSize(this.fs(12))
        .fontColor(this.selectedCategoryId === item.id ? this.tk().textPrimary : this.tk().textSecondary)
        .lineHeight(this.fs(15))
    }
    .onClick(() => {
      this.selectedCategoryId = item.id;
    })
  }

  @Builder ModeChip(label: ResourceStr, mode: number) {
    Text(label)
      .fontSize(this.fs(13))
      .fontColor(this.repeatMode === mode ? this.tk().surface : this.tk().textPrimary)
      .textAlign(TextAlign.Center)
      .height(32)
      .layoutWeight(1)
      .backgroundColor(this.repeatMode === mode ? this.tk().primary : this.tk().surfaceVariant)
      .borderRadius(16)
      .onClick(() => {
        this.repeatMode = mode;
      })
  }

  @Builder WeekChip(day: number) {
    Text(this.weekdayLabel(day))
      .fontSize(this.fs(13))
      .fontColor(this.selectedWeekdays.indexOf(day) >= 0 ? this.tk().surface : this.tk().textPrimary)
      .textAlign(TextAlign.Center)
      .width(44)
      .height(32)
      .backgroundColor(this.selectedWeekdays.indexOf(day) >= 0 ? this.tk().primary : this.tk().surfaceVariant)
      .borderRadius(16)
      .onClick(() => {
        this.toggleWeekday(day);
      })
  }

  @Builder MonthDayChip(day: number) {
    Text(day.toString())
      .fontSize(this.fs(13))
      .fontColor(this.selectedMonthDays.indexOf(day) >= 0 ? this.tk().surface : this.tk().textPrimary)
      .textAlign(TextAlign.Center)
      .width(36)
      .height(30)
      .backgroundColor(this.selectedMonthDays.indexOf(day) >= 0 ? this.tk().primary : this.tk().surfaceVariant)
      .borderRadius(15)
      .onClick(() => {
        this.toggleMonthDay(day);
      })
  }

  // 周几文案，0=周日 ... 6=周六
  weekdayLabel(dayOfWeek: number): ResourceStr {
    switch (dayOfWeek) {
      case 0:
        return $r('app.string.recurring_weekday_0');
      case 1:
        return $r('app.string.recurring_weekday_1');
      case 2:
        return $r('app.string.recurring_weekday_2');
      case 3:
        return $r('app.string.recurring_weekday_3');
      case 4:
        return $r('app.string.recurring_weekday_4');
      case 5:
        return $r('app.string.recurring_weekday_5');
      default:
        return $r('app.string.recurring_weekday_6');
    }
  }

  build() {
    Column() {
      AccountNavigator({
        title: this.editId.length > 0 ? $r('app.string.recurring_bill_edit') : $r('app.string.recurring_bill_add')
      })
      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          Row({ space: SPACE_SMALL }) {
            this.TypeChip($r('app.string.expenditure'), AccountType.EXPENSES)
            this.TypeChip($r('app.string.income'), AccountType.INCOME)
          }
          .width('100%')

          Column({ space: SPACE_MEDIUM }) {
            this.SectionTitle($r('app.string.recurring_amount_label'))
            TextInput({ text: this.amountText, placeholder: $r('app.string.recurring_amount_placeholder') })
              .type(InputType.NUMBER_DECIMAL)
              .maxLength(10)
              .fontSize(this.fs(14))
              .fontColor(this.tk().textPrimary)
              .height(44)
              .backgroundColor(this.tk().surfaceVariant)
              .onChange((value: string) => {
                this.amountText = value;
              })
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          Column({ space: SPACE_MEDIUM }) {
            this.SectionTitle($r('app.string.recurring_category_label'))
            Grid() {
              ForEach(this.currentList(), (item: AccountTypeModel) => {
                GridItem() {
                  this.CategoryItem(item)
                }.width('100%')
                // key 带上收支侧前缀：两侧分类 id 均从 0 编号，仅用 id 切换收支时会残留旧分类
              }, (item: AccountTypeModel) => this.accountType + '_' + item.id.toString())
            }
            .columnsTemplate('1fr 1fr 1fr 1fr')
            .rowsGap(16)
            .width('100%')
            .height(this.categoryGridHeight())
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          Column({ space: SPACE_MEDIUM }) {
            this.SectionTitle($r('app.string.recurring_repeat_label'))
            Row({ space: SPACE_SMALL }) {
              this.ModeChip($r('app.string.recurring_repeat_every_day'), RecurringRepeatMode.EVERY_DAY)
              this.ModeChip($r('app.string.recurring_repeat_weekdays'), RecurringRepeatMode.WEEKDAYS)
              this.ModeChip($r('app.string.recurring_repeat_weekly'), RecurringRepeatMode.WEEKLY)
              this.ModeChip($r('app.string.recurring_repeat_monthly'), RecurringRepeatMode.MONTHLY)
            }
            .width('100%')

            if (this.repeatMode === RecurringRepeatMode.WEEKLY) {
              Text($r('app.string.recurring_weekly_hint'))
                .width('100%')
                .fontSize(this.fs(12))
                .fontColor(this.tk().textSecondary)
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.weekdayOrder, (day: number) => {
                  this.WeekChip(day)
                }, (day: number) => day.toString())
              }
              .width('100%')
            }

            if (this.repeatMode === RecurringRepeatMode.MONTHLY) {
              Text($r('app.string.recurring_monthly_hint'))
                .width('100%')
                .fontSize(this.fs(12))
                .fontColor(this.tk().textSecondary)
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.monthDayOptions, (day: number) => {
                  this.MonthDayChip(day)
                }, (day: number) => day.toString())
              }
              .width('100%')
            }

            Row() {
              Text($r('app.string.recurring_time_label'))
                .fontSize(this.fs(14))
                .fontColor(this.tk().textPrimary)
              Blank()
              Row({ space: SPACE_TINY }) {
                Text(this.timeText())
                  .fontSize(this.fs(14))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.tk().primary)
                Image($r('app.media.arrow_left'))
                  .width(12)
                  .objectFit(ImageFit.Contain)
                  .rotate({ angle: 180 })
                  .fillColor(this.tk().textSecondary)
              }
              .onClick(() => {
                this.showTimePicker();
              })
            }
            .width('100%')
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          Column({ space: SPACE_TINY }) {
            Row() {
              Text($r('app.string.recurring_notify_label'))
                .fontSize(this.fs(15))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.tk().textPrimary)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: $$this.notifyOn })
            }
            .width('100%')
            Text($r('app.string.recurring_notify_desc'))
              .width('100%')
              .fontSize(this.fs(12))
              .lineHeight(this.fs(17))
              .fontColor(this.tk().textSecondary)
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          Column({ space: SPACE_MEDIUM }) {
            this.SectionTitle($r('app.string.recurring_desc_label'))
            TextInput({ text: this.description, placeholder: $r('app.string.recurring_desc_placeholder') })
              .fontSize(this.fs(14))
              .fontColor(this.tk().textPrimary)
              .height(44)
              .backgroundColor(this.tk().surfaceVariant)
              .onChange((value: string) => {
                this.description = value;
              })
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          Button($r('app.string.save'))
            .width('100%')
            .height(44)
            .fontSize(this.fs(16))
            .backgroundColor(this.tk().primary)
            .fontColor(this.tk().surface)
            .type(ButtonType.Normal)
            .borderRadius(SPACE_SMALL)
            .margin({ top: SPACE_TINY, bottom: SPACE_LARGE })
            .onClick(() => {
              this.onSave();
            })
        }
        .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
        .padding({ left: SPACE_XLARGE, right: SPACE_XLARGE, top: SPACE_MEDIUM })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }
}
