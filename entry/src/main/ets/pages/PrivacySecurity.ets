import router from '@ohos.router';
import AccountNavigator from '../components/Navigator';
import CloudLlmConfigStore from '../service/recognition/CloudLlmConfigStore';
import learnedClassifier from '../service/recognition/classifier/LearnedClassifier';
import MerchantLearningSync from '../service/MerchantLearningSync';
import CloudSyncService from '../service/CloudSyncService';
import WidgetUpdater from '../common/widget/WidgetUpdater';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import BreakpointConstants from '../common/breakpoint';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY, SPACE_XLARGE } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

/**
 * 隐私与安全页：隐私承诺说明、云端识别授权、数据管理（清除学习分类/清空全部账单数据）
 */
@Entry
@Component
struct PrivacySecurity {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  @State cloudConsent: boolean = false;
  @State clearing: boolean = false;
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
        fontColor: this.tk().danger,
        action: () => {
          this.clearLearned();
        }
      }
    });
  }

  async clearLearned(): Promise<void> {
    try {
      const count = await learnedClassifier.clearLearned();
      // 记录清除时间并删除云端行，防止已清记忆被下次同步从云端拉回
      await MerchantLearningSync.recordCleared();
      Logger.debug('清除学习到的商家分类数量: ', count);
      Toast.success($r('app.string.clear_learned_success'));
    } catch (error) {
      Logger.error('清除学习分类失败', (error as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  confirmClearAllFirst(): void {
    AlertDialog.show({
      title: $r('app.string.clear_all_confirm_title'),
      message: $r('app.string.clear_all_confirm_msg'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.clear_all_next'),
        fontColor: this.tk().danger,
        action: () => {
          this.confirmClearAllSecond();
        }
      }
    });
  }

  confirmClearAllSecond(): void {
    AlertDialog.show({
      title: $r('app.string.clear_all_confirm_again_title'),
      message: $r('app.string.clear_all_confirm_again_msg'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.clear_all_confirm_btn'),
        fontColor: this.tk().danger,
        action: () => {
          this.clearAllBills();
        }
      }
    });
  }

  async clearAllBills(): Promise<void> {
    if (this.clearing) {
      return;
    }
    this.clearing = true;
    try {
      await CloudSyncService.clearAllBillsData();
      // 清空后小组件金额归零，立即刷新卡片
      await WidgetUpdater.refreshAllForms(getContext(this), ThemeKit.palette());
      Toast.success($r('app.string.clear_all_success'));
    } catch (error) {
      Logger.error('清空全部账单数据失败', (error as Error).message);
      Toast.error($r('app.string.clear_all_failed'));
    } finally {
      this.clearing = false;
    }
  }

  @Builder
  PrivacyItem(title: ResourceStr, desc: ResourceStr) {
    Column({ space: SPACE_TINY }) {
      Text(title)
        .fontSize(this.fs(14))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tk().textPrimary)
      Text(desc)
        .fontSize(this.fs(12))
        .fontColor(this.tk().textSecondary)
        .lineHeight(this.fs(18))
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column() {
      AccountNavigator({ title: $r('app.string.privacy_security') })
      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          // 隐私承诺说明
          Column({ space: SPACE_MEDIUM }) {
            Text($r('app.string.privacy_commitment_title'))
              .fontSize(this.fs(15))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.tk().textPrimary)
            this.PrivacyItem($r('app.string.privacy_item_local_title'),
              $r('app.string.privacy_item_local_desc'))
            this.PrivacyItem($r('app.string.privacy_item_sync_title'),
              $r('app.string.privacy_item_sync_desc'))
            this.PrivacyItem($r('app.string.privacy_item_apikey_title'),
              $r('app.string.privacy_item_apikey_desc'))
            this.PrivacyItem($r('app.string.privacy_item_cloud_title'),
              $r('app.string.privacy_item_cloud_desc'))
            this.PrivacyItem($r('app.string.privacy_item_permission_title'),
              $r('app.string.privacy_item_permission_desc'))
            Button($r('app.string.privacy_policy_entry'))
              .width('100%')
              .height(36)
              .fontSize(this.fs(13))
              .fontColor(this.tk().primary)
              .backgroundColor(this.tk().surface)
              .type(ButtonType.Normal)
              .borderRadius(SPACE_SMALL)
              .border({ width: 1, color: this.tk().primary })
              .onClick(() => {
                router.pushUrl({ url: 'pages/PrivacyPolicy' });
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          // 云端识别授权
          Column({ space: SPACE_MEDIUM }) {
            Row({ space: SPACE_MEDIUM }) {
              Column({ space: 2 }) {
                Text($r('app.string.cloud_consent_label'))
                  .fontSize(this.fs(15))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.tk().textPrimary)
                Text(this.cloudConsent ? $r('app.string.consent_granted') : $r('app.string.consent_not_granted'))
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (this.cloudConsent) {
                Button($r('app.string.revoke_consent'))
                  .height(32)
                  .fontSize(this.fs(13))
                  .fontColor(this.tk().danger)
                  .backgroundColor(this.tk().surface)
                  .type(ButtonType.Normal)
                  .borderRadius(SPACE_SMALL)
                  .border({ width: 1, color: this.tk().danger })
                  .onClick(() => {
                    this.onRevokeConsent();
                  })
              }
            }.width('100%')
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          // 数据管理
          Column({ space: SPACE_LARGE }) {
            Text($r('app.string.data_management_title'))
              .fontSize(this.fs(15))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.tk().textPrimary)
            Row({ space: SPACE_MEDIUM }) {
              Column({ space: 2 }) {
                Text($r('app.string.clear_learned'))
                  .fontSize(this.fs(14))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.tk().textPrimary)
                Text($r('app.string.clear_learned_desc'))
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Button($r('app.string.clear_learned_confirm'))
                .height(32)
                .fontSize(this.fs(13))
                .fontColor(this.tk().danger)
                .backgroundColor(this.tk().surface)
                .type(ButtonType.Normal)
                .borderRadius(SPACE_SMALL)
                .border({ width: 1, color: this.tk().danger })
                .onClick(() => {
                  this.confirmClearLearned();
                })
            }.width('100%')
            Row({ space: SPACE_MEDIUM }) {
              Column({ space: 2 }) {
                Text($r('app.string.clear_all_bills'))
                  .fontSize(this.fs(14))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.tk().textPrimary)
                Text($r('app.string.clear_all_bills_desc'))
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().textSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Button(this.clearing ? $r('app.string.clearing_in_progress') : $r('app.string.clear_all_confirm_btn'))
                .height(32)
                .fontSize(this.fs(13))
                .fontColor(this.tk().danger)
                .backgroundColor(this.tk().surface)
                .type(ButtonType.Normal)
                .borderRadius(SPACE_SMALL)
                .border({ width: 1, color: this.tk().danger })
                .enabled(!this.clearing)
                .onClick(() => {
                  this.confirmClearAllFirst();
                })
            }.width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
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
