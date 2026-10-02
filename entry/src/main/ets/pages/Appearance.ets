import router from '@ohos.router';
import BreakpointConstants from '../common/breakpoint';
import { PAGE_PADDING, RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_XLARGE } from '../common/dimens';
import {
  ThemeKit,
  ThemePalette,
  THEME_ID_CLAUDE,
  THEME_ID_LIST,
  THEME_ID_NOTION,
  THEME_ID_PINE,
  THEME_ID_SKY,
  THEME_ID_STONE,
  THEME_ID_VIOLET,
  THEME_MODE_DARK,
  THEME_MODE_LIGHT,
  THEME_MODE_SYSTEM,
  FONT_SCALE_DEFAULT,
  FONT_SCALE_LARGE,
  FONT_SCALE_SMALL,
  FONT_SCALE_XLARGE,
  GLOW_LEVEL_SOFT,
  GLOW_LEVEL_STANDARD,
  GLOW_LEVEL_STRONG,
  glowShadowColor
} from '../common/theme/Theme';

// 基准字号（sp）：字号滑杆与缩放档位都基于 15sp 换算
const APPEARANCE_BASE_FONT: number = 15;

// 主题候选项：名称与副标题走资源，id 对应 Theme.ets
interface AppearanceThemeOption {
  id: string;
  name: ResourceStr;
  desc: ResourceStr;
}

const APPEARANCE_THEME_OPTIONS: AppearanceThemeOption[] = [
  { id: THEME_ID_PINE, name: $r('app.string.theme_name_pine'), desc: $r('app.string.theme_desc_pine') },
  { id: THEME_ID_CLAUDE, name: $r('app.string.theme_name_claude'), desc: $r('app.string.theme_desc_claude') },
  { id: THEME_ID_SKY, name: $r('app.string.theme_name_sky'), desc: $r('app.string.theme_desc_sky') },
  { id: THEME_ID_VIOLET, name: $r('app.string.theme_name_violet'), desc: $r('app.string.theme_desc_violet') },
  { id: THEME_ID_NOTION, name: $r('app.string.theme_name_notion'), desc: $r('app.string.theme_desc_notion') },
  { id: THEME_ID_STONE, name: $r('app.string.theme_name_stone'), desc: $r('app.string.theme_desc_stone') }
];

// 深浅色模式候选项
interface AppearanceModeOption {
  key: string;
  label: ResourceStr;
}

const APPEARANCE_MODE_OPTIONS: AppearanceModeOption[] = [
  { key: THEME_MODE_SYSTEM, label: $r('app.string.appearance_mode_system') },
  { key: THEME_MODE_LIGHT, label: $r('app.string.appearance_mode_light') },
  { key: THEME_MODE_DARK, label: $r('app.string.appearance_mode_dark') }
];

// 字号缩放档位
interface AppearanceFontOption {
  scale: number;
  label: ResourceStr;
}

const APPEARANCE_FONT_OPTIONS: AppearanceFontOption[] = [
  { scale: FONT_SCALE_SMALL, label: $r('app.string.appearance_font_small') },
  { scale: FONT_SCALE_DEFAULT, label: $r('app.string.appearance_font_default') },
  { scale: FONT_SCALE_LARGE, label: $r('app.string.appearance_font_large') },
  { scale: FONT_SCALE_XLARGE, label: $r('app.string.appearance_font_xlarge') }
];

// 光感（阴影浓度）档位
interface AppearanceGlowOption {
  key: string;
  label: ResourceStr;
}

const APPEARANCE_GLOW_OPTIONS: AppearanceGlowOption[] = [
  { key: GLOW_LEVEL_SOFT, label: $r('app.string.glow_soft') },
  { key: GLOW_LEVEL_STANDARD, label: $r('app.string.glow_standard') },
  { key: GLOW_LEVEL_STRONG, label: $r('app.string.glow_strong') }
];

const APPEARANCE_TAB_LABELS: ResourceStr[] = [
  $r('app.string.appearance_tab_theme'),
  $r('app.string.appearance_tab_font'),
  $r('app.string.appearance_tab_motion'),
  $r('app.string.appearance_tab_glow')
];

@Entry
@Component
struct Appearance {

  @StorageProp('themeSeq') themeSeq: number = 0;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  // 当前页签：0 主题 / 1 字体与排版 / 2 流式动效 / 3 光感
  @State currentTab: number = 0;
  // 深浅色模式与主题 id（本地镜像 ThemeKit，点击即写回）
  @State colorMode: string = THEME_MODE_SYSTEM;
  @State themeId: string = THEME_ID_PINE;
  // 字号滑杆位置（sp），拖动实时预览，松手写回全局
  @State previewSize: number = APPEARANCE_BASE_FONT;
  // 光感档位（本地镜像 ThemeKit，点击即写回）
  @State glowLevel: string = GLOW_LEVEL_STANDARD;

