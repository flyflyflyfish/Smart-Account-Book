/**
 * 运行时主题系统：6 套主题 × 浅/深双套调色板 + 字号缩放。
 * 所有 UI 颜色统一经 ThemePalette 令牌获取；切换主题/模式/字号时
 * 通过递增 AppStorage 中的 themeSeq 触发全局细粒度刷新。
 */
import common from '@ohos.app.ability.common';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import resourceManager from '@ohos.resourceManager';
import PreferenceUtil from '../../utils/PreferenceUtil';
import { PREF_THEME_ID, PREF_COLOR_MODE, PREF_FONT_SCALE, PREF_GLOW_LEVEL } from '../constants';

// 主题 id
export const THEME_ID_PINE: string = 'pine';
export const THEME_ID_CLAUDE: string = 'claude';
export const THEME_ID_SKY: string = 'sky';
export const THEME_ID_VIOLET: string = 'violet';
export const THEME_ID_NOTION: string = 'notion';
export const THEME_ID_STONE: string = 'stone';
export const THEME_ID_LIST: string[] = [
  THEME_ID_PINE, THEME_ID_CLAUDE, THEME_ID_SKY, THEME_ID_VIOLET, THEME_ID_NOTION, THEME_ID_STONE
];

// 深浅色模式
export const THEME_MODE_SYSTEM: string = 'system';
export const THEME_MODE_LIGHT: string = 'light';
export const THEME_MODE_DARK: string = 'dark';

// 字号缩放档位：小 / 默认 / 大 / 特大
export const FONT_SCALE_SMALL: number = 0.85;
export const FONT_SCALE_DEFAULT: number = 1.0;
export const FONT_SCALE_LARGE: number = 1.15;
export const FONT_SCALE_XLARGE: number = 1.3;
export const FONT_SCALE_OPTIONS: number[] = [
  FONT_SCALE_SMALL, FONT_SCALE_DEFAULT, FONT_SCALE_LARGE, FONT_SCALE_XLARGE
];

// 光感（阴影浓度）档位：柔和 / 标准 / 浓郁
export const GLOW_LEVEL_SOFT: string = 'soft';
export const GLOW_LEVEL_STANDARD: string = 'standard';
export const GLOW_LEVEL_STRONG: string = 'strong';

function hexToRgb(hex: string): number[] {
  const clean = hex.startsWith('#') ? hex.substring(1) : hex;
  return [
    parseInt(clean.substring(0, 2), 16),
    parseInt(clean.substring(2, 4), 16),
    parseInt(clean.substring(4, 6), 16)
  ];
}

function rgbToHex(r: number, g: number, b: number): string {
  const part = (v: number): string => {
    const clamped = Math.min(255, Math.max(0, Math.round(v)));
    const text = clamped.toString(16);
    return text.length === 1 ? '0' + text : text;
  };
  return '#' + part(r) + part(g) + part(b);
}

function mixColorHex(base: string, target: string, ratio: number): string {
  const a = hexToRgb(base);
  const b = hexToRgb(target);
  return rgbToHex(
    a[0] + (b[0] - a[0]) * ratio,
    a[1] + (b[1] - a[1]) * ratio,
    a[2] + (b[2] - a[2]) * ratio
  );
}

function withAlpha(hex: string, alpha: number): string {
  const value = Math.round(alpha * 255);
  const text = value.toString(16);
  const alphaHex = text.length === 1 ? '0' + text : text;
  return '#' + alphaHex + hex.substring(1);
}

/** 按光感档位计算卡片阴影色：柔和 / 标准 / 浓郁 */
export function glowShadowColor(primary: string, isDark: boolean, level: string): string {
  if (isDark) {
    if (level === GLOW_LEVEL_SOFT) {
      return '#26000000';
    }
    if (level === GLOW_LEVEL_STRONG) {
      return '#66000000';
    }
    return '#4D000000';
  }
  if (level === GLOW_LEVEL_SOFT) {
    return withAlpha(primary, 0.12);
  }
  if (level === GLOW_LEVEL_STRONG) {
    return withAlpha(primary, 0.4);
  }
  return withAlpha(primary, 0.24);
}

