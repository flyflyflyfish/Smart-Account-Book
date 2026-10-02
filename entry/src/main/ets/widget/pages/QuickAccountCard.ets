let storage = new LocalStorage();

/**
 * 快捷记账卡片：今日收支 + 三个图标快捷入口（记一笔 / 拍照 / AI）。
 * 颜色由 EntryFormAbility 按当前应用主题解析后随卡片数据推送，
 * 默认值仅为主题数据到达前的兜底（松雾绿浅色）。
 */
@Entry(storage)
@Component
struct QuickAccountCard {
  @LocalStorageProp('expenses') expenses: string = '--';
  @LocalStorageProp('income') income: string = '--';
  @LocalStorageProp('monthExpenses') monthExpenses: string = '--';
  @LocalStorageProp('monthIncome') monthIncome: string = '--';
  @LocalStorageProp('bg') bgColor: string = '#F3F5F4';
  @LocalStorageProp('textPrimary') textPrimary: string = '#1D221F';
  @LocalStorageProp('textSecondary') textSecondary: string = '#5F6660';
  @LocalStorageProp('primary') primaryColor: string = '#2E9E73';
  @LocalStorageProp('onPrimary') onPrimary: string = '#FFFFFF';
  @LocalStorageProp('primarySoft') primarySoft: string = '#292E9E73';
  @LocalStorageProp('divider') dividerColor: string = '#CBCDCC';
  @LocalStorageProp('accentBlue') accentBlue: string = '#3B82D6';
  @LocalStorageProp('accentBlueSoft') accentBlueSoft: string = '#293B82D6';
  @LocalStorageProp('accentOrange') accentOrange: string = '#E5833A';
  @LocalStorageProp('accentOrangeSoft') accentOrangeSoft: string = '#29E5833A';
  // 大卡（2*4）宽布局：左今日右本月，由 EntryFormAbility 按卡片尺寸下发
  @LocalStorageProp('isWide') isWideFlag: string = '0';

  build() {
    Column() {
      if (this.isWideFlag === '1') {
        Row() {
          Column({ space: 2 }) {
            Text($r('app.string.today_expense_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
            Text('¥ ' + this.expenses)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.textPrimary)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column({ space: 2 }) {
            Text($r('app.string.today_income_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
            Text('¥ ' + this.income)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryColor)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Divider()
            .vertical(true)
            .strokeWidth(0.5)
            .color(this.dividerColor)
            .height(30)
            .margin({ left: 8, right: 8 })

          Column({ space: 2 }) {
            Text($r('app.string.month_expense_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
            Text('¥ ' + this.monthExpenses)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.textPrimary)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column({ space: 2 }) {
            Text($r('app.string.month_income_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
            Text('¥ ' + this.monthIncome)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryColor)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
      } else {
        Row() {
          Column({ space: 2 }) {
            Text($r('app.string.today_expense_label'))
              .fontSize(11)
              .fontColor(this.textSecondary)
            Text('¥ ' + this.expenses)
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.textPrimary)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column({ space: 2 }) {
            Text($r('app.string.today_income_label'))
              .fontSize(11)
              .fontColor(this.textSecondary)
            Text('¥ ' + this.income)
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryColor)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
      }

      Divider()
        .color(this.dividerColor)
        .strokeWidth(0.5)
        .margin({ top: 10, bottom: 10 })

      Row() {
        Column({ space: 4 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle()
              .width(36)
              .height(36)
              .fill(this.primaryColor)
            Image($r('app.media.add'))
              .width(18)
              .height(18)
              .fillColor(this.onPrimary)
          }
          .width(36)
          .height(36)
          Text($r('app.string.add_menu_manual'))
            .fontSize(10)
            .fontColor(this.textSecondary)
            .maxLines(1)
        }
        .layoutWeight(1)
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: { targetPage: 'add' }
          });
        })

        Column({ space: 4 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle()
              .width(36)
              .height(36)
              .fill(this.accentBlueSoft)
            Image($r('app.media.camera'))
              .width(18)
              .height(18)
              .fillColor(this.accentBlue)
          }
          .width(36)
          .height(36)
          Text($r('app.string.pick_from_camera'))
            .fontSize(10)
            .fontColor(this.textSecondary)
            .maxLines(1)
        }
        .layoutWeight(1)
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: { targetPage: 'recognize' }
          });
        })

        Column({ space: 4 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle()
              .width(36)
              .height(36)
              .fill(this.accentOrangeSoft)
            Image($r('app.media.ai'))
              .width(18)
              .height(18)
              .fillColor(this.accentOrange)
          }
          .width(36)
          .height(36)
          Text($r('app.string.ai_assistant'))
            .fontSize(10)
            .fontColor(this.textSecondary)
            .maxLines(1)
        }
        .layoutWeight(1)
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: { targetPage: 'ai' }
          });
        })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 14, right: 14, top: 12, bottom: 10 })
    .backgroundColor(this.bgColor)
  }
}
