import dayjs from 'dayjs';
import { StatsType } from '../../models/stats/stats';
import { SPACE_MEDIUM } from '../../common/dimens';
import { ThemeKit, ThemePalette } from '../../common/theme/Theme';

interface MonthCell {
  month: number;
  label: string;
  enabled: boolean;
}

/**
 * 时间段选择弹窗：
 * 月账单模式 = 年份箭头 + 12 宫格月份；
 * 年账单模式 = 年份宫格。点选即生效并关闭。
 */
@CustomDialog
export default struct PeriodPickerDialog {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  controller: CustomDialogController;
  mode: StatsType = StatsType.MONTH;
  time: number = 0;
  // 可选的晚绑定取值：弹窗每次打开时读取调用方最新选中时间，
  // 避免控制器构造时一次性绑定 time 导致重开弹窗显示旧值
  getTime?: () => number;
  minYear: number = 0;
  onChange?: (time: number) => void;
  // 弹窗内正在浏览的年份：不直接改 time，点选月份/年份才生效
  @State viewYear: number = 0;

  aboutToAppear(): void {
    if (this.getTime) {
      this.time = this.getTime();
    }
    this.viewYear = dayjs(this.time).year();
  }

  maxYear(): number {
    return dayjs().year();
  }

  canPrevYear(): boolean {
    return this.viewYear > this.minYear;
  }

  canNextYear(): boolean {
    return this.viewYear < this.maxYear();
  }

  stepYear(delta: number): void {
    const target = this.viewYear + delta;
    if (target < this.minYear || target > this.maxYear()) {
      return;
    }
    this.viewYear = target;
  }

  // 12 个月宫格：浏览到今年时，未来月份禁用
  monthCells(): MonthCell[] {
    const cells: MonthCell[] = [];
    const now = dayjs();
    for (let m = 0; m < 12; m++) {
      const enabled = !(this.viewYear === now.year() && m > now.month());
      const cell: MonthCell = { month: m, label: `${m + 1}月`, enabled: enabled };
      cells.push(cell);
    }
    return cells;
  }

  isMonthSelected(month: number): boolean {
    return this.viewYear === dayjs(this.time).year() && month === dayjs(this.time).month();
  }

  yearCells(): number[] {
    const cells: number[] = [];
    for (let y = this.maxYear(); y >= this.minYear; y--) {
      cells.push(y);
    }
    return cells;
  }

  yearGridHeight(): number {
    const rows = Math.ceil(this.yearCells().length / 3);
    if (rows <= 0) {
      return 0;
    }
    return rows * 40 + (rows - 1) * 10;
  }

  pickMonth(month: number): void {
    const newTime = dayjs(this.time).set('year', this.viewYear).set('month', month).valueOf();
    if (this.onChange) {
      this.onChange(newTime);
    }
    this.controller?.close();
  }

  pickYear(year: number): void {
    const newTime = dayjs(this.time).set('year', year).valueOf();
    if (this.onChange) {
      this.onChange(newTime);
    }
    this.controller?.close();
  }

  build() {
    Column({ space: SPACE_MEDIUM }) {
      Text(this.mode === StatsType.MONTH ? '选择月份' : '选择年份')
        .width('100%')
        .textAlign(TextAlign.Center)
        .fontSize(this.fs(16))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tk().textPrimary)

      if (this.mode === StatsType.MONTH) {
        // 年份左右切换
        Row() {
          Image($r('app.media.arrow_left'))
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
            .fillColor(this.tk().textPrimary)
            .opacity(this.canPrevYear() ? 0.9 : 0.3)
            .onClick(() => {
              this.stepYear(-1);
            })
          Blank()
          Text(`${this.viewYear}年`)
            .fontSize(this.fs(16))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tk().textPrimary)
          Blank()
          Image($r('app.media.arrow_left'))
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
            .rotate({ angle: 180 })
            .fillColor(this.tk().textPrimary)
            .opacity(this.canNextYear() ? 0.9 : 0.3)
            .onClick(() => {
              this.stepYear(1);
            })
        }
        .width('100%')

        Grid() {
          ForEach(this.monthCells(), (cell: MonthCell) => {
            GridItem() {
              Text(cell.label)
                .fontSize(this.fs(15))
                .fontWeight(this.isMonthSelected(cell.month) ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.isMonthSelected(cell.month) ? this.tk().primary : this.tk().textPrimary)
                .textAlign(TextAlign.Center)
                .width('100%')
                .height(40)
                .backgroundColor(this.isMonthSelected(cell.month) ? this.tk().primarySoft : this.tk().surfaceVariant)
                .borderRadius(10)
                .opacity(cell.enabled ? 1 : 0.35)
                .onClick(() => {
                  if (cell.enabled) {
                    this.pickMonth(cell.month);
                  }
                })
            }
          }, (cell: MonthCell) => cell.month.toString() + '_' + this.viewYear.toString())
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .columnsGap(10)
        .rowsGap(10)
        .width('100%')
        .height(140)
      } else {
        Grid() {
          ForEach(this.yearCells(), (year: number) => {
            GridItem() {
              Text(`${year}年`)
                .fontSize(this.fs(15))
                .fontWeight(year === dayjs(this.time).year() ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(year === dayjs(this.time).year() ? this.tk().primary : this.tk().textPrimary)
                .textAlign(TextAlign.Center)
                .width('100%')
                .height(40)
                .backgroundColor(year === dayjs(this.time).year() ? this.tk().primarySoft : this.tk().surfaceVariant)
                .borderRadius(10)
                .onClick(() => {
                  this.pickYear(year);
                })
            }
          }, (year: number) => year.toString())
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(10)
        .rowsGap(10)
        .width('100%')
        .height(this.yearGridHeight())
      }

      Button($r('app.string.cancel'))
        .width('100%')
        .height(40)
        .fontSize(this.fs(15))
        .fontColor(this.tk().textSecondary)
        .backgroundColor(this.tk().surfaceVariant)
        .type(ButtonType.Normal)
        .borderRadius(20)
        .onClick(() => {
          this.controller?.close();
        })
    }
    .width('78%')
    .padding({ left: 20, right: 20, top: 20, bottom: 16 })
    .borderRadius(20)
    .backgroundColor(this.tk().surface)
  }
}