  aboutToAppear(): void {
    this.colorMode = ThemeKit.currentMode();
    this.themeId = ThemeKit.currentThemeId();
    this.previewSize = APPEARANCE_BASE_FONT * ThemeKit.currentFontScale();
    this.glowLevel = ThemeKit.currentGlowLevel();
  }

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  // 主题卡片的迷你预览取对应主题浅色套
  themePreview(id: string): ThemePalette {
    return ThemeKit.previewPalette(id);
  }

  // 字号当前值文案（如 “15 sp”）
  currentFontText(): string {
    return Math.round(this.previewSize) + ' sp';
  }

  selectMode(mode: string): void {
    this.colorMode = mode;
    ThemeKit.setMode(mode);
  }

  selectTheme(id: string): void {
    this.themeId = id;
    ThemeKit.setThemeId(id);
  }

  selectFontScale(scale: number): void {
    this.previewSize = APPEARANCE_BASE_FONT * scale;
    ThemeKit.setFontScale(scale);
  }

  selectGlow(level: string): void {
    this.glowLevel = level;
    ThemeKit.setGlowLevel(level);
  }

  showCustomThemeToast(): void {
    this.getUIContext().getPromptAction().showToast({
      message: $r('app.string.appearance_theme_custom_toast'),
      duration: 2000
    });
  }

  build() {
    Column() {
      this.HeaderBar()
      this.TabBar()
      Scroll() {
        Column({ space: SPACE_LARGE }) {
          if (this.currentTab === 0) {
            this.ThemeTab()
          } else if (this.currentTab === 1) {
            this.FontTab()
          } else if (this.currentTab === 2) {
            this.PlaceholderCard($r('app.string.appearance_motion_placeholder'))
          } else {
            this.GlowTab()
          }
        }
        .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: SPACE_LARGE, bottom: SPACE_LARGE })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }

