import { CategoryType } from '../../models/stats/stats'
import { ThemeKit, ThemePalette } from '../../common/theme/Theme';
@Component
export default struct StatsDetailHeader {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }
  @State categoryType: CategoryType = CategoryType.DATE;
  onChange?: (type: CategoryType) => void;

  build() {
    Row() {
      Text($r('app.string.statistics_details'))
        .fontSize(this.fs(18))
        .lineHeight(this.fs(25))
        .fontColor(this.tk().textPrimary)
        .fontWeight(500)
        .layoutWeight(1)
      Button(this.categoryType === CategoryType.DATE ? $r('app.string.by_category') : $r('app.string.by_date'))
        .backgroundColor(this.tk().primary)
        .onClick(() => {
          this.categoryType = this.categoryType === CategoryType.DATE ? CategoryType.TYPE : CategoryType.DATE;
          if (this.onChange) {
            this.onChange(this.categoryType);
          }
        })
    }.width('100%')
  }
}