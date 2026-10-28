import { ThemePalette } from '../../common/theme/Theme';

/**
 * 账本颜色 key → 当前主题 accent 色
 */
export function ledgerAccent(tk: ThemePalette, key: string): string {
  switch (key) {
    case 'blue':
      return tk.accentBlue;
    case 'yellow':
      return tk.accentYellow;
    case 'orange':
      return tk.accentOrange;
    case 'red':
      return tk.accentRed;
    case 'purple':
      return tk.accentPurple;
    case 'green':
    default:
      return tk.accentGreen;
  }
}

/**
 * 账本颜色 key → 当前主题 accent 柔和底色
 */
export function ledgerAccentSoft(tk: ThemePalette, key: string): string {
  switch (key) {
    case 'blue':
      return tk.accentBlueSoft;
    case 'yellow':
      return tk.accentYellowSoft;
    case 'orange':
      return tk.accentOrangeSoft;
    case 'red':
      return tk.accentRedSoft;
    case 'purple':
      return tk.accentPurpleSoft;
    case 'green':
    default:
      return tk.accentGreenSoft;
  }
}
