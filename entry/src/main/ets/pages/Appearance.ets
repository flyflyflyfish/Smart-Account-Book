import router from '@ohos.router';
import { BusinessError } from '@kit.BasicServicesKit';
import BreakpointConstants from '../common/breakpoint';
import SecondTabStore from '../common/SecondTabStore';
import {
  PREF_LEDGER_SYNC_BILLS,
  SECOND_TAB_STYLE_AI,
  SECOND_TAB_STYLE_LEDGER
} from '../common/constants';
import PreferenceUtil from '../utils/PreferenceUtil';
import { Logger } from '../utils/Logger';
import { PAGE_PADDING, RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY } from '../common/dimens';
import {
  ThemeKit,
  ThemePalette,
  THEME_ID_CLAUDE,
  THEME_ID_CUSTOM,
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
  HOME_SCOPE_DAY,
  HOME_SCOPE_MONTH,
  buildCustomPalette,
  colorFromHsl,
  colorToHsl,
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
  $r('app.string.appearance_tab_home'),
  $r('app.string.appearance_tab_glow')
];

// 自定义主题编辑器：预设种子色（#RRGGBB，小写与 colorFromHsl 输出一致便于选中比对）
const CUSTOM_SWATCHES: string[] = [
  '#2E9E73', '#3AA0A8', '#3B82D6', '#4A5B7A', '#8A63C2',
  '#D6558A', '#D95757', '#C46A35', '#BF8A42', '#5A8A3C'
];

// 编辑器滑杆取值范围：饱和度/明度收窄到可保证对比度的区间
const EDITOR_SAT_MIN: number = 0.15;
const EDITOR_SAT_MAX: number = 0.9;
const EDITOR_LIGHT_MIN: number = 0.25;
const EDITOR_LIGHT_MAX: number = 0.6;

@Entry
@Component
struct Appearance {

  @StorageProp('themeSeq') themeSeq: number = 0;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  // 当前页签：0 主题 / 1 字体与排版 / 2 首页统计 / 3 光感
  @State currentTab: number = 0;
  // 深浅色模式与主题 id（本地镜像 ThemeKit，点击即写回）
  @State colorMode: string = THEME_MODE_SYSTEM;
  @State themeId: string = THEME_ID_PINE;
  // 字号滑杆位置（sp），拖动实时预览，松手写回全局
  @State previewSize: number = APPEARANCE_BASE_FONT;
  // 光感档位（本地镜像 ThemeKit，点击即写回）
  @State glowLevel: string = GLOW_LEVEL_STANDARD;
  // 首页汇总口径（本地镜像 ThemeKit，点击即写回，默认按月）
  @State homeScope: string = HOME_SCOPE_MONTH;
  // 底部第二页签样式：AI 助手 / 账本（存 Preferences + AppStorage，Index 据此切换）
  @State secondTab: string = SECOND_TAB_STYLE_AI;
  // 账本同步主账单默认开关（账本内记一笔/图片识别入账时是否同步计入主账单）
  @State ledgerSyncDefault: boolean = true;
  // 自定义主题：种子色（空串代表未创建）与编辑器开合/HSV 状态
  @State customColor: string = '';
  @State showCustomEditor: boolean = false;
  @State editorH: number = 150;
  @State editorS: number = 0.55;
  @State editorL: number = 0.4;

  aboutToAppear(): void {
    this.colorMode = ThemeKit.currentMode();
    this.themeId = ThemeKit.currentThemeId();
    this.previewSize = APPEARANCE_BASE_FONT * ThemeKit.currentFontScale();
    this.glowLevel = ThemeKit.currentGlowLevel();
    this.homeScope = ThemeKit.currentHomeScope();
    this.secondTab = SecondTabStore.current();
    this.customColor = ThemeKit.currentCustomColor();
    this.loadLedgerSyncDefault();
  }

  // 读取“账本同步主账单”默认开关；读取失败保持默认 true
  async loadLedgerSyncDefault(): Promise<void> {
    try {
      const value = await PreferenceUtil.getPreferenceValue(PREF_LEDGER_SYNC_BILLS, true);
      this.ledgerSyncDefault = value === true;
    } catch (err) {
      Logger.error('读取账本同步默认设置失败', (err as Error).message);
    }
  }

  // 切换并持久化“账本同步主账单”默认开关
  setLedgerSyncDefault(isOn: boolean): void {
    this.ledgerSyncDefault = isOn;
    PreferenceUtil.putPreferenceValue(PREF_LEDGER_SYNC_BILLS, isOn).catch((err: BusinessError) => {
      Logger.error('保存账本同步默认设置失败', err.message);
    });
  }

