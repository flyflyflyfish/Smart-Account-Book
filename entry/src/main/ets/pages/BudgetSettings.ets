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
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

const AMOUNT_PATTERN: RegExp = /^\d+(\.\d{1,2})?$/;

/**
 * 消费额度设置：自定义每月消费额度，超额后弹窗与通知提醒
 */
@Entry
@Component
struct BudgetSettings {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

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
      return this.tk().danger;
    }
    if (this.usagePercent() >= 80) {
      return this.tk().warning;
    }
    return this.tk().primary;
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
      .fontSize(this.fs(14))
      .fontColor(this.tk().textPrimary)
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
                .fontSize(this.fs(15))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.tk().textPrimary)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: $$this.budgetOn })
            }.width('100%')
            Text($r('app.string.budget_hint'))
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

          if (this.budgetOn) {
            Column({ space: SPACE_MEDIUM }) {
              this.SectionTitle($r('app.string.budget_amount_label'))
              TextInput({ text: this.amountText, placeholder: $r('app.string.budget_amount_placeholder') })
                .type(InputType.NUMBER_DECIMAL)
                .fontSize(this.fs(14))
                .fontColor(this.tk().textPrimary)
                .height(44)
                .backgroundColor(this.tk().surfaceVariant)
                .onChange((value: string) => {
                  this.amountText = value;
                })

              Divider().color(this.tk().surfaceVariant)

              Row() {
                Text($r('app.string.budget_month_spent_label') + '（' + dayjs().format('YYYY年M月') + '）')
                  .fontSize(this.fs(13))
                  .fontColor(this.tk().textSecondary)
                Blank()
                Text('¥ ' + this.monthExpenses.toFixed(2))
                  .fontSize(this.fs(15))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.isOver() ? this.tk().danger : this.tk().textPrimary)
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
                    .fontSize(this.fs(12))
                    .fontColor(this.tk().textSecondary)
                  Blank()
                  if (this.isOver()) {
                    Text($r('app.string.budget_over_row_label', this.overAmount().toFixed(2)))
                      .fontSize(this.fs(12))
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.tk().danger)
                  } else {
                    Text($r('app.string.budget_remaining_label', this.remainingAmount().toFixed(2)))
                      .fontSize(this.fs(12))
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.usagePercent() >= 80 ? this.tk().warning : this.tk().primary)
                  }
                }.width('100%')
              } else {
                Text($r('app.string.budget_no_limit_tip'))
                  .width('100%')
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().textSecondary)
              }
            }
            .width('100%')
            .padding(SPACE_LARGE)
            .backgroundColor(this.tk().surface)
            .borderRadius(RADIUS_CARD)
            .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
          }

          Button($r('app.string.save'))
            .width('100%')
            .height(44)
            .fontSize(this.fs(16))
            .backgroundColor(this.tk().primary)
            .fontColor(this.tk().surface)
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
    .backgroundColor(this.tk().background)
  }
}
