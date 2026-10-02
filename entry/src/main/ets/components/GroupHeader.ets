import dayjs from 'dayjs';
import { AccountType, GroupByDate } from '../models/account/account';
import { SPACE_SMALL } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

// accountType 的缺省值：收支都展示
const SHOW_ALL: number = -1;

/**
 * 账单分组头：展示分组日期与收支汇总
 */
@Component
export default struct GroupHeader {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }
  group: GroupByDate = { time: 0, expenses: 0, income: 0, records: [] };
  // 首页收支都展示，详情页只展示当前收支类型
  accountType: number = SHOW_ALL;

  build() {
    Column() {
      Row({ space: SPACE_SMALL }) {
        Text(dayjs(this.group.time).format('MM月DD日'))
          .fontSize(this.fs(18))
          .fontColor(this.tk().textPrimary)
        Blank()
        if (this.accountType === SHOW_ALL || this.accountType === AccountType.EXPENSES) {
          Text($r('app.string.expense_label', this.group.expenses.toFixed(2)))
            .fontColor(this.tk().textSecondary)
            .fontSize(this.fs(12))
        }
        if (this.accountType === SHOW_ALL || this.accountType === AccountType.INCOME) {
          Text($r('app.string.income_label', this.group.income.toFixed(2)))
            .fontColor(this.tk().primary)
            .fontSize(this.fs(12))
        }
      }.height(40)
      .width('100%')
      Divider().color(this.tk().surfaceVariant)
    }.width('100%')
  }
}
