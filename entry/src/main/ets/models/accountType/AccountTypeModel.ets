import { ThemeKit } from '../../common/theme/Theme';

/**
 * 支持类型
 */
export default class AccountTypeModel {
  /**
   * id
   */
  id: number;
  /**
   * 名称
   */
  name: ResourceStr;
  /**
   * icon
   */
  icon: ResourceStr;
  /**
   * 颜色 key（green/blue/yellow/orange/red/purple），运行时经主题解析为低饱和 accent
   */
  colorKey: string;

  constructor(id: number, name: ResourceStr, icon: ResourceStr, colorKey: string) {
    this.id = id;
    this.name = name;
    this.icon = icon;
    this.colorKey = colorKey;
  }

  /**
   * 当前主题下的激活色（主题切换后自动跟随）
   */
  get activeColor(): string {
    return ThemeKit.accent(this.colorKey);
  }
}
