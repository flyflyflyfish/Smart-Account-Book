import dayjs from 'dayjs';
import AccountNavigator from '../components/Navigator';
import BudgetService from '../service/BudgetService';
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

const AMOUNT_PATTERN: RegExp = /^\d+(\.\d{1,2})?$/;

/**
 * 消费额度设置：自定义每月消费额度，超额后弹窗与通知提醒
 */
@Entry
@Component
struct BudgetSettings {
  @State budgetOn: boolean = false;
  @State amountText: string = '';
  @State monthExpenses: number = 0;
  @State savedLimit: number = 0;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  async aboutToAppear(): Promise<void> {
    const status = await BudgetService.loadStatus();
    this.budgetOn = status.enabled;
    this.savedLimit = status.limit;
    this.monthExpenses = status.monthExpenses;
    this.amountText = status.limit > 0 ? String(status.limit) : '';
  }

  // 预览时优先使用当前输入的合法额度，未输入或非法时回退到已保存额度
  effectiveLimit(): number {
    const text = this.amountText.trim();
    if (this.budgetOn && AMOUNT_PATTERN.test(text)) {
      return Math.round(Number(text) * 100) / 100;
    }
    return this.savedLimit;
  }

  isOver(): boolean {
    return this.budgetOn && this.effectiveLimit() > 0 && this.monthExpenses > this.effectiveLimit();
  }

  usagePercent(): number {
    const limit = this.effectiveLimit();
    if (limit <= 0) {
      return 0;
    }
    return Math.min(100, this.monthExpenses / limit * 100);
  }

  remainingAmount(): number {
    return this.effectiveLimit() - this.monthExpenses;
  }

  overAmount(): number {
    return this.monthExpenses - this.effectiveLimit();
  }

  progressColor(): ResourceColor {
    if (this.isOver()) {
      return $r('app.color.red');
    }
    if (this.usagePercent() >= 80) {
      return $r('app.color.orange');
    }
    return $r('app.color.green');
  }

  async onSave(): Promise<void> {
    if (this.budgetOn) {
      const text = this.amountText.trim();
      if (!AMOUNT_PATTERN.test(text) || Number(text) <= 0) {
        Toast.error($r('app.string.budget_amount_invalid'));
        return;
      }
      const amount = Math.round(Number(text) * 100) / 100;
      await BudgetService.saveSettings(true, amount);
    } else {
      await BudgetService.saveSettings(false, 0);
    }
    const status = await BudgetService.loadStatus();
    this.savedLimit = status.limit;
    this.monthExpenses = status.monthExpenses;
    Toast.success($r('app.string.settings_saved'));
  }

  @Builder SectionTitle(label: ResourceStr) {
    Text(label)
      .width('100%')
      .fontSize(14)
      .fontColor($r('app.color.font_3'))
      .margin({ bottom: SPACE_SMALL })
  }

  build() {
    Column() {
      AccountNavigator({ title: $r('app.string.budget_settings') })
      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          Column({ space: SPACE_TINY }) {
            Row({ space: SPACE_MEDIUM }) {
              Text($r('app.string.budget_enable_label'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.font_3'))
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: $$this.budgetOn })
            }.width('100%')
            Text($r('app.string.budget_hint'))
              .width('100%')
              .fontSize(12)
              .lineHeight(17)
              .fontColor($r('app.color.font_2'))
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor($r('app.color.white'))
          .borderRadius(RADIUS_CARD)

          if (this.budgetOn) {
            Column({ space: SPACE_MEDIUM }) {
              this.SectionTitle($r('app.string.budget_amount_label'))
              TextInput({ text: this.amountText, placeholder: $r('app.string.budget_amount_placeholder') })
                .type(InputType.NUMBER_DECIMAL)
                .fontSize(14)
                .fontColor($r('app.color.font_3'))
                .height(44)
                .backgroundColor($r('app.color.grey_1'))
                .onChange((value: string) => {
                  this.amountText = value;
                })

              Divider().color($r('app.color.grey_1'))

              Row() {
                Text($r('app.string.budget_month_spent_label') + '（' + dayjs().format('YYYY年M月') + '）')
                  .fontSize(13)
                  .fontColor($r('app.color.font_2'))
                Blank()
                Text('¥ ' + this.monthExpenses.toFixed(2))
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.isOver() ? $r('app.color.red') : $r('app.color.font_3'))
              }.width('100%')

              if (this.effectiveLimit() > 0) {
                Progress({ value: this.usagePercent(), total: 100, type: ProgressType.Linear })
                  .color(this.progressColor())
                  .height(8)
                  .borderRadius(4)
                  .animation({ duration: 400, curve: Curve.EaseOut })
                Row() {
                  Text($r('app.string.budget_usage_label',
                    this.monthExpenses.toFixed(2), this.effectiveLimit().toFixed(2)))
                    .fontSize(12)
                    .fontColor($r('app.color.font_2'))
                  Blank()
                  if (this.isOver()) {
                    Text($r('app.string.budget_over_row_label', this.overAmount().toFixed(2)))
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.red'))
                  } else {
                    Text($r('app.string.budget_remaining_label', this.remainingAmount().toFixed(2)))
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.usagePercent() >= 80 ? $r('app.color.orange') : $r('app.color.green'))
                  }
                }.width('100%')
              } else {
                Text($r('app.string.budget_no_limit_tip'))
                  .width('100%')
                  .fontSize(12)
                  .fontColor($r('app.color.font_2'))
              }
            }
            .width('100%')
            .padding(SPACE_LARGE)
            .backgroundColor($r('app.color.white'))
            .borderRadius(RADIUS_CARD)
          }

          Button($r('app.string.save'))
            .width('100%')
            .height(44)
            .fontSize(16)
            .backgroundColor($r('app.color.green'))
            .fontColor($r('app.color.white'))
            .type(ButtonType.Normal)
            .borderRadius(SPACE_SMALL)
            .margin({ top: SPACE_TINY })
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
    .backgroundColor($r('app.color.bg'))
  }
}
