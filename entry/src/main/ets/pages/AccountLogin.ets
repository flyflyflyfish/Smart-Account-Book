import AccountNavigator from '../components/Navigator';
import AuthService from '../service/AuthService';
import CloudInit from '../data/CloudInit';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import BreakpointConstants from '../common/breakpoint';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL } from '../common/dimens';

@Entry
@Component
struct AccountLogin {
  @State signedIn: boolean = false;
  @State uid: string = '';
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  async aboutToAppear(): Promise<void> {
    try {
      const currentUid = await AuthService.getCurrentUid();
      if (currentUid) {
        this.signedIn = true;
        this.uid = currentUid;
      }
    } catch (error) {
      Logger.error('加载登录状态失败', (error as Error).message);
    }
  }

  async onSignIn(): Promise<void> {
    const currentUid = await AuthService.signInWithHuaweiId();
    if (currentUid) {
      CloudInit.init();
      this.signedIn = true;
      this.uid = currentUid;
      Toast.success($r('app.string.sign_in_success'));
    } else {
      Toast.error($r('app.string.sign_in_failed'));
    }
  }

  async onSignOut(): Promise<void> {
    const success = await AuthService.signOut();
    if (success) {
      CloudInit.reset();
      this.signedIn = false;
      this.uid = '';
      Toast.success($r('app.string.sign_out_success'));
    }
  }

  build() {
    Column() {
      AccountNavigator({ title: $r('app.string.account_login') })
      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          Column({ space: SPACE_MEDIUM }) {
            Column() {
              Image($r('app.media.user'))
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
            Text(this.signedIn ? $r('app.string.signed_in') : $r('app.string.not_signed_in'))
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.font_3'))
            if (this.signedIn) {
              Text($r('app.string.uid_label') + ': ' + this.uid)
                .fontSize(13)
                .fontColor($r('app.color.font_2'))
            }
            Text($r('app.string.cloud_sync_hint'))
              .width('100%')
              .fontSize(12)
              .lineHeight(17)
              .fontColor($r('app.color.font_2'))
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor($r('app.color.white'))
          .borderRadius(RADIUS_CARD)

          if (this.signedIn) {
            Button($r('app.string.sign_out'))
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontColor($r('app.color.red'))
              .backgroundColor($r('app.color.white'))
              .type(ButtonType.Normal)
              .borderRadius(SPACE_SMALL)
              .border({ width: 1, color: $r('app.color.red') })
              .onClick(() => {
                this.onSignOut();
              })
          } else {
            Button($r('app.string.sign_in_huawei'))
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontColor($r('app.color.white'))
              .backgroundColor($r('app.color.green'))
              .type(ButtonType.Normal)
              .borderRadius(SPACE_SMALL)
              .onClick(() => {
                this.onSignIn();
              })
          }
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