/** 调色板种子：仅主题差异化字段，其余中性色按明暗统一推导 */
interface ThemeSeed {
  primary: string;
  container: string;
  bg: string;
  surface: string;
  isDark: boolean;
}

function hexToHsl(hex: string): number[] {
  const rgb = hexToRgb(hex);
  const r = rgb[0] / 255;
  const g = rgb[1] / 255;
  const b = rgb[2] / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  let h = 0;
  let s = 0;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max === r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (max === g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h *= 60;
  }
  return [h, s, l];
}

function hslToHex(h: number, s: number, l: number): string {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const hp = (((h % 360) + 360) % 360) / 60;
  const x = c * (1 - Math.abs(hp % 2 - 1));
  let r = 0;
  let g = 0;
  let b = 0;
  if (hp < 1) {
    r = c;
    g = x;
  } else if (hp < 2) {
    r = x;
    g = c;
  } else if (hp < 3) {
    g = c;
    b = x;
  } else if (hp < 4) {
    g = x;
    b = c;
  } else if (hp < 5) {
    r = x;
    b = c;
  } else {
    r = c;
    b = x;
  }
  const m = l - c / 2;
  return rgbToHex((r + m) * 255, (g + m) * 255, (b + m) * 255);
}

/**
 * 图表分类色：以主色为锚的和谐多色板。
 * 首色固定为主色，其余按色相环绕展开（邻色 + 互补色），
 * 饱和度继承主色气质、明度逐档抬升，避免整屏单色深浅的呆板感。
 */
function buildChartPalette(primary: string, isDark: boolean): string[] {
  const hsl = hexToHsl(primary);
  const baseH = hsl[0];
  const baseS = hsl[1];
  const offsets: number[] = [0, 32, -38, 70, 178, -74];
  const sat = Math.min(0.6, Math.max(0.34, baseS * 0.95));
  const baseL = isDark ? 0.6 : 0.45;
  const lStep = isDark ? 0.045 : 0.038;
  const palette: string[] = [primary];
  for (let i = 1; i < offsets.length; i++) {
    const hue = (baseH + offsets[i] + 360) % 360;
    const l = Math.min(isDark ? 0.72 : 0.56, baseL + i * lStep);
    palette.push(hslToHex(hue, Math.max(0.3, sat - i * 0.02), l));
  }
  return palette;
}

export class ThemePalette {
  isDark: boolean;
  primary: string;
  onPrimary: string;
  primaryContainer: string;
  onPrimaryContainer: string;
  primarySoft: string;
  primaryShadow: string;
  background: string;
  surface: string;
  surfaceVariant: string;
  outline: string;
  textPrimary: string;
  textSecondary: string;
  success: string;
  successSoft: string;
  danger: string;
  dangerSoft: string;
  warning: string;
  toastBg: string;
  toastText: string;
  scrim: string;
  accentGreen: string;
  accentBlue: string;
  accentYellow: string;
  accentOrange: string;
  accentRed: string;
  accentPurple: string;
  accentGreenSoft: string;
  accentBlueSoft: string;
  accentYellowSoft: string;
  accentOrangeSoft: string;
  accentRedSoft: string;
  accentPurpleSoft: string;
  chart: string[];

