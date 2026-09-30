import { AccountType, ItemRecordInfo } from '../models/account/account';
import AccountTypeModel from '../models/accountType/AccountTypeModel';
import { RADIUS_ICON, SPACE_MEDIUM, SPACE_TINY } from '../common/dimens';

@Component
export default struct AccountItem {
  private account: ItemRecordInfo = {
    id: 0,
    type: 0,
    accountType: 0,
    description: '',
    createTime: 0,
    amount: 0,
    time: 0,
    info: new AccountTypeModel(0, '', '', '')
  };

  build() {
    Row({ space: SPACE_MEDIUM }) {
      Column() {
        Image(this.account.info.icon)
          .width(16)
          .fillColor($r('app.color.white'))
      }.width(36)
      .height(36)
      .backgroundColor(this.account.info.activeColor)
      .borderRadius(RADIUS_ICON)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      Column({ space: SPACE_TINY }) {
        Text(this.account.info.name)
          .fontColor($r('app.color.font_3'))
          .fontSize(15)
        if (this.account.description) {
          Text(this.account.description)
            .fontSize(12)
            .lineHeight(14)
            .fontColor($r('app.color.font_2'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 支出深色、收入绿色，并带收支符号便于扫读
      Text((this.account.accountType === AccountType.EXPENSES ? '-' : '+') + this.account.amount.toFixed(2))
        .fontColor(this.account.accountType === AccountType.EXPENSES ? $r('app.color.font_3') : $r('app.color.green'))
        .fontWeight(FontWeight.Medium)
        .fontSize(16)
    }.width('100%')
    .height(56)
  }
}
