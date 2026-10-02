import router from '@ohos.router';
import dayjs from 'dayjs';
import AccountNavigator from '../components/Navigator';
import RecurringBillService from '../service/RecurringBillService';
import { RecurringBill, RecurringRepeatMode } from '../models/recurring/RecurringBill';
import CategoryStore from '../models/accountType/CategoryStore';
import AccountTypeModel from '../models/accountType/AccountTypeModel';
import { AccountType } from '../models/account/account';
import BreakpointConstants from '../common/breakpoint';
import {
  RADIUS_CARD,
  SPACE_LARGE,
  SPACE_MEDIUM,
  SPACE_SMALL,
  SPACE_TINY,
  SPACE_XLARGE
} from '../common/dimens';

/**
 * 重复性账单管理：查看全部规则、启停/编辑/删除，点击新建进入编辑页
 */
@Entry
@Component
struct RecurringBillManage {
  @State bills: RecurringBill[] = [];
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  async aboutToAppear(): Promise<void> {
    await this.refresh();
  }

  async onPageShow(): Promise<void> {
    await this.refresh();
  }

  async refresh(): Promise<void> {
    this.bills = await RecurringBillService.loadAll();
  }

  resText(name: Resource): string {
    return getContext(this).resourceManager.getStringSync(name);
  }

  // 周几文案，0=周日 ... 6=周六
  weekdayLabel(dayOfWeek: number): Resource {
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

  // 重复规则摘要，如“周一至周五 08:00”、“每周一 08:00”、“每月3日 08:00”
  repeatText(bill: RecurringBill): string {
    const time = dayjs().hour(bill.hour).minute(bill.minute).format('HH:mm');
    switch (bill.repeatMode) {
      case RecurringRepeatMode.EVERY_DAY:
        return this.resText($r('app.string.recurring_repeat_every_day')) + ' ' + time;
      case RecurringRepeatMode.WEEKDAYS:
        return this.resText($r('app.string.recurring_repeat_weekdays')) + ' ' + time;
      case RecurringRepeatMode.WEEKLY: {
        const labels = RecurringBill.sortWeekdays(bill.weekdays)
          .map((day: number): string => this.resText(this.weekdayLabel(day)))
          .join('、');
        return this.resText($r('app.string.recurring_repeat_weekly')) + labels + ' ' + time;
      }
      case RecurringRepeatMode.MONTHLY: {
        const days = RecurringBill.sortMonthDays(bill.monthDays)
          .map((day: number): string => day.toString() + this.resText($r('app.string.recurring_day_suffix')))
          .join('、');
        return this.resText($r('app.string.recurring_repeat_monthly')) + days + ' ' + time;
      }
      default:
        return time;
    }
  }

  // 下次记入时间文案，停用时显示“已停用”
  nextText(bill: RecurringBill): string {
    if (!bill.enabled) {
      return this.resText($r('app.string.recurring_stopped'));
    }
    const next = RecurringBillService.nextOccurrence(bill, Date.now());
    if (next < 0) {
      return '';
    }
    return this.resText($r('app.string.recurring_next_label')) + ' ' + dayjs(next).format('YYYY-MM-DD HH:mm');
  }

  categoryIcon(bill: RecurringBill): ResourceStr {
    return CategoryStore.getById(bill.type, bill.accountType).icon;
  }

  categoryName(bill: RecurringBill): string {
    return CategoryStore.nameText(bill.type, bill.accountType);
  }

  isExpense(bill: RecurringBill): boolean {
    return bill.accountType !== AccountType.INCOME;
  }

  // 删除前二次确认
  confirmRemove(bill: RecurringBill): void {
    AlertDialog.show({
      title: $r('app.string.recurring_delete_title'),
      message: $r('app.string.recurring_delete_msg'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: $r('app.color.red'),
        action: (): void => {
          RecurringBillService.remove(bill.id).then((): void => {
            this.refresh();
          });
        }
      }
    });
  }

  goEdit(bill: RecurringBill | undefined): void {
    if (bill) {
      AppStorage.setOrCreate('recurringEditBill', bill);
    }
    router.pushUrl({ url: 'pages/RecurringBillEdit' });
  }

  @Builder BillCard(bill: RecurringBill) {
    Column({ space: SPACE_SMALL }) {
      Row({ space: SPACE_MEDIUM }) {
        Column() {
          Image(this.categoryIcon(bill))
            .width(20)
            .height(20)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.green'))
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.green_alpha'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column({ space: 2 }) {
          Row({ space: SPACE_SMALL }) {
            Text(this.categoryName(bill))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.font_3'))
            if (bill.description.length > 0) {
              Text(bill.description)
                .fontSize(12)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor($r('app.color.font_2'))
                .constraintSize({ maxWidth: 120 })
            }
          }
          Text(this.repeatText(bill))
            .fontSize(12)
            .fontColor($r('app.color.font_2'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: 2 }) {
          Text('¥ ' + bill.amount.toFixed(2))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isExpense(bill) ? $r('app.color.font_3') : $r('app.color.green'))
        }
        .alignItems(HorizontalAlign.End)

        Toggle({ type: ToggleType.Switch, isOn: bill.enabled })
          .onChange((isOn: boolean) => {
            RecurringBillService.setEnabled(bill.id, isOn).then((): void => {
              this.refresh();
            });
          })
      }
      .width('100%')

      Row({ space: SPACE_MEDIUM }) {
        Text(this.nextText(bill))
          .fontSize(12)
          .fontColor($r('app.color.font_2'))
          .layoutWeight(1)
        Text($r('app.string.delete'))
          .fontSize(12)
          .fontColor($r('app.color.red'))
          .onClick(() => {
            this.confirmRemove(bill);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(SPACE_LARGE)
    .backgroundColor($r('app.color.white'))
    .borderRadius(RADIUS_CARD)
    .onClick(() => {
      this.goEdit(bill);
    })
  }

  build() {
    Column() {
      AccountNavigator({ title: $r('app.string.recurring_bill_title') })
      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          Text($r('app.string.recurring_bill_hint'))
            .width('100%')
            .fontSize(12)
            .lineHeight(17)
            .fontColor($r('app.color.font_2'))
            .padding({ left: SPACE_TINY })

          if (this.bills.length === 0) {
            Column({ space: SPACE_SMALL }) {
              Text($r('app.string.recurring_bill_empty'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.font_3'))
              Text($r('app.string.recurring_bill_empty_hint'))
                .fontSize(12)
                .fontColor($r('app.color.font_2'))
            }
            .width('100%')
            .padding({ top: SPACE_XLARGE, bottom: SPACE_XLARGE })
            .alignItems(HorizontalAlign.Center)
          }

          ForEach(this.bills, (bill: RecurringBill) => {
            this.BillCard(bill)
          }, (bill: RecurringBill) => bill.id)

          Button($r('app.string.recurring_bill_add'))
            .width('100%')
            .height(44)
            .fontSize(16)
            .backgroundColor($r('app.color.green'))
            .fontColor($r('app.color.white'))
            .type(ButtonType.Normal)
            .borderRadius(SPACE_SMALL)
            .margin({ top: SPACE_TINY })
            .onClick(() => {
              this.goEdit(undefined);
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
    .backgroundColor($r('app.color.bg'))
  }
}
