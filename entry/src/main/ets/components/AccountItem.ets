import dayjs from 'dayjs';
import { AccountType, ItemRecordInfo } from '../models/account/account';
import AccountTypeModel from '../models/accountType/AccountTypeModel';
import { RADIUS_ICON, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

@Component
export default struct AccountItem {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }
  private account: ItemRecordInfo = {
    id: '',
    type: 0,
    accountType: 0,
    description: '',
    createTime: 0,
    amount: 0,
    time: 0,
    info: new AccountTypeModel(0, '', '', '')
  };

  // 显示消费时间（时分）：旧数据 payTime 为 0 时退回日期当天 00:00
  formatPayTime(): string {
    const payTime = this.account.payTime ?? 0;
    if (payTime > 0) {
      return dayjs(payTime).format('HH:mm');
    }
    return dayjs(this.account.time).format('HH:mm');
  }

  build() {
    Row({ space: SPACE_MEDIUM }) {
      Column() {
        Image(this.account.info.icon)
          .width(16)
          .fillColor(this.tk().surface)
      }.width(36)
      .height(36)
      .backgroundColor(this.account.info.activeColor)
      .borderRadius(RADIUS_ICON)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      Column({ space: SPACE_TINY }) {
        Row({ space: SPACE_SMALL }) {
          Text(this.account.info.name)
            .fontColor(this.tk().textPrimary)
            .fontSize(this.fs(15))
          Text(this.formatPayTime())
            .fontSize(this.fs(11))
            .lineHeight(this.fs(15))
            .fontColor(this.tk().textSecondary)
        }
        if (this.account.description) {
          Text(this.account.description)
            .fontSize(this.fs(12))
            .lineHeight(this.fs(14))
            .fontColor(this.tk().textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 支出深色、收入绿色，并带收支符号便于扫读
      Text((this.account.accountType === AccountType.EXPENSES ? '-' : '+') + this.account.amount.toFixed(2))
        .fontColor(this.account.accountType === AccountType.EXPENSES ? this.tk().textPrimary : this.tk().primary)
        .fontWeight(FontWeight.Medium)
        .fontSize(this.fs(16))
    }.width('100%')
    .height(56)
  }
}
