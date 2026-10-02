import router from '@ohos.router';
import { formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { Logger } from '../utils/Logger';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

/**
 * 设置菜单：作为底部 Tab 展示分组列表，点击进入各子页面
 */
@Component
export default struct SettingsView {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }
  @Builder SectionLabel(label: ResourceStr) {
    Text(label)
      .width('100%')
      .fontSize(this.fs(13))
      .fontColor(this.tk().textSecondary)
      .padding({ left: SPACE_TINY })
  }

  @Builder MenuRow(icon: ResourceStr, label: ResourceStr, desc: ResourceStr, url: string,
    accent: string, accentSoft: string) {
    Row({ space: SPACE_MEDIUM }) {
      Column() {
        Image(icon)
          .width(20)
          .height(20)
          .fillColor(accent)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(accentSoft)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      Column({ space: 2 }) {
        Text(label)
          .fontSize(this.fs(16))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().textPrimary)
        Text(desc)
          .fontSize(this.fs(12))
          .fontColor(this.tk().textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Image($r('app.media.arrow_left'))
        .width(14)
        .objectFit(ImageFit.Contain)
        .rotate({ angle: 180 })
        .fillColor(this.tk().textSecondary)
    }
    .width('100%')
    .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_MEDIUM, bottom: SPACE_MEDIUM })
    .backgroundColor(this.tk().surface)
    .borderRadius(RADIUS_CARD)
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
    .onClick(() => {
      router.pushUrl({ url: url });
    })
  }

  // 拉起系统卡片管理页，添加记账小组件到桌面
  addWidget(): void {
    const want: Want = {
      bundleName: 'com.flyfish.account_app',
      abilityName: 'EntryFormAbility',
      parameters: {
        'ohos.extra.param.key.form_dimension': 2,
        'ohos.extra.param.key.form_name': 'quickAccountCard',
        'ohos.extra.param.key.module_name': 'entry'
      }
    };
    try {
      formProvider.openFormManager(want);
    } catch (err) {
      Logger.error('打开卡片管理页失败', (err as Error).message);
    }
  }

  @Builder ActionRow(icon: ResourceStr, label: ResourceStr, desc: ResourceStr, action: () => void,
    accent: string, accentSoft: string) {
    Row({ space: SPACE_MEDIUM }) {
      Column() {
        Image(icon)
          .width(20)
          .height(20)
          .fillColor(accent)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(accentSoft)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      Column({ space: 2 }) {
        Text(label)
          .fontSize(this.fs(16))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().textPrimary)
        Text(desc)
          .fontSize(this.fs(12))
          .fontColor(this.tk().textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Image($r('app.media.arrow_left'))
        .width(14)
        .objectFit(ImageFit.Contain)
        .rotate({ angle: 180 })
        .fillColor(this.tk().textSecondary)
    }
    .width('100%')
    .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_MEDIUM, bottom: SPACE_MEDIUM })
    .backgroundColor(this.tk().surface)
    .borderRadius(RADIUS_CARD)
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
    .onClick(action)
  }

  build() {
    Column() {
      Text($r('app.string.settings_title'))
        .width('100%')
        .fontSize(this.fs(24))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tk().textPrimary)
        .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_LARGE, bottom: SPACE_SMALL })

      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          this.SectionLabel($r('app.string.settings_section_account'))
          this.MenuRow($r('app.media.user'), $r('app.string.account_login'),
            $r('app.string.account_login_desc'), 'pages/AccountLogin',
            this.tk().accentBlue, this.tk().accentBlueSoft)

          this.SectionLabel($r('app.string.settings_section_ai'))
          this.MenuRow($r('app.media.ai'), $r('app.string.model_settings'),
            $r('app.string.model_settings_desc'), 'pages/ModelSettings',
            this.tk().accentPurple, this.tk().accentPurpleSoft)

          this.SectionLabel($r('app.string.settings_section_general'))
          this.MenuRow($r('app.media.palette'), $r('app.string.appearance'),
            $r('app.string.appearance_desc'), 'pages/Appearance',
            this.tk().accentOrange, this.tk().accentOrangeSoft)
          this.MenuRow($r('app.media.shoping'), $r('app.string.category_manage'),
            $r('app.string.category_manage_desc'), 'pages/CategoryManage',
            this.tk().accentYellow, this.tk().accentYellowSoft)
          this.MenuRow($r('app.media.budget'), $r('app.string.budget_settings'),
            $r('app.string.budget_settings_desc'), 'pages/BudgetSettings',
            this.tk().accentGreen, this.tk().accentGreenSoft)
          this.MenuRow($r('app.media.date'), $r('app.string.recurring_bill_title'),
            $r('app.string.recurring_bill_settings_desc'), 'pages/RecurringBillManage',
            this.tk().accentRed, this.tk().accentRedSoft)
          this.MenuRow($r('app.media.stats'), $r('app.string.export_bill'),
            $r('app.string.export_bill_desc'), 'pages/ExportBill',
            this.tk().accentBlue, this.tk().accentBlueSoft)
          this.MenuRow($r('app.media.shield'), $r('app.string.privacy_security'),
            $r('app.string.privacy_security_desc'), 'pages/PrivacySecurity',
            this.tk().accentGreen, this.tk().accentGreenSoft)
          this.ActionRow($r('app.media.add'), $r('app.string.add_widget'),
            $r('app.string.add_widget_desc'), (): void => {
              this.addWidget();
            }, this.tk().accentOrange, this.tk().accentOrangeSoft)
        }
        .width('100%')
        .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_SMALL, bottom: SPACE_LARGE })
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