  constructor(seed: ThemeSeed) {
    this.isDark = seed.isDark;
    this.primary = seed.primary;
    this.primaryContainer = seed.container;
    this.background = seed.bg;
    this.surface = seed.surface;
    if (seed.isDark) {
      this.onPrimary = mixColorHex(seed.primary, '#000000', 0.55);
      this.onPrimaryContainer = mixColorHex(seed.primary, '#FFFFFF', 0.45);
      this.primarySoft = withAlpha(seed.primary, 0.28);
      this.primaryShadow = '#4D000000';
      this.surfaceVariant = mixColorHex(seed.surface, '#E8EBE6', 0.08);
      this.outline = mixColorHex(seed.surface, '#DDE1DC', 0.18);
      this.textPrimary = '#EAEEEA';
      this.textSecondary = '#A2AAA3';
      this.success = '#7CC3A0';
      this.successSoft = withAlpha('#7CC3A0', 0.24);
      this.danger = '#E08A80';
      this.dangerSoft = withAlpha('#E08A80', 0.24);
      this.warning = '#D9AC6B';
      this.toastBg = '#E6262626';
      this.scrim = '#66000000';
      this.accentGreen = mixColorHex('#2EB877', '#FFFFFF', 0.22);
      this.accentBlue = mixColorHex('#3D94F0', '#FFFFFF', 0.22);
      this.accentYellow = mixColorHex('#F0B32E', '#FFFFFF', 0.22);
      this.accentOrange = mixColorHex('#F28C3B', '#FFFFFF', 0.22);
      this.accentRed = mixColorHex('#EC6050', '#FFFFFF', 0.22);
      this.accentPurple = mixColorHex('#9C70E4', '#FFFFFF', 0.22);
    } else {
      this.onPrimary = '#FFFFFF';
      this.onPrimaryContainer = mixColorHex(seed.primary, '#000000', 0.35);
      this.primarySoft = withAlpha(seed.primary, 0.16);
      this.primaryShadow = withAlpha(seed.primary, 0.24);
      this.surfaceVariant = mixColorHex(seed.bg, '#3A3F3C', 0.10);
      this.outline = mixColorHex(seed.bg, '#2A2E2B', 0.20);
      this.textPrimary = mixColorHex('#171A18', seed.primary, 0.05);
      this.textSecondary = mixColorHex('#5F6660', seed.primary, 0.08);
      this.success = '#3E8E68';
      this.successSoft = withAlpha('#3E8E68', 0.16);
      this.danger = '#C4534A';
      this.dangerSoft = withAlpha('#C4534A', 0.14);
      this.warning = '#BF8A42';
      this.toastBg = '#E61F1F1F';
      this.scrim = '#66000000';
      this.accentGreen = '#2EB877';
      this.accentBlue = '#3D94F0';
      this.accentYellow = '#F0B32E';
      this.accentOrange = '#F28C3B';
      this.accentRed = '#EC6050';
      this.accentPurple = '#9C70E4';
    }
    this.toastText = '#F5F6F5';
    const accentSoftAlpha = seed.isDark ? 0.22 : 0.16;
    this.accentGreenSoft = withAlpha(this.accentGreen, accentSoftAlpha);
    this.accentBlueSoft = withAlpha(this.accentBlue, accentSoftAlpha);
    this.accentYellowSoft = withAlpha(this.accentYellow, accentSoftAlpha);
    this.accentOrangeSoft = withAlpha(this.accentOrange, accentSoftAlpha);
    this.accentRedSoft = withAlpha(this.accentRed, accentSoftAlpha);
    this.accentPurpleSoft = withAlpha(this.accentPurple, accentSoftAlpha);
    this.chart = buildChartPalette(seed.primary, seed.isDark);
  }

  /** 分类颜色 key（green/blue/yellow/orange/red/purple）→ 当前主题下的低饱和 accent */
  accent(key: string): string {
    switch (key) {
      case 'blue':
        return this.accentBlue;
      case 'yellow':
        return this.accentYellow;
      case 'orange':
        return this.accentOrange;
      case 'red':
        return this.accentRed;
      case 'purple':
        return this.accentPurple;
      case 'green':
      default:
        return this.accentGreen;
    }
  }
}

interface ThemeEntry {
  id: string;
  light: ThemePalette;
  dark: ThemePalette;
}

