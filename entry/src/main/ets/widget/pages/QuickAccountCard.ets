let storage = new LocalStorage();

@Entry(storage)
@Component
struct QuickAccountCard {
  @LocalStorageProp('expenses') expenses: string = '--';
  @LocalStorageProp('income') income: string = '--';

  build() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.today_expense_label'))
            .fontSize(12)
            .fontColor($r('app.color.font_2'))
          Text('¥ ' + this.expenses)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.font_1'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column({ space: 2 }) {
          Text($r('app.string.today_income_label'))
            .fontSize(12)
            .fontColor($r('app.color.font_2'))
          Text('¥ ' + this.income)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.green'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12 })

      Row({ space: 8 }) {
        Button($r('app.string.add_menu_manual'))
          .layoutWeight(1)
          .height(30)
          .fontSize(12)
          .fontColor($r('app.color.white'))
          .backgroundColor($r('app.color.green'))
          .type(ButtonType.Normal)
          .borderRadius(15)
          .onClick(() => {
            postCardAction(this, {
              action: 'router',
              abilityName: 'EntryAbility',
              params: { targetPage: 'add' }
            });
          })
        Button($r('app.string.pick_from_camera'))
          .layoutWeight(1)
          .height(30)
          .fontSize(12)
          .fontColor($r('app.color.white'))
          .backgroundColor($r('app.color.blue'))
          .type(ButtonType.Normal)
          .borderRadius(15)
          .onClick(() => {
            postCardAction(this, {
              action: 'router',
              abilityName: 'EntryAbility',
              params: { targetPage: 'recognize' }
            });
          })
        Button($r('app.string.ai_assistant'))
          .layoutWeight(1)
          .height(30)
          .fontSize(12)
          .fontColor($r('app.color.white'))
          .backgroundColor($r('app.color.orange'))
          .type(ButtonType.Normal)
          .borderRadius(15)
          .onClick(() => {
            postCardAction(this, {
              action: 'router',
              abilityName: 'EntryAbility',
              params: { targetPage: 'ai' }
            });
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor($r('app.color.white'))
  }
}