  selectSecondTab(style: string): void {
    this.secondTab = style;
    SecondTabStore.set(style);
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

  selectHomeScope(scope: string): void {
    this.homeScope = scope;
    ThemeKit.setHomeScope(scope);
  }

  // ===== 自定义主题编辑器 =====

  // 编辑器当前种子色（由 HSV 状态实时计算）
  editorColor(): string {
    return colorFromHsl(this.editorH, this.editorS, this.editorL);
  }

  // 编辑器实时预览调色板（浅色套）
  editorPreview(): ThemePalette {
    return buildCustomPalette(this.editorColor(), false);
  }

  // 打开编辑器：已创建过则从现有种子色初始化，否则从默认绿开始
  openCustomEditor(): void {
    const base = this.customColor.length > 0 ? this.customColor : '#2E9E73';
    this.setEditorColor(base);
    this.showCustomEditor = true;
  }

  // 按种子色设置编辑器状态（饱和度/明度收窄到可保证对比度的区间）
  setEditorColor(color: string): void {
    const hsl = colorToHsl(color);
    this.editorH = Math.round(hsl[0]);
    this.editorS = Math.min(EDITOR_SAT_MAX, Math.max(EDITOR_SAT_MIN, hsl[1]));
    this.editorL = Math.min(EDITOR_LIGHT_MAX, Math.max(EDITOR_LIGHT_MIN, hsl[2]));
  }

  // 保存并应用：更新种子色后切换到自定义主题
  saveCustomTheme(): void {
    const color = this.editorColor();
    ThemeKit.setCustomTheme(color);
    this.customColor = color;
    this.themeId = THEME_ID_CUSTOM;
    ThemeKit.setThemeId(THEME_ID_CUSTOM);
    this.showCustomEditor = false;
  }

  build() {
    Stack() {
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
              this.HomeTab()
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

      // 自定义主题编辑器浮层
      if (this.showCustomEditor) {
        this.CustomThemeEditorOverlay()
      }
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
          // 已创建的自定义主题：以第 7 张卡片出现在网格中
          if (this.customColor.length > 0) {
            this.ThemeCard({
              id: THEME_ID_CUSTOM,
              name: $r('app.string.appearance_theme_custom'),
              desc: this.customColor.toUpperCase()
            })
          }
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
        if (this.customColor.length > 0) {
          // 已创建：显示当前种子色圆点
          Column()
            .width(16)
            .height(16)
            .borderRadius(8)
            .backgroundColor(this.customColor)
        } else {
          Text('+')
            .fontSize(this.fs(18))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tk().primary)
        }
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
        Text(this.customColor.length > 0
          ? $r('app.string.appearance_theme_custom_edit_desc', this.customColor.toUpperCase())
          : $r('app.string.appearance_theme_custom_desc'))
          .fontSize(this.fs(11))
          .fontColor(this.tk().textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.themeId === THEME_ID_CUSTOM) {
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
    .padding({ top: SPACE_MEDIUM, bottom: SPACE_MEDIUM, left: SPACE_MEDIUM, right: SPACE_MEDIUM })
    .borderRadius(18)
    .border({ width: 1.5, color: this.themeId === THEME_ID_CUSTOM ? this.tk().primary : this.tk().outline, style: BorderStyle.Dashed })
    .onClick(() => {
      this.openCustomEditor();
    })
  }

  // ===== 自定义主题编辑器浮层 =====

  // 预设种子色圆点：当前色与预设一致时高亮描边
  @Builder EditorSwatch(color: string) {
    Column() {
      Column()
        .width(30)
        .height(30)
        .borderRadius(15)
        .backgroundColor(color)
        .border({
          width: 3,
          color: this.editorColor() === color ? this.tk().primary : Color.Transparent
        })
    }
    .width('18%')
    .padding({ top: SPACE_TINY, bottom: SPACE_TINY })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.setEditorColor(color);
    })
  }

