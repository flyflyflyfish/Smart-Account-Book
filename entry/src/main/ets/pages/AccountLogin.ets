import AccountNavigator from '../components/Navigator';
import AuthService from '../service/AuthService';
import CloudInit from '../data/CloudInit';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import BreakpointConstants from '../common/breakpoint';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

@Entry
@Component
struct AccountLogin {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

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
      if (CloudInit.isReady()) {
        Toast.success($r('app.string.sign_in_success'));
      } else {
        // 登录成功但云服务初始化失败：本地记账不受影响，但需明确告知云端同步不可用
        Toast.error($r('app.string.cloud_sync_unavailable'));
        Logger.error('云同步初始化失败', '登录成功但云开发服务不可用，账单将不会同步到云端');
      }
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
                .fillColor(this.tk().primary)
            }
            .width(64)
            .height(64)
            .borderRadius(32)
            .backgroundColor(this.tk().primarySoft)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            Text(this.signedIn ? $r('app.string.signed_in') : $r('app.string.not_signed_in'))
              .fontSize(this.fs(18))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.tk().textPrimary)
            if (this.signedIn) {
              Text($r('app.string.uid_label') + ': ' + this.uid)
                .fontSize(this.fs(13))
                .fontColor(this.tk().textSecondary)
            }
            Text($r('app.string.cloud_sync_hint'))
              .width('100%')
              .fontSize(this.fs(12))
              .lineHeight(this.fs(17))
              .fontColor(this.tk().textSecondary)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          if (this.signedIn) {
            Button($r('app.string.sign_out'))
              .width('100%')
              .height(44)
              .fontSize(this.fs(15))
              .fontColor(this.tk().danger)
              .backgroundColor(this.tk().surface)
              .type(ButtonType.Normal)
              .borderRadius(SPACE_SMALL)
              .border({ width: 1, color: this.tk().danger })
              .onClick(() => {
                this.onSignOut();
              })
          } else {
            Button($r('app.string.sign_in_huawei'))
              .width('100%')
              .height(44)
              .fontSize(this.fs(15))
              .fontColor(this.tk().surface)
              .backgroundColor(this.tk().primary)
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
    .backgroundColor(this.tk().background)
  }
}
