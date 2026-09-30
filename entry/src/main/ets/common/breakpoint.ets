export interface BreakpointTypeOptions<T> {
  sm: T;
  md: T;
  lg: T;
}

export class BreakpointType<T> {
  options: BreakpointTypeOptions<T>;

  constructor(options: BreakpointTypeOptions<T>) {
    this.options = options;
  }

  getValue(breakpoint: string): T {
    if (breakpoint === 'sm') {
      return this.options.sm;
    }
    if (breakpoint === 'md') {
      return this.options.md;
    }
    return this.options.lg;
  }
}

export default class BreakpointConstants {
  /**
   * 小屏幕设备的 BreakPoints 标记
   */
  static readonly BREAKPOINT_SM: string = 'sm';

  /**
   * 中等设备的 Breakpoint 标记
   */
  static readonly BREAKPOINT_MD: string = 'md';

  /**
   * 大屏设备的 Breakpoints 标记
   */
  static readonly BREAKPOINT_LG: string = 'lg';

  /**
   * 当前设备的 Breakpoints 标记 存储的 key
   */
  static readonly CURRENT_BREAKPOINT: string = 'currentBreakpoint';

  /**
   * 小屏设备宽度范围
   */
  static readonly RANGE_SM: string = '(320vp<=width<600vp)';

  /**
   * 中屏设备宽度范围
   */
  static readonly RANGE_MD: string = '(600vp<=width<840vp)';

  /**
   * 大屏幕设备宽度范围
   */
  static readonly RANGE_LG: string = '(840vp<=width)';

  /**
   * 不同设备下的bar位置
   */
  static readonly bar_position: BreakpointType<BarPosition> = new BreakpointType<BarPosition>({
    sm: BarPosition.End,
    md: BarPosition.Start,
    lg: BarPosition.Start,
  });

  /**
   * 不同尺寸设备的 bar 是否垂直
   */
  static readonly bar_vertical: BreakpointType<boolean> = new BreakpointType<boolean>({
    sm: false,
    md: true,
    lg: true,
  });

  static readonly addBtn_stack_align: BreakpointType<Alignment> = new BreakpointType<Alignment>({
    sm: Alignment.Bottom,
    md: Alignment.Start,
    lg: Alignment.Start,
  });

  static readonly addBtn_stack_size: BreakpointType<number> = new BreakpointType<number>({
    sm: 60,
    md: 100,
    lg: 120,
  });

  /**
   * 不同尺寸设备 stats 统计数据展示数量
   */
  static readonly max_content_size: BreakpointType<Length> = new BreakpointType<Length>({
    sm: '100%',
    md: '80%',
    lg: '60%',
  })
}
