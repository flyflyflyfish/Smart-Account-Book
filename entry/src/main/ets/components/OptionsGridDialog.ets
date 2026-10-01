import { OptionsItem } from '../models/stats/StatsItem';
import { SPACE_MEDIUM } from '../common/dimens';

/**
 * 通用选项网格弹窗：用于年/月等离散选项的快速选择，紧凑美观
 */
@CustomDialog
export default struct OptionsGridDialog {
  controller: CustomDialogController;
  title: string = '';
  options: OptionsItem<number>[] = [];
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
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.font_3'))
      Grid() {
        ForEach(this.options, (item: OptionsItem<number>) => {
          GridItem() {
            Text(item.label)
              .fontSize(15)
              .fontColor($r('app.color.font_3'))
              .textAlign(TextAlign.Center)
              .width('100%')
              .height(40)
              .backgroundColor($r('app.color.grey_1'))
              .borderRadius(10)
              .onClick(() => {
                if (this.onChange) {
                  this.onChange(item.value);
                }
                this.controller.close();
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
        .fontSize(15)
        .fontColor($r('app.color.font_2'))
        .backgroundColor($r('app.color.grey_1'))
        .type(ButtonType.Normal)
        .borderRadius(20)
        .onClick(() => {
          this.controller.close();
        })
    }
    .width('78%')
    .padding({ left: 20, right: 20, top: 20, bottom: 16 })
    .borderRadius(20)
    .backgroundColor($r('app.color.white'))
  }
}