  // 实时迷你预览：与主题卡片预览同构，颜色随编辑器状态即时变化
  @Builder EditorMiniPreview() {
    Column({ space: 6 }) {
      Row({ space: SPACE_SMALL }) {
        Column()
          .width(10)
          .height(10)
          .borderRadius(5)
          .backgroundColor(this.editorPreview().primary)
        Column()
          .height(6)
          .width(52)
          .borderRadius(3)
          .backgroundColor(this.editorPreview().primaryContainer)
      }
      .width('100%')
      Column()
        .height(5)
        .width('100%')
        .borderRadius(2.5)
        .backgroundColor(this.editorPreview().surfaceVariant)
      Column()
        .height(5)
        .width('60%')
        .borderRadius(2.5)
        .backgroundColor(this.editorPreview().surfaceVariant)
      Row() {
        Column()
          .width(56)
          .height(10)
          .borderRadius(5)
          .backgroundColor(this.editorPreview().primary)
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding(SPACE_MEDIUM)
    .backgroundColor(this.editorPreview().background)
    .borderRadius(14)
    .border({ width: 1, color: this.editorPreview().outline })
  }

  // 编辑器浮层：遮罩点击关闭，卡片内容超高时可滚动
  @Builder CustomThemeEditorOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.tk().scrim)
        .onClick(() => {
          this.showCustomEditor = false;
        })
      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          Text($r('app.string.appearance_custom_editor_title'))
            .fontSize(this.fs(16))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tk().textPrimary)

          this.EditorMiniPreview()

