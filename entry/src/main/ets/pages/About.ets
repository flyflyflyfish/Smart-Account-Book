import router from '@ohos.router';
import { bundleManager } from '@kit.AbilityKit';
import AccountNavigator from '../components/Navigator';
import BreakpointConstants from '../common/breakpoint';
import {
  RADIUS_CARD, RADIUS_ICON, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY, SPACE_XLARGE
} from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';
import { Logger } from '../utils/Logger';

/**
 * 关于页：应用信息、开发者信息、开源声明与许可证、隐私政策入口。
 * 供应用市场审核展示开发者信息，同时作为开源署名入口。
 */
@Entry
@Component
struct About {

  @StorageProp('themeSeq') themeSeq: number = 0;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  @State versionName: string = '';

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  aboutToAppear(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.versionName = info.versionName;
    } catch (error) {
      Logger.error('读取应用版本号失败', (error as Error).message);
    }
  }

  @Builder
  InfoRow(label: ResourceStr, value: string) {
    Row({ space: SPACE_MEDIUM }) {
      Text(label)
        .fontSize(this.fs(13))
        .fontColor(this.tk().textSecondary)
        .width(76)
      Text(value)
        .fontSize(this.fs(13))
        .fontColor(this.tk().textPrimary)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  @Builder
  SectionText(title: ResourceStr, desc: ResourceStr) {
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
      AccountNavigator({ title: $r('app.string.about_title') })
      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          // 应用信息
          Column({ space: SPACE_SMALL }) {
            Image($r('app.media.icon'))
              .width(72)
              .height(72)
              .borderRadius(RADIUS_ICON)
              .objectFit(ImageFit.Cover)
            Text($r('app.string.about_app_name'))
              .fontSize(this.fs(20))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.tk().textPrimary)
            if (this.versionName) {
              Text($r('app.string.about_version_value', this.versionName))
                .fontSize(this.fs(12))
                .fontColor(this.tk().textSecondary)
            }
          }
          .width('100%')
          .padding({ top: SPACE_LARGE, bottom: SPACE_MEDIUM })

          // 开发者信息：供应用市场审核核验
          Column({ space: SPACE_MEDIUM }) {
            Text($r('app.string.about_developer_title'))
              .fontSize(this.fs(15))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.tk().textPrimary)
            this.InfoRow($r('app.string.about_developer_label'), 'hid12163462')
            this.InfoRow($r('app.string.about_email_label'), '3855757949@qq.com')
            this.InfoRow($r('app.string.about_home_label'), 'github.com/flyflyfishfish/Smart-Account-Book')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          // 开源声明与许可证
          Column({ space: SPACE_MEDIUM }) {
            Text($r('app.string.about_open_source_title'))
              .fontSize(this.fs(15))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.tk().textPrimary)
            this.SectionText($r('app.string.about_upstream_label'),
              'github.com/banggx/account_app_harmonyos (Apache License 2.0)')
            this.SectionText($r('app.string.about_license_label'), $r('app.string.about_license_desc'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          // 隐私政策入口
          Row({ space: SPACE_MEDIUM }) {
            Text($r('app.string.privacy_policy'))
              .fontSize(this.fs(14))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.tk().textPrimary)
              .layoutWeight(1)
            Image($r('app.media.arrow_left'))
              .width(14)
              .objectFit(ImageFit.Contain)
              .rotate({ angle: 180 })
              .fillColor(this.tk().textSecondary)
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/PrivacyPolicy' });
          })
        }
        .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
        .padding({ left: SPACE_XLARGE, right: SPACE_XLARGE, top: SPACE_MEDIUM, bottom: SPACE_LARGE })
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
