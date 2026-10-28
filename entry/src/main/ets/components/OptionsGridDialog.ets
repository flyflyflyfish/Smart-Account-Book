import { OptionsItem } from '../models/stats/StatsItem';
import { SPACE_MEDIUM } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

/**
 * 通用选项网格弹窗：用于年/月等离散选项的快速选择，紧凑美观
 */
@CustomDialog
export default struct OptionsGridDialog {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }
  controller: CustomDialogController;
  title: string = '';
  options: OptionsItem<number>[] = [];
  // 当前已选中的值：对应选项高亮展示
  selectedValue?: number;
  onChange?: (value: number) => void;

  // Grid 是滚动容器，必须显式给定高度，否则弹窗会被撑满
  getGridHeight(): number {
    const rows = Math.ceil(this.options.length / 4);
    if (rows <= 0) {
      return 0;
    }
    return rows * 40 + (rows - 1) * 10;
  }

  build() {
    Column({ space: SPACE_MEDIUM }) {
      Text(this.title)
        .width('100%')
        .textAlign(TextAlign.Center)
        .fontSize(this.fs(16))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tk().textPrimary)
      Grid() {
        ForEach(this.options, (item: OptionsItem<number>) => {
          GridItem() {
            Text(item.label)
              .fontSize(this.fs(15))
              .fontWeight(item.value === this.selectedValue ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(item.value === this.selectedValue ? this.tk().primary : this.tk().textPrimary)
              .textAlign(TextAlign.Center)
              .width('100%')
              .height(40)
              .backgroundColor(item.value === this.selectedValue ? this.tk().primarySoft : this.tk().surfaceVariant)
              .borderRadius(10)
              .onClick(() => {
                if (this.onChange) {
                  this.onChange(item.value);
                }
                this.controller?.close();
              })
          }
        }, (item: OptionsItem<number>) => item.value.toString())
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .height(this.getGridHeight())
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