function buildEntry(id: string, lightSeed: ThemeSeed, darkSeed: ThemeSeed): ThemeEntry {
  const light: ThemeSeed = {
    primary: lightSeed.primary,
    container: lightSeed.container,
    bg: lightSeed.bg,
    surface: '#FCFBF8',
    isDark: false
  };
  const dark: ThemeSeed = {
    primary: darkSeed.primary,
    container: darkSeed.container,
    bg: darkSeed.bg,
    surface: darkSeed.surface,
    isDark: true
  };
  const entry: ThemeEntry = {
    id: id,
    light: new ThemePalette(light),
    dark: new ThemePalette(dark)
  };
  return entry;
}

const THEME_ENTRIES: ThemeEntry[] = [
  // 松雾绿（默认）
  buildEntry(THEME_ID_PINE,
    { primary: '#2E9E73', container: '#D7F0E4', bg: '#F3F5F4', surface: '', isDark: false },
    { primary: '#6FCB9F', container: '#1F382C', bg: '#101711', surface: '#181F19', isDark: true }),
  // Claude 暖棕
  buildEntry(THEME_ID_CLAUDE,
    { primary: '#C46A35', container: '#F7DFC8', bg: '#F7F5F1', surface: '', isDark: false },
    { primary: '#E09A6B', container: '#33261D', bg: '#161210', surface: '#201914', isDark: true }),
  // 清爽蓝
  buildEntry(THEME_ID_SKY,
    { primary: '#3B82D6', container: '#DAEAFB', bg: '#F3F5F7', surface: '', isDark: false },
    { primary: '#7FB3EE', container: '#1C2A3C', bg: '#0F1318', surface: '#161B23', isDark: true }),
  // 雾紫
  buildEntry(THEME_ID_VIOLET,
    { primary: '#8A63C2', container: '#ECE1F9', bg: '#F5F4F7', surface: '', isDark: false },
    { primary: '#B398DC', container: '#292038', bg: '#120F17', surface: '#191521', isDark: true }),
  // Notion 极简
  buildEntry(THEME_ID_NOTION,
    { primary: '#37352F', container: '#E9E7E2', bg: '#F4F4F2', surface: '', isDark: false },
    { primary: '#E0DED8', container: '#2A2925', bg: '#121212', surface: '#1A1A1A', isDark: true }),
  // 曜石黑
  buildEntry(THEME_ID_STONE,
    { primary: '#1C1C1E', container: '#E9E9EC', bg: '#F4F4F5', surface: '', isDark: false },
    { primary: '#C2C2CA', container: '#232328', bg: '#0A0A0B', surface: '#141416', isDark: true })
];

/** 指定主题 + 深浅色的调色板（卡片 FormAbility 等非组件进程使用） */
export function resolveThemePalette(id: string, dark: boolean): ThemePalette {
  return resolvePalette(id, dark);
}

/** 纯调色板解析（内部实现） */
function resolvePalette(id: string, dark: boolean): ThemePalette {
  const matched = THEME_ENTRIES.find((entry: ThemeEntry): boolean => entry.id === id);
  if (matched) {
    return dark ? matched.dark : matched.light;
  }
  const fallback = THEME_ENTRIES[0];
  return dark ? fallback.dark : fallback.light;
}

class ThemeManager {
  private themeId: string = THEME_ID_PINE;
  private mode: string = THEME_MODE_SYSTEM;
  private systemDark: boolean = false;
  private fontScale: number = FONT_SCALE_DEFAULT;
  private glowLevel: string = GLOW_LEVEL_STANDARD;
  private seq: number = 0;
  private appContext: common.ApplicationContext | undefined = undefined;

  async init(context: common.Context): Promise<void> {
    this.appContext = context.getApplicationContext();
    const savedId = await PreferenceUtil.getPreferenceValue(PREF_THEME_ID, THEME_ID_PINE);
    if (typeof savedId === 'string') {
      this.themeId = savedId;
    }
    const savedMode = await PreferenceUtil.getPreferenceValue(PREF_COLOR_MODE, THEME_MODE_SYSTEM);
    if (typeof savedMode === 'string') {
      this.mode = savedMode;
    }
    const savedScale = await PreferenceUtil.getPreferenceValue(PREF_FONT_SCALE, FONT_SCALE_DEFAULT);
    if (typeof savedScale === 'number') {
      this.fontScale = savedScale;
    }
    const savedGlow = await PreferenceUtil.getPreferenceValue(PREF_GLOW_LEVEL, GLOW_LEVEL_STANDARD);
    if (typeof savedGlow === 'string') {
      this.glowLevel = savedGlow;
    }
    this.systemDark = this.readSystemDark(context);
    AppStorage.setOrCreate('themeSeq', 0);
    this.applyColorMode();
  }