  @Builder HeaderBar() {
    Row({ space: SPACE_MEDIUM }) {
      Column() {
        Image($r('app.media.arrow_left'))
          .height(14)
          .objectFit(ImageFit.Contain)
          .fillColor(this.tk().textPrimary)
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.tk().surfaceVariant)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        router.back();
      })
      Text($r('app.string.appearance_title'))
        .fontSize(this.fs(18))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tk().textPrimary)
    }
    .width('100%')
    .height(56)
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
  }

  @Builder TabBar() {
    Row() {
      ForEach(APPEARANCE_TAB_LABELS, (label: ResourceStr, index: number) => {
        Column({ space: 4 }) {
          Text(label)
            .fontSize(this.fs(14))
            .fontWeight(index === this.currentTab ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(index === this.currentTab ? this.tk().primary : this.tk().textSecondary)
          Column()
            .width(20)
            .height(3)
            .borderRadius(1.5)
            .backgroundColor(index === this.currentTab ? this.tk().primary : Color.Transparent)
        }
        .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM })
        .onClick(() => {
          this.currentTab = index;
        })
      }, (label: ResourceStr, index: number): string => 'appearance_tab_' + index)
    }
    .width('100%')
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING, bottom: SPACE_SMALL })
  }

  @Builder ThemeTab() {
    Column({ space: SPACE_LARGE }) {
      // 深浅色模式分段控件
      Row() {
        ForEach(APPEARANCE_MODE_OPTIONS, (option: AppearanceModeOption) => {
          Text(option.label)
            .fontSize(this.fs(13))
            .fontWeight(this.colorMode === option.key ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.colorMode === option.key ? this.tk().onPrimary : this.tk().textSecondary)
            .padding({ top: 8, bottom: 8, left: SPACE_LARGE, right: SPACE_LARGE })
            .backgroundColor(this.colorMode === option.key ? this.tk().primary : Color.Transparent)
            .borderRadius(999)
            .onClick(() => {
              this.selectMode(option.key);
            })
        }, (option: AppearanceModeOption): string => 'appearance_mode_' + option.key)
      }
      .width('100%')
      .padding(4)
      .backgroundColor(this.tk().surfaceVariant)
      .borderRadius(999)
      .justifyContent(FlexAlign.Center)

      // 主题色卡片网格
      Column({ space: SPACE_MEDIUM }) {
        Text($r('app.string.appearance_theme_section'))
          .fontSize(this.fs(13))
          .fontColor(this.tk().textSecondary)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(APPEARANCE_THEME_OPTIONS, (option: AppearanceThemeOption) => {
            this.ThemeCard(option)
          }, (option: AppearanceThemeOption): string => 'appearance_theme_' + option.id)
        }
        .width('100%')
        this.CustomThemeEntry()
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder ThemeCard(option: AppearanceThemeOption) {
    Column({ space: SPACE_SMALL }) {
      // 迷你界面预览：模拟顶栏 / 正文行 / 主按钮的配色关系
      Column({ space: 6 }) {
        Row({ space: SPACE_SMALL }) {
          Column()
            .width(10)
            .height(10)
            .borderRadius(5)
            .backgroundColor(this.themePreview(option.id).primary)
          Column()
            .height(6)
            .width(52)
            .borderRadius(3)
            .backgroundColor(this.themePreview(option.id).primaryContainer)
        }
        .width('100%')
        Column()
          .height(5)
          .width('100%')
          .borderRadius(2.5)
          .backgroundColor(this.themePreview(option.id).surfaceVariant)
        Column()
          .height(5)
          .width('60%')
          .borderRadius(2.5)
          .backgroundColor(this.themePreview(option.id).surfaceVariant)
        Row() {
          Column()
            .width(56)
            .height(10)
            .borderRadius(5)
            .backgroundColor(this.themePreview(option.id).primary)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .padding(SPACE_MEDIUM)
      .backgroundColor(this.themePreview(option.id).background)
      .borderRadius(14)

      Row() {
        Column({ space: 2 }) {
          Text(option.name)
            .fontSize(this.fs(13))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themeId === option.id ? this.tk().primary : this.tk().textPrimary)
          Text(option.desc)
            .fontSize(this.fs(11))
            .fontColor(this.tk().textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.themeId === option.id) {
          Text('✓')
            .fontSize(this.fs(12))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tk().onPrimary)
            .width(18)
            .height(18)
            .textAlign(TextAlign.Center)
            .backgroundColor(this.tk().primary)
            .borderRadius(9)
        }
      }
      .width('100%')
    }
    .width('48.5%')
    .padding(SPACE_SMALL)
    .backgroundColor(this.tk().surface)
    .borderRadius(18)
    .border({
      width: this.themeId === option.id ? 2 : 1,
      color: this.themeId === option.id ? this.tk().primary : this.tk().outline
    })
    .onClick(() => {
      this.selectTheme(option.id);
    })
  }

  @Builder CustomThemeEntry() {
    Row({ space: SPACE_MEDIUM }) {
      Column() {
        Text('+')
          .fontSize(this.fs(18))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().primary)
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.tk().primarySoft)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      Column({ space: 2 }) {
        Text($r('app.string.appearance_theme_custom'))
          .fontSize(this.fs(13))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().textPrimary)
        Text($r('app.string.appearance_theme_custom_desc'))
          .fontSize(this.fs(11))
          .fontColor(this.tk().textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: SPACE_MEDIUM, bottom: SPACE_MEDIUM, left: SPACE_MEDIUM, right: SPACE_MEDIUM })
    .borderRadius(18)
    .border({ width: 1.5, color: this.tk().outline, style: BorderStyle.Dashed })
    .onClick(() => {
      this.showCustomThemeToast();
    })
  }

  @Builder FontTab() {
    Column({ space: SPACE_LARGE }) {
      // 预览卡：跟随滑杆实时缩放
      Column({ space: SPACE_MEDIUM }) {
        Row() {
          Text($r('app.string.appearance_font_preview_label'))
            .fontSize(this.fs(11))
            .fontColor(this.tk().textSecondary)
          Blank()
          Text(this.currentFontText())
            .fontSize(this.fs(11))
            .fontColor(this.tk().primary)
        }
        .width('100%')
        Text($r('app.string.appearance_font_preview_text'))
          .fontSize(this.previewSize)
          .lineHeight(this.previewSize * 1.5)
          .fontColor(this.tk().textPrimary)
        Row({ space: SPACE_MEDIUM }) {
          Column() {
            Text('¥')
              .fontSize(this.fs(12))
              .fontColor(this.tk().textSecondary)
          }
          .justifyContent(FlexAlign.End)
          Text('1,280.00')
            .fontSize(this.previewSize + 4)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tk().primary)
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        Text($r('app.string.appearance_font_preview_amount'))
          .fontSize(this.fs(11))
          .fontColor(this.tk().textSecondary)
      }
      .width('100%')
      .padding(SPACE_LARGE)
      .backgroundColor(this.tk().surface)
      .borderRadius(RADIUS_CARD)
      .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
      .alignItems(HorizontalAlign.Start)

      // 滑杆 + 档位：拖动实时预览，松手全局生效
      Column({ space: SPACE_MEDIUM }) {
        Row({ space: SPACE_MEDIUM }) {
          Slider({
            value: this.previewSize,
            min: 12,
            max: 20,
            step: 0.25,
            style: SliderStyle.InSet
          })
            .selectedColor(this.tk().primary)
            .trackColor(this.tk().surfaceVariant)
            .blockColor(this.tk().primary)
            .layoutWeight(1)
            .onChange((value: number, mode: SliderChangeMode) => {
              this.previewSize = value;
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                ThemeKit.setFontScale(value / APPEARANCE_BASE_FONT);
              }
            })
          Text(this.currentFontText())
            .fontSize(this.fs(13))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tk().textPrimary)
            .width(44)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        Row() {
          ForEach(APPEARANCE_FONT_OPTIONS, (option: AppearanceFontOption) => {
            Text(option.label)
              .fontSize(this.fs(13))
              .fontWeight(Math.abs(this.previewSize - APPEARANCE_BASE_FONT * option.scale) < 0.01
                ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(Math.abs(this.previewSize - APPEARANCE_BASE_FONT * option.scale) < 0.01
                ? this.tk().onPrimary : this.tk().textSecondary)
              .padding({ top: 7, bottom: 7, left: SPACE_MEDIUM, right: SPACE_MEDIUM })
              .backgroundColor(Math.abs(this.previewSize - APPEARANCE_BASE_FONT * option.scale) < 0.01
                ? this.tk().primary : Color.Transparent)
              .borderRadius(999)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.selectFontScale(option.scale);
              })
          }, (option: AppearanceFontOption): string => 'appearance_font_' + option.scale)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .padding(SPACE_LARGE)
      .backgroundColor(this.tk().surface)
      .borderRadius(RADIUS_CARD)
      .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder PlaceholderCard(message: ResourceStr) {
    Column({ space: SPACE_MEDIUM }) {
      Column()
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(this.tk().primarySoft)
      Text(message)
        .fontSize(this.fs(13))
        .fontColor(this.tk().textSecondary)
        .textAlign(TextAlign.Center)
        .lineHeight(this.fs(20))
    }
    .width('100%')
    .padding(SPACE_XLARGE)
    .backgroundColor(this.tk().surface)
    .borderRadius(RADIUS_CARD)
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder GlowTab() {
    Column({ space: SPACE_LARGE }) {
      // 说明文案
      Text($r('app.string.appearance_glow_placeholder'))
        .fontSize(this.fs(13))
        .fontColor(this.tk().textSecondary)
        .lineHeight(this.fs(20))

      // 三档浓度预览：点击即切换，当前档高亮描边
      Row({ space: SPACE_MEDIUM }) {
        ForEach(APPEARANCE_GLOW_OPTIONS, (option: AppearanceGlowOption) => {
          Column({ space: SPACE_SMALL }) {
            // 模拟一张卡片，用对应档位的阴影色实时预览
            Column()
              .width('100%')
              .height(72)
              .backgroundColor(this.tk().surface)
              .borderRadius(16)
              .shadow({
                radius: 16,
                color: glowShadowColor(this.tk().primary, this.tk().isDark, option.key),
                offsetX: 0,
                offsetY: 6
              })
            Text(option.label)
              .fontSize(this.fs(13))
              .fontWeight(this.glowLevel === option.key ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.glowLevel === option.key ? this.tk().primary : this.tk().textSecondary)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .padding(SPACE_SMALL)
          .borderRadius(18)
          .border({
            width: this.glowLevel === option.key ? 2 : 1,
            color: this.glowLevel === option.key ? this.tk().primary : Color.Transparent
          })
          .onClick(() => {
            this.selectGlow(option.key);
          })
        }, (option: AppearanceGlowOption): string => 'appearance_glow_' + option.key)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 档位分段：与深浅色模式一致的胶囊样式
      Column({ space: SPACE_MEDIUM }) {
        Text($r('app.string.appearance_glow_section'))
          .fontSize(this.fs(13))
          .fontColor(this.tk().textSecondary)
        Row() {
          ForEach(APPEARANCE_GLOW_OPTIONS, (option: AppearanceGlowOption) => {
            Text(option.label)
              .fontSize(this.fs(13))
              .fontWeight(this.glowLevel === option.key ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.glowLevel === option.key ? this.tk().onPrimary : this.tk().textSecondary)
              .padding({ top: 8, bottom: 8, left: SPACE_LARGE, right: SPACE_LARGE })
              .backgroundColor(this.glowLevel === option.key ? this.tk().primary : Color.Transparent)
              .borderRadius(999)
              .onClick(() => {
                this.selectGlow(option.key);
              })
          }, (option: AppearanceGlowOption): string => 'appearance_glow_seg_' + option.key)
        }
        .width('100%')
        .padding(4)
        .backgroundColor(this.tk().surfaceVariant)
        .borderRadius(999)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(SPACE_LARGE)
      .backgroundColor(this.tk().surface)
      .borderRadius(RADIUS_CARD)
      .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
