import { CategoryType } from '../../models/stats/stats'
import { SPACE_SMALL } from '../../common/dimens';
import { ThemeKit, ThemePalette } from '../../common/theme/Theme';

/**
 * 统计明细头部：标题 + “按日期 / 按分类”分段胶囊切换
 */
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

  @Builder ToggleItem(label: ResourceStr, value: CategoryType) {
    Text(label)
      .fontSize(this.fs(13))
      .lineHeight(this.fs(18))
      .fontWeight(this.categoryType === value ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.categoryType === value ? this.tk().primary : this.tk().textSecondary)
      .padding({ left: SPACE_SMALL + 4, right: SPACE_SMALL + 4, top: 5, bottom: 5 })
      .backgroundColor(this.categoryType === value ? this.tk().surface : Color.Transparent)
      .borderRadius(SPACE_SMALL)
      .onClick(() => {
        if (this.categoryType === value) {
          return;
        }
        this.categoryType = value;
        if (this.onChange) {
          this.onChange(this.categoryType);
        }
      })
  }

  build() {
    Row() {
      Text($r('app.string.statistics_details'))
        .fontSize(this.fs(16))
        .lineHeight(this.fs(22))
        .fontColor(this.tk().textPrimary)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
      Row({ space: 2 }) {
        this.ToggleItem($r('app.string.by_date'), CategoryType.DATE)
        this.ToggleItem($r('app.string.by_category'), CategoryType.TYPE)
      }
      .padding(2)
      .backgroundColor(this.tk().surfaceVariant)
      .borderRadius(SPACE_SMALL + 2)
    }.width('100%')
  }
}
