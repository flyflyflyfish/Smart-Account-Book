import dayjs from 'dayjs';
import { StatsType } from '../../models/stats/stats';
import OptionsGridDialog from '../OptionsGridDialog';
import { OptionsItem } from '../../models/stats/StatsItem';
import PreferenceUtil from '../../utils/PreferenceUtil';
import * as CONSTANTS from '../../common/constants';
import { SPACE_SMALL, SPACE_TINY } from '../../common/dimens';

/**
 * 统计页头部：月账单/年账单用分段控件切换，年份、月份用下拉网格弹窗选择，
 * 替代原先循环滚动的 TextPicker 与费劲的横向月份列表
 */
@Component
export default struct StatsHeader {
  @Link @Watch('onTypeChange') type: StatsType;
  @Link time: number;
  private firstUseTime: number = 0;

  yearController = new CustomDialogController({
    builder: OptionsGridDialog({
      title: '选择年份',
      options: this.yearOptions(),
      onChange: (year: number) => {
        this.time = dayjs(this.time).set('year', year).valueOf();
      }
    }),
    customStyle: true,
    alignment: DialogAlignment.Center
  })

  monthController = new CustomDialogController({
    builder: OptionsGridDialog({
      title: '选择月份',
      options: this.monthOptions(),
      onChange: (month: number) => {
        this.time = dayjs(this.time).set('month', month).valueOf();
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

  yearOptions(): OptionsItem<number>[] {
    const startYear = dayjs(this.firstUseTime || '2020-01-01').year();
    const currentYear = dayjs().year();
    const list: OptionsItem<number>[] = [];
    for (let year = currentYear; year >= startYear; year--) {
      list.push({ label: `${year}年`, value: year });
    }
    return list;
  }

  monthOptions(): OptionsItem<number>[] {
    const list: OptionsItem<number>[] = [];
    for (let i = 0; i < 12; i++) {
      list.push({ label: `${i + 1}月`, value: i });
    }
    return list;
  }

  @Builder SegmentItem(label: ResourceStr, value: StatsType) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.type === value ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.type === value ? $r('app.color.green') : $r('app.color.font_2'))
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .backgroundColor(this.type === value ? $r('app.color.white') : $r('app.color.transparent'))
      .borderRadius(SPACE_SMALL)
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
    .backgroundColor($r('app.color.grey_1'))
    .borderRadius(10)
  }

  @Builder Chip(format: string, controller: CustomDialogController) {
    Row({ space: SPACE_TINY }) {
      Text(dayjs(this.time).format(format))
        .fontSize(14)
        .lineHeight(20)
        .fontColor($r('app.color.font_3'))
      Image($r('app.media.arrow_down'))
        .width(12)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.font_2'))
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.white'))
    .borderRadius(10)
    .onClick(() => {
      controller.open();
    })
  }

  build() {
    Row({ space: SPACE_SMALL }) {
      this.SegmentedControl()
      Blank()
      this.Chip('YYYY年', this.yearController)
      if (this.type === StatsType.MONTH) {
        this.Chip('M月', this.monthController)
      }
    }
    .width('100%')
  }
}
