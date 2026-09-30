import dayjs from 'dayjs';
import { StatsType } from '../../models/stats/stats';
import PickerDialog, { StatsTypeOption } from '../PickerDialog';
import { OptionsItem, StatsItem } from '../../models/stats/StatsItem';
import PreferenceUtil from '../../utils/PreferenceUtil';
import * as CONSTANTS from '../../common/constants';
import { SPACE_SMALL, SPACE_TINY } from '../../common/dimens';

@Component
export default struct StatsHeader {
  @Link @Watch('onTypeChange') type: StatsType;
  @Link time: number;
  @State selected: number = 0;
  private firstUseTime: number = 0;
  private statsTypeOptions: StatsTypeOption[] = [
    { label: '月账单', value: StatsType.MONTH },
    { label: '年账单', value: StatsType.YEAR }
  ];
  controller = new CustomDialogController({
    builder: PickerDialog({
      options: this.statsTypeOptions,
      onChange: (type: StatsType) => {
        this.type = type;
        this.time = dayjs().valueOf();
      }
    }),
    customStyle: true
  })

  async aboutToAppear(): Promise<void> {
    this.firstUseTime = Number(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_USER_FIRST_KEY, 0));
    this.resetSelected();
  }

  // 当账期类型切换时，重新定位到当前月/年
  onTypeChange(): void {
    this.resetSelected();
  }

  getStatsTypeLabel(): string {
    const found = this.statsTypeOptions.find((item: StatsTypeOption): boolean => item.value === this.type);
    return found ? found.label : '';
  }

  getStatsTypeList(): OptionsItem<number>[] {
    return StatsItem.getStatsTypeDateList(this.type, this.firstUseTime);
  }

  // 仅在初始化或账期类型切换时重置选中项，避免每次 build 都重置高亮
  resetSelected(): void {
    const typeList = this.getStatsTypeList();
    const currentValue: number = this.type === StatsType.MONTH ? dayjs().month() : dayjs().year();
    const index = typeList.findIndex((item: OptionsItem<number>): boolean => item.value === currentValue);
    this.selected = index < 0 ? 0 : index;
  }

  selectAccountTime(item: OptionsItem<number>, index: number): void {
    this.selected = index;
    // 基于当前 time 修改月/年，保留月账单下已切换的年份
    if (this.type === StatsType.MONTH) {
      this.time = dayjs(this.time).set('month', item.value).valueOf();
    } else {
      this.time = dayjs(this.time).set('year', item.value).valueOf();
    }
  }

  // 年份切换范围：2020（与记账页日期选择器起点一致）~ 当前年
  canChangeYear(delta: number): boolean {
    const target = dayjs(this.time).add(delta, 'year').year();
    const minYear = 2020;
    const maxYear = dayjs().year();
    return target >= minYear && target <= maxYear;
  }

  changeYear(delta: number): void {
    if (!this.canChangeYear(delta)) {
      return;
    }
    this.time = dayjs(this.time).add(delta, 'year').valueOf();
  }

  @Builder YearSwitcher() {
    Row({ space: SPACE_SMALL }) {
      Image($r('app.media.arrow_left'))
        .width(10)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.font_1'))
        .opacity(this.canChangeYear(-1) ? 1 : 0.3)
        .padding(SPACE_TINY)
        .onClick(() => {
          this.changeYear(-1);
        })
      Text(dayjs(this.time).format('YYYY年'))
        .fontSize(14)
        .lineHeight(18)
        .fontColor($r('app.color.font_1'))
      Image($r('app.media.arrow_left'))
        .width(10)
        .objectFit(ImageFit.Contain)
        .rotate({ angle: 180 })
        .fillColor($r('app.color.font_1'))
        .opacity(this.canChangeYear(1) ? 1 : 0.3)
        .padding(SPACE_TINY)
        .onClick(() => {
          this.changeYear(1);
        })
    }.padding({
      left: SPACE_SMALL,
      right: SPACE_SMALL,
      top: SPACE_TINY,
      bottom: SPACE_TINY
    })
    .backgroundColor($r('app.color.white_alpha'))
    .borderRadius(12)
  }

  build() {
    Row({ space: 16 }) {
      Row({ space: 5 }) {
        Text(this.getStatsTypeLabel())
          .fontSize(18)
          .lineHeight(25)
          .fontColor($r('app.color.font_1'))
        Image($r('app.media.arrow_down'))
          .width(14)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.font_1'))
      }.onClick(() => {
        this.controller.open();
      })
      // 仅月账单需要年份切换，年账单的横向列表本身就是年份
      if (this.type === StatsType.MONTH) {
        this.YearSwitcher()
      }
      List({ space: 12, initialIndex: this.selected }) {
        ForEach(this.getStatsTypeList(), (item: OptionsItem<number>, index: number) => {
          ListItem() {
            Text(item.label)
              .fontSize(18)
              .lineHeight(25)
              .fontWeight(500)
              .fontColor(this.selected === index ? $r('app.color.font_1') : $r('app.color.font_2'))
              .padding({ left: 10, right: 10 })
              .onClick(() => this.selectAccountTime(item, index))
          }
        })
      }.listDirection(Axis.Horizontal)
      .alignListItem(ListItemAlign.Center)
      .layoutWeight(1)
      .height('100%')
    }.width('100%')
    .height(44)
  }
}
