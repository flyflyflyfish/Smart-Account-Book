import router from '@ohos.router';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY } from '../common/dimens';

/**
 * 设置菜单：作为底部 Tab 展示分组列表，点击进入各子页面
 */
@Component
export default struct SettingsView {
  @Builder SectionLabel(label: ResourceStr) {
    Text(label)
      .width('100%')
      .fontSize(13)
      .fontColor($r('app.color.font_2'))
      .padding({ left: SPACE_TINY })
  }

  @Builder MenuRow(icon: ResourceStr, label: ResourceStr, desc: ResourceStr, url: string) {
    Row({ space: SPACE_MEDIUM }) {
      Column() {
        Image(icon)
          .width(20)
          .height(20)
          .fillColor($r('app.color.green'))
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.green_alpha'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      Column({ space: 2 }) {
        Text(label)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.font_3'))
        Text(desc)
          .fontSize(12)
          .fontColor($r('app.color.font_2'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Image($r('app.media.arrow_left'))
        .width(14)
        .objectFit(ImageFit.Contain)
        .rotate({ angle: 180 })
        .fillColor($r('app.color.font_2'))
    }
    .width('100%')
    .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_MEDIUM, bottom: SPACE_MEDIUM })
    .backgroundColor($r('app.color.white'))
    .borderRadius(RADIUS_CARD)
    .onClick(() => {
      router.pushUrl({ url: url });
    })
  }

  build() {
    Column() {
      Text($r('app.string.settings_title'))
        .width('100%')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.font_1'))
        .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_LARGE, bottom: SPACE_SMALL })

      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          this.SectionLabel($r('app.string.settings_section_account'))
          this.MenuRow($r('app.media.user'), $r('app.string.account_login'),
            $r('app.string.account_login_desc'), 'pages/AccountLogin')

          this.SectionLabel($r('app.string.settings_section_ai'))
          this.MenuRow($r('app.media.ai'), $r('app.string.model_settings'),
            $r('app.string.model_settings_desc'), 'pages/ModelSettings')

          this.SectionLabel($r('app.string.settings_section_general'))
          this.MenuRow($r('app.media.palette'), $r('app.string.appearance'),
            $r('app.string.appearance_desc'), 'pages/Appearance')
          this.MenuRow($r('app.media.shield'), $r('app.string.privacy_security'),
            $r('app.string.privacy_security_desc'), 'pages/PrivacySecurity')
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
    .backgroundColor($r('app.color.bg'))
  }
}