  private readSystemDark(context: common.Context): boolean {
    try {
      const conf = context.resourceManager.getConfigurationSync();
      return conf.colorMode === resourceManager.ColorMode.DARK;
    } catch (err) {
      return false;
    }
  }

  private applyColorMode(): void {
    if (!this.appContext) {
      return;
    }
    if (this.mode === THEME_MODE_DARK) {
      this.appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (this.mode === THEME_MODE_LIGHT) {
      this.appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } else {
      this.appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
  }

  /** seq 参数用于让组件在 build 中建立对 themeSeq 的状态依赖，实现主题切换细粒度刷新 */
  palette(seq: number = 0): ThemePalette {
    const dark = this.mode === THEME_MODE_DARK || (this.mode === THEME_MODE_SYSTEM && this.systemDark);
    const resolved = resolvePalette(this.themeId, dark);
    // 光感档位实时套用到阴影色（缓存实例上原地更新，bump 后全局重读）
    resolved.primaryShadow = glowShadowColor(resolved.primary, resolved.isDark, this.glowLevel);
    return resolved;
  }

  accent(key: string): string {
    return this.palette().accent(key);
  }

  /** 字号缩放：按当前倍率缩放基准字号，保留一位小数；seq 参数用于建立组件状态依赖 */
  fontScaled(base: number, seq: number = 0): number {
    return Math.round(base * this.fontScale * 10) / 10;
  }

  setThemeId(id: string): void {
    this.themeId = id;
    PreferenceUtil.putPreferenceValue(PREF_THEME_ID, id);
    this.bump();
  }

  setMode(mode: string): void {
    this.mode = mode;
    PreferenceUtil.putPreferenceValue(PREF_COLOR_MODE, mode);
    this.applyColorMode();
    this.bump();
  }

  setFontScale(scale: number): void {
    this.fontScale = scale;
    PreferenceUtil.putPreferenceValue(PREF_FONT_SCALE, scale);
    this.bump();
  }

  setGlowLevel(level: string): void {
    this.glowLevel = level;
    PreferenceUtil.putPreferenceValue(PREF_GLOW_LEVEL, level);
    this.bump();
  }

  /** 系统深浅色变化（跟随系统模式时联动） */
  onSystemColorModeChanged(colorMode: ConfigurationConstant.ColorMode): void {
    const dark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    if (dark === this.systemDark) {
      return;
    }
    this.systemDark = dark;
    if (this.mode === THEME_MODE_SYSTEM) {
      this.applyColorMode();
      this.bump();
    }
  }

  private bump(): void {
    this.seq += 1;
    AppStorage.setOrCreate('themeSeq', this.seq);
  }

  currentThemeId(): string {
    return this.themeId;
  }

  currentMode(): string {
    return this.mode;
  }

  currentFontScale(): number {
    return this.fontScale;
  }

  currentGlowLevel(): string {
    return this.glowLevel;
  }

  /** 导出文档（HTML/PDF/Word）用调色板：固定取当前主题浅色套，保证打印可读性 */
  lightPalette(): ThemePalette {
    return resolvePalette(this.themeId, false);
  }

  /** 指定主题的浅色调色板，供主题选择卡片预览 */
  previewPalette(id: string): ThemePalette {
    return resolvePalette(id, false);
  }
}

export const ThemeKit = new ThemeManager();

/** 非组件模块（模型/服务）获取当前调色板 */
export function currentThemePalette(): ThemePalette {
  return ThemeKit.palette();
}