          Text($r('app.string.appearance_custom_preset'))
            .fontSize(this.fs(12))
            .fontColor(this.tk().textSecondary)
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(CUSTOM_SWATCHES, (color: string) => {
              this.EditorSwatch(color)
            }, (color: string): string => 'editor_swatch_' + color)
          }
          .width('100%')

          // 色相滑杆：拖动实时联动预览
          Row({ space: SPACE_MEDIUM }) {
            Text($r('app.string.appearance_custom_hue'))
              .fontSize(this.fs(12))
              .fontColor(this.tk().textSecondary)
              .width(48)
            Slider({ value: this.editorH, min: 0, max: 360, step: 1, style: SliderStyle.InSet })
              .selectedColor(this.editorColor())
              .trackColor(this.tk().surfaceVariant)
              .blockColor(this.editorColor())
              .layoutWeight(1)
              .onChange((value: number) => {
                this.editorH = value;
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          // 饱和度滑杆
          Row({ space: SPACE_MEDIUM }) {
            Text($r('app.string.appearance_custom_saturation'))
              .fontSize(this.fs(12))
              .fontColor(this.tk().textSecondary)
              .width(48)
            Slider({ value: this.editorS, min: EDITOR_SAT_MIN, max: EDITOR_SAT_MAX, step: 0.01, style: SliderStyle.InSet })
              .selectedColor(this.editorColor())
              .trackColor(this.tk().surfaceVariant)
              .blockColor(this.editorColor())
              .layoutWeight(1)
              .onChange((value: number) => {
                this.editorS = value;
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          // 明度滑杆
          Row({ space: SPACE_MEDIUM }) {
            Text($r('app.string.appearance_custom_lightness'))
              .fontSize(this.fs(12))
              .fontColor(this.tk().textSecondary)
              .width(48)
            Slider({ value: this.editorL, min: EDITOR_LIGHT_MIN, max: EDITOR_LIGHT_MAX, step: 0.01, style: SliderStyle.InSet })
              .selectedColor(this.editorColor())
              .trackColor(this.tk().surfaceVariant)
              .blockColor(this.editorColor())
              .layoutWeight(1)
              .onChange((value: number) => {
                this.editorL = value;
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          // 操作按钮：取消 / 保存并应用
          Row({ space: SPACE_MEDIUM }) {
            Button($r('app.string.cancel'))
              .layoutWeight(1)
              .height(40)
              .fontSize(this.fs(14))
              .backgroundColor(this.tk().surfaceVariant)
              .fontColor(this.tk().textPrimary)
              .type(ButtonType.Normal)
              .borderRadius(SPACE_SMALL)
              .onClick(() => {
                this.showCustomEditor = false;
              })
            Button($r('app.string.appearance_custom_apply'))
              .layoutWeight(1)
              .height(40)
              .fontSize(this.fs(14))
              .backgroundColor(this.editorColor())
              .fontColor(Color.White)
              .type(ButtonType.Normal)
              .borderRadius(SPACE_SMALL)
              .onClick(() => {
                this.saveCustomTheme();
              })
          }
          .width('100%')
          .padding({ top: SPACE_SMALL })
        }
        .width('100%')
        .padding(SPACE_LARGE)
        .alignItems(HorizontalAlign.Start)
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .constraintSize({ maxHeight: '82%' })
      .width('86%')
      .backgroundColor(this.tk().surface)
      .borderRadius(RADIUS_CARD)
      .shadow({ radius: 24, color: this.tk().primaryShadow, offsetX: 0, offsetY: 8 })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
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

  @Builder HomeTab() {
    Column({ space: SPACE_LARGE }) {
      // 说明文案
      Text($r('app.string.appearance_home_scope_desc'))
        .fontSize(this.fs(13))
        .fontColor(this.tk().textSecondary)
        .lineHeight(this.fs(20))

      // 预览卡：按所选口径模拟首页顶部的汇总展示
      Column({ space: SPACE_MEDIUM }) {
        Text(this.homeScope === HOME_SCOPE_MONTH
          ? $r('app.string.month_expenses') : $r('app.string.day_expenses'))
          .fontSize(this.fs(12))
          .fontColor(this.tk().textSecondary)
          .opacity(0.7)
        Text('¥ 1,280.00')
          .fontSize(this.fs(36))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tk().primary)
        Row({ space: SPACE_MEDIUM }) {
          Row({ space: SPACE_TINY }) {
            Text(this.homeScope === HOME_SCOPE_MONTH
              ? $r('app.string.home_income_label') : $r('app.string.day_income_label'))
              .fontSize(this.fs(12))
              .fontColor(this.tk().textSecondary)
              .opacity(0.7)
            Text('¥ 3,200.00')
              .fontSize(this.fs(14))
              .fontColor(this.tk().textPrimary)
          }.alignItems(VerticalAlign.Center)
          Text(this.homeScope === HOME_SCOPE_MONTH
            ? $r('app.string.month_balance_label') : $r('app.string.day_balance_label'))
            .fontSize(this.fs(12))
            .fontColor(this.tk().primary)
            .padding({ left: SPACE_SMALL, right: SPACE_SMALL, top: SPACE_TINY, bottom: SPACE_TINY })
            .backgroundColor(this.tk().primarySoft)
            .borderRadius(999)
        }.alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding(SPACE_LARGE)
      .backgroundColor(this.tk().surface)
      .borderRadius(RADIUS_CARD)
      .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
      .alignItems(HorizontalAlign.Start)

      // 口径分段：按日 / 按月
      Row() {
        Text($r('app.string.appearance_home_scope_day'))
          .fontSize(this.fs(13))
          .fontWeight(this.homeScope === HOME_SCOPE_DAY ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.homeScope === HOME_SCOPE_DAY ? this.tk().onPrimary : this.tk().textSecondary)
          .padding({ top: 8, bottom: 8, left: SPACE_LARGE, right: SPACE_LARGE })
          .backgroundColor(this.homeScope === HOME_SCOPE_DAY ? this.tk().primary : Color.Transparent)
          .borderRadius(999)
          .onClick(() => {
            this.selectHomeScope(HOME_SCOPE_DAY);
          })
        Text($r('app.string.appearance_home_scope_month'))
          .fontSize(this.fs(13))
          .fontWeight(this.homeScope === HOME_SCOPE_MONTH ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.homeScope === HOME_SCOPE_MONTH ? this.tk().onPrimary : this.tk().textSecondary)
          .padding({ top: 8, bottom: 8, left: SPACE_LARGE, right: SPACE_LARGE })
          .backgroundColor(this.homeScope === HOME_SCOPE_MONTH ? this.tk().primary : Color.Transparent)
          .borderRadius(999)
          .onClick(() => {
            this.selectHomeScope(HOME_SCOPE_MONTH);
          })
      }
      .width('100%')
      .padding(4)
      .backgroundColor(this.tk().surfaceVariant)
      .borderRadius(999)
      .justifyContent(FlexAlign.Center)

      // 分隔线：区分“汇总口径”与“底部页签”两组设置
      Divider()
        .color(this.tk().surfaceVariant)
        .width('100%')

      // 底部页签：第二个页签可切换为 AI 助手或账本
      Text($r('app.string.appearance_second_tab_section'))
        .fontSize(this.fs(13))
        .fontColor(this.tk().textSecondary)

      // 预览卡：模拟底部导航栏，第二个页签按所选样式实时变化
      Row() {
        this.SecondTabPreviewItem($r('app.media.home'), $r('app.string.home'), false)
        this.SecondTabPreviewLedgerItem()
        Column() {
          Text('+')
            .fontSize(this.fs(13))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tk().onPrimary)
        }
        .width(30)
        .height(30)
        .borderRadius(15)
        .backgroundColor(this.tk().primary)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        this.SecondTabPreviewItem($r('app.media.stats'), $r('app.string.statistics'), false)
        this.SecondTabPreviewItem($r('app.media.settings'), $r('app.string.settings'), false)
      }
      .width('100%')
      .padding({ top: SPACE_MEDIUM, bottom: SPACE_MEDIUM })
      .backgroundColor(this.tk().surface)
      .borderRadius(RADIUS_CARD)
      .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
      .justifyContent(FlexAlign.SpaceEvenly)

      // 样式分段：AI 助手 / 账本
      Row() {
        Text($r('app.string.ai_assistant'))
          .fontSize(this.fs(13))
          .fontWeight(this.secondTab === SECOND_TAB_STYLE_AI ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.secondTab === SECOND_TAB_STYLE_AI ? this.tk().onPrimary : this.tk().textSecondary)
          .padding({ top: 8, bottom: 8, left: SPACE_LARGE, right: SPACE_LARGE })
          .backgroundColor(this.secondTab === SECOND_TAB_STYLE_AI ? this.tk().primary : Color.Transparent)
          .borderRadius(999)
          .onClick(() => {
            this.selectSecondTab(SECOND_TAB_STYLE_AI);
          })
        Text($r('app.string.ledger'))
          .fontSize(this.fs(13))
          .fontWeight(this.secondTab === SECOND_TAB_STYLE_LEDGER ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.secondTab === SECOND_TAB_STYLE_LEDGER ? this.tk().onPrimary : this.tk().textSecondary)
          .padding({ top: 8, bottom: 8, left: SPACE_LARGE, right: SPACE_LARGE })
          .backgroundColor(this.secondTab === SECOND_TAB_STYLE_LEDGER ? this.tk().primary : Color.Transparent)
          .borderRadius(999)
          .onClick(() => {
            this.selectSecondTab(SECOND_TAB_STYLE_LEDGER);
          })
      }
      .width('100%')
      .padding(4)
      .backgroundColor(this.tk().surfaceVariant)
      .borderRadius(999)
      .justifyContent(FlexAlign.Center)

      // 分隔线：区分“底部页签”与“账本行为”两组设置
      Divider()
        .color(this.tk().surfaceVariant)
        .width('100%')

      // 账本行为：记一笔/图片识别入账时是否默认同步计入主账单
      Text($r('app.string.ledger'))
        .fontSize(this.fs(13))
        .fontColor(this.tk().textSecondary)

      Row({ space: SPACE_MEDIUM }) {
        Column({ space: 2 }) {
          Text($r('app.string.settings_ledger_sync'))
            .fontSize(this.fs(14))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tk().textPrimary)
          Text($r('app.string.settings_ledger_sync_desc'))
            .fontSize(this.fs(11))
            .fontColor(this.tk().textSecondary)
            .lineHeight(this.fs(16))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.ledgerSyncDefault })
          .selectedColor(this.tk().primary)
          .onChange((isOn: boolean) => {
            this.setLedgerSyncDefault(isOn);
          })
      }
      .width('100%')
      .padding(SPACE_LARGE)
      .backgroundColor(this.tk().surface)
      .borderRadius(RADIUS_CARD)
      .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 底部页签预览的单个迷你页签项：被自定义的第二个页签高亮
  @Builder SecondTabPreviewItem(icon: ResourceStr, label: ResourceStr, highlight: boolean) {
    Column({ space: 2 }) {
      Image(icon)
        .width(16)
        .height(16)
        .fillColor(highlight ? this.tk().primary : this.tk().textSecondary)
      Text(label)
        .fontSize(this.fs(9))
        .fontColor(highlight ? this.tk().primary : this.tk().textSecondary)
    }
    .justifyContent(FlexAlign.Center)
  }

  // 第二页签的迷你预览：@Builder 按值传参不随状态刷新，图标/文案必须在 Builder 体内直读状态
  @Builder SecondTabPreviewLedgerItem() {
    Column({ space: 2 }) {
      Image(this.secondTab === SECOND_TAB_STYLE_LEDGER ? $r('app.media.ledger') : $r('app.media.ai'))
        .width(16)
        .height(16)
        .fillColor(this.tk().primary)
      Text(this.secondTab === SECOND_TAB_STYLE_LEDGER ? $r('app.string.ledger') : $r('app.string.ai_assistant'))
        .fontSize(this.fs(9))
        .fontColor(this.tk().primary)
    }
    .justifyContent(FlexAlign.Center)
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
