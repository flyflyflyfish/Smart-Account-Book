import dayjs from 'dayjs';
import { StatsType } from '../../models/stats/stats';
import PeriodPickerDialog from './PeriodPickerDialog';
import PreferenceUtil from '../../utils/PreferenceUtil';
import * as CONSTANTS from '../../common/constants';
import { SPACE_SMALL } from '../../common/dimens';
import { ThemeKit, ThemePalette } from '../../common/theme/Theme';

/**
 * 统计页头部：左侧时间段（点击弹窗选年月），右侧月账单/年账单切换。
 * 与首页日期选择行保持一致的视觉语言。
 */
@Component
export default struct StatsHeader {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }
  @Link @Watch('onTypeChange') type: StatsType;
  @Link time: number;
  private firstUseTime: number = 0;

  // 弹窗参数全部走晚绑定回调：控制器只构造一次，切换月/年账单或改过时间后
  // 重开弹窗必须读取最新值（构造时快照会显示旧模式/旧时间）
  periodController = new CustomDialogController({
    builder: PeriodPickerDialog({
      getMode: (): StatsType => this.type,
      getTime: (): number => this.time,
      getMinYear: (): number => this.minYear(),
      onChange: (picked: number) => {
        this.time = picked;
      }
    }),
    customStyle: true,
    alignment: DialogAlignment.Center
  })

  async aboutToAppear(): Promise<void> {
    this.firstUseTime = Number(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_USER_FIRST_KEY, 0));
  }

  // 切换月/年账单时回到当前月/年
  onTypeChange(): void {
    this.time = dayjs().valueOf();
  }

  // 年份可选下界：首次使用时间与“最近 5 年”取更早者
  minYear(): number {
    const currentYear = dayjs().year();
    const firstYear = this.firstUseTime > 0 ? dayjs(this.firstUseTime).year() : currentYear;
    return Math.min(firstYear, currentYear - 4);
  }

  periodLabel(): string {
    return this.type === StatsType.MONTH ? dayjs(this.time).format('YYYY年M月') : dayjs(this.time).format('YYYY年');
  }

  @Builder SegmentItem(label: ResourceStr, value: StatsType) {
    Text(label)
      .fontSize(this.fs(13))
      .lineHeight(this.fs(18))
      .fontWeight(this.type === value ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.type === value ? this.tk().primary : this.tk().textSecondary)
      .padding({ left: SPACE_SMALL + 6, right: SPACE_SMALL + 6, top: 6, bottom: 6 })
      .backgroundColor(this.type === value ? this.tk().surface : Color.Transparent)
      .borderRadius(SPACE_SMALL + 2)
      .onClick(() => {
        this.type = value;
      })
  }

  @Builder SegmentedControl() {
    Row({ space: 2 }) {
      this.SegmentItem($r('app.string.monthly_bill'), StatsType.MONTH)
      this.SegmentItem($r('app.string.annual_bill'), StatsType.YEAR)
    }
    .padding(2)
    .backgroundColor(this.tk().surfaceVariant)
    .borderRadius(SPACE_SMALL + 4)
  }

  build() {
    Row() {
      Row({ space: SPACE_SMALL }) {
        Text(this.periodLabel())
          .fontSize(this.fs(16))
          .lineHeight(this.fs(22))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().textPrimary)
        Image($r('app.media.arrow_down'))
          .width(14)
          .height(14)
          .objectFit(ImageFit.Contain)
          .fillColor(this.tk().textSecondary)
      }
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.periodController.open();
      })

      Blank()

      this.SegmentedControl()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
