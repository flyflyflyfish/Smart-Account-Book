import AccountNavigator from '../components/Navigator';
import BreakpointConstants from '../common/breakpoint';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM } from '../common/dimens';

@Entry
@Component
struct Appearance {
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  build() {
    Column() {
      AccountNavigator({ title: $r('app.string.appearance') })
      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          Column({ space: SPACE_MEDIUM }) {
            Column() {
              Image($r('app.media.palette'))
                .width(28)
                .height(28)
                .fillColor($r('app.color.green'))
            }
            .width(64)
            .height(64)
            .borderRadius(32)
            .backgroundColor($r('app.color.green_alpha'))
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            Text($r('app.string.appearance_coming_soon'))
              .fontSize(14)
              .fontColor($r('app.color.font_2'))
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor($r('app.color.white'))
          .borderRadius(RADIUS_CARD)
        }
        .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
        .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_LARGE })
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
