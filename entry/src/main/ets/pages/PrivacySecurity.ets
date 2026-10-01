import AccountNavigator from '../components/Navigator';
import CloudLlmConfigStore from '../service/recognition/CloudLlmConfigStore';
import learnedClassifier from '../service/recognition/classifier/LearnedClassifier';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import BreakpointConstants from '../common/breakpoint';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_XLARGE } from '../common/dimens';

@Entry
@Component
struct PrivacySecurity {
  @State cloudConsent: boolean = false;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  async aboutToAppear(): Promise<void> {
    try {
      this.cloudConsent = await CloudLlmConfigStore.loadCloudConsent();
    } catch (error) {
      Logger.error('加载隐私设置失败', (error as Error).message);
    }
  }

  async onRevokeConsent(): Promise<void> {
    try {
      await CloudLlmConfigStore.saveCloudConsent(false);
      this.cloudConsent = false;
      Toast.success($r('app.string.revoke_consent_success'));
    } catch (error) {
      Logger.error('撤回云端授权失败', (error as Error).message);
    }
  }

  confirmClearLearned(): void {
    AlertDialog.show({
      title: $r('app.string.clear_learned_confirm_title'),
      message: $r('app.string.clear_learned_confirm_msg'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.clear_learned_confirm'),
        fontColor: $r('app.color.red'),
        action: () => {
          this.clearLearned();
        }
      }
    });
  }

  async clearLearned(): Promise<void> {
    try {
      const count = await learnedClassifier.clearLearned();
      Logger.debug('清除学习到的商家分类数量: ', count);
      Toast.success($r('app.string.clear_learned_success'));
    } catch (error) {
      Logger.error('清除学习分类失败', (error as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  build() {
    Column() {
      AccountNavigator({ title: $r('app.string.privacy_security') })
      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          Column({ space: SPACE_MEDIUM }) {
            Row({ space: SPACE_MEDIUM }) {
              Column({ space: 2 }) {
                Text($r('app.string.cloud_consent_label'))
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.font_3'))
                Text(this.cloudConsent ? $r('app.string.consent_granted') : $r('app.string.consent_not_granted'))
                  .fontSize(12)
                  .fontColor($r('app.color.font_2'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (this.cloudConsent) {
                Button($r('app.string.revoke_consent'))
                  .height(32)
                  .fontSize(13)
                  .fontColor($r('app.color.red'))
                  .backgroundColor($r('app.color.white'))
                  .type(ButtonType.Normal)
                  .borderRadius(SPACE_SMALL)
                  .border({ width: 1, color: $r('app.color.red') })
                  .onClick(() => {
                    this.onRevokeConsent();
                  })
              }
            }.width('100%')
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor($r('app.color.white'))
          .borderRadius(RADIUS_CARD)

          Button($r('app.string.clear_learned'))
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor($r('app.color.red'))
            .backgroundColor($r('app.color.white'))
            .type(ButtonType.Normal)
            .borderRadius(SPACE_SMALL)
            .border({ width: 1, color: $r('app.color.red') })
            .onClick(() => {
              this.confirmClearLearned();
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
