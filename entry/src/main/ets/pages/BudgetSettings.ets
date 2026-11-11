import dayjs from 'dayjs';
import AccountNavigator from '../components/Navigator';
import BudgetService from '../service/BudgetService';
import DBUtil from '../utils/DBUtil';
import { Logger } from '../utils/Logger';
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
import { AMOUNT_MAX, clampAmount } from '../utils/AmountGuard';

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
    try {
      // 等待数据库初始化完成，避免冷启动期间查询抛错导致超支进度显示为 0
      await DBUtil.ready;
      const status = await BudgetService.loadStatus();
      this.budgetOn = status.enabled;
      this.savedLimit = status.limit;
      this.monthExpenses = status.monthExpenses;
      this.amountText = status.limit > 0 ? String(status.limit) : '';
    } catch (err) {
      Logger.error('加载消费额度设置失败', (err as Error).message);
    }
  }

  // 预览时优先使用当前输入的合法额度（超上限按上限 9999999.99 预览），
  // 未输入或非法时回退到已保存额度，保证输入与下方预览始终一致
  effectiveLimit(): number {
    const text = this.amountText.trim();
    if (this.budgetOn && AMOUNT_PATTERN.test(text)) {
      const value = Number(text);
      if (Number.isFinite(value) && value > 0) {
        return clampAmount(value);
      }
    }
    return this.savedLimit;
  }

  // 输入超过金额上限时展示内联提示，避免用户误以为已按输入值生效
  isOverMax(): boolean {
    const text = this.amountText.trim();
    return AMOUNT_PATTERN.test(text) && Number(text) > AMOUNT_MAX;
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
    try {
      if (this.budgetOn) {
        const text = this.amountText.trim();
        if (!AMOUNT_PATTERN.test(text) || Number(text) <= 0) {
          Toast.error($r('app.string.budget_amount_invalid'));
          return;
        }
        if (Number(text) > AMOUNT_MAX) {
          Toast.error($r('app.string.amount_too_large'));
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
    } catch (err) {
      Logger.error('保存消费额度设置失败', (err as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  /**
   * 开关拨动即保存：关闭立即生效；
   * 开启时若输入框或上次保存的额度可用则立即生效，否则等输入额度后点保存
   */
  async onToggleChanged(isOn: boolean): Promise<void> {
    this.budgetOn = isOn;
    if (!isOn) {
      await this.onSave();
      return;
    }
    const text = this.amountText.trim();
    if (AMOUNT_PATTERN.test(text) && Number(text) > 0 && Number(text) <= AMOUNT_MAX) {
      await this.onSave();
      return;
    }
    if (this.savedLimit > 0) {
      await this.onSave();
      return;
    }
    // 首次开启且未输入额度：展示输入区，输入后点保存
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
              Toggle({ type: ToggleType.Switch, isOn: this.budgetOn })
                .onChange((isOn: boolean) => {
                  this.onToggleChanged(isOn);
                })
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
                .maxLength(10)
                .fontSize(this.fs(14))
                .fontColor(this.tk().textPrimary)
                .height(44)
                .backgroundColor(this.tk().surfaceVariant)
                .onChange((value: string) => {
                  this.amountText = value;
                })

              if (this.isOverMax()) {
                Text($r('app.string.amount_too_large'))
                  .width('100%')
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().danger)
              }

              Divider().color(this.tk().surfaceVariant)

              Row() {
                // 长标签随字号缩放，超出时省略号截断，避免把右侧金额挤出卡片
                Text($r('app.string.budget_month_spent_period_label', dayjs().format('YYYY年M月')))
                  .fontSize(this.fs(13))
                  .fontColor(this.tk().textSecondary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text('¥ ' + this.monthExpenses.toFixed(2))
                  .fontSize(this.fs(15))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.isOver() ? this.tk().danger : this.tk().textPrimary)
                  .maxLines(1)
              }.width('100%')

              if (this.effectiveLimit() > 0) {
                Progress({ value: this.usagePercent(), total: 100, type: ProgressType.Linear })
                  .color(this.progressColor())
                  .height(8)
                  .borderRadius(4)
                  .animation({ duration: 400, curve: Curve.EaseOut })
                Row() {
                  // 长标签（已支出 ¥xx / 额度 ¥xx）随字号缩放，超出时省略号截断
                  Text($r('app.string.budget_usage_label',
                    this.monthExpenses.toFixed(2), this.effectiveLimit().toFixed(2)))
                    .fontSize(this.fs(12))
                    .fontColor(this.tk().textSecondary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  if (this.isOver()) {
                    Text($r('app.string.budget_over_row_label', this.overAmount().toFixed(2)))
                      .fontSize(this.fs(12))
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.tk().danger)
                      .maxLines(1)
                  } else {
                    Text($r('app.string.budget_remaining_label', this.remainingAmount().toFixed(2)))
                      .fontSize(this.fs(12))
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.usagePercent() >= 80 ? this.tk().warning : this.tk().primary)
                      .maxLines(1)
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
