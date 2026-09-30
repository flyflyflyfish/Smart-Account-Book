import dayjs from 'dayjs';
import { AccountType, GroupByDate } from '../models/account/account';
import { SPACE_SMALL } from '../common/dimens';

// accountType 的缺省值：收支都展示
const SHOW_ALL: number = -1;

/**
 * 账单分组头：展示分组日期与收支汇总
 */
@Component
export default struct GroupHeader {
  group: GroupByDate = { time: 0, expenses: 0, income: 0, records: [] };
  // 首页收支都展示，详情页只展示当前收支类型
  accountType: number = SHOW_ALL;

  build() {
    Column() {
      Row({ space: SPACE_SMALL }) {
        Text(dayjs(this.group.time).format('MM月DD日'))
          .fontSize(18)
          .fontColor($r('app.color.font_3'))
        Blank()
        if (this.accountType === SHOW_ALL || this.accountType === AccountType.EXPENSES) {
          Text($r('app.string.expense_label', this.group.expenses.toFixed(2)))
            .fontColor($r('app.color.font_2'))
            .fontSize(12)
        }
        if (this.accountType === SHOW_ALL || this.accountType === AccountType.INCOME) {
          Text($r('app.string.income_label', this.group.income.toFixed(2)))
            .fontColor($r('app.color.green'))
            .fontSize(12)
        }
      }.height(40)
      .width('100%')
      Divider().color($r('app.color.grey_1'))
    }.width('100%')
  }
}
