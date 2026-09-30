import AccountNavigator from '../components/Navigator';
import AccountForm from '../components/addAccount/AccountForm';
import { expenses, incomes } from '../models/accountType/accountType';
import { AccountType, ItemRecordInfo } from '../models/account/account';
import BreakpointConstants from '../common/breakpoint';

@Entry
@Component
struct AddAccount {
  @State currentIndex: number = 0;
  // 首页点击账单条目时经 AppStorage 传入，非空则进入编辑模式
  @State editRecord: ItemRecordInfo | undefined = undefined;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  aboutToAppear(): void {
    const record = AppStorage.get<ItemRecordInfo>('editRecord');
    if (record) {
      this.editRecord = record;
      // 编辑时直接定位到记录所属的收支 Tab
      this.currentIndex = record.accountType;
      AppStorage.delete('editRecord');
    }
  }

  @Builder TabBuilder(name: ResourceStr, index: number) {
    Column() {
      Text(name)
        .fontColor(this.currentIndex === index ? $r('app.color.font_1') : $r('app.color.font_2'))
        .fontSize(18)
        .lineHeight(20)
        .margin({ top: 17, bottom: 7 })
      Divider()
        .strokeWidth(2)
        .color($r('app.color.font_1'))
        .opacity(this.currentIndex === index ? 1 : 0)
    }.width('100%')
  }

  build() {
    Column() {
      AccountNavigator()
      Tabs({ index: this.currentIndex }) {
        TabContent() {
          AccountForm({ accountTypeList: expenses, accountType: AccountType.EXPENSES, editRecord: this.editRecord })
            .height('100%')
            .padding({ top: 16 })
        }.tabBar(this.TabBuilder($r('app.string.expenditure'), 0))
        TabContent() {
          AccountForm({ accountTypeList: incomes, accountType: AccountType.INCOME, editRecord: this.editRecord })
            .height('100%')
            .padding({ top: 16 })
        }.tabBar(this.TabBuilder($r('app.string.income'), 1))
      }.width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
      .layoutWeight(1)
      .padding({ left: 24, right: 24 })
      .onChange((index) => {
        this.currentIndex = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }
}
