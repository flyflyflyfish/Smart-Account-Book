let storage = new LocalStorage();

/**
 * 快捷记账卡片：今日收支 + 三个图标快捷入口（记一笔 / 拍照 / AI）。
 * 颜色由 EntryFormAbility 按当前应用主题解析后随卡片数据推送，
 * 默认值仅为主题数据到达前的兜底（松雾绿浅色）。
 * 金额按字符串长度自适应字号，四位及以上数字自动缩小字号完整显示；
 * 超大金额由 WidgetUpdater 预格式化为“万”单位，避免溢出。
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
  @LocalStorageProp('surfaceVariant') surfaceVariant: string = '#ECEEEA';
  @LocalStorageProp('danger') dangerColor: string = '#C4534A';
  @LocalStorageProp('accentBlue') accentBlue: string = '#3B82D6';
  @LocalStorageProp('accentBlueSoft') accentBlueSoft: string = '#293B82D6';
  @LocalStorageProp('accentPurple') accentPurple: string = '#9C70E4';
  @LocalStorageProp('accentPurpleSoft') accentPurpleSoft: string = '#299C70E4';
  // 大卡（2*4）宽布局：左今日右本月，由 EntryFormAbility 按卡片尺寸下发
  @LocalStorageProp('isWide') isWideFlag: string = '0';

  // 金额前缀：无数据时显示占位符，避免出现“¥ --”
  amountText(value: string): string {
    return value === '--' ? '--' : '¥ ' + value;
  }

  // 金额字号按长度自适应：每多出约两位字符缩小一档，保证四位及以上数字完整显示
  amountFontSize(text: string, base: number): number {
    const len = text.length;
    let size = base;
    if (len > 9) {
      size = base - 6;
    } else if (len > 7) {
      size = base - 4;
    } else if (len > 5) {
      size = base - 2;
    }
    return Math.max(10, size);
  }

  build() {
    Column() {
      // 收支统计面板：柔色圆角卡片承载，配色为支出红、收入绿
      if (this.isWideFlag === '1') {
        Row() {
          Column({ space: 2 }) {
            Text($r('app.string.today_expense_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
              .maxLines(1)
            Text(this.amountText(this.expenses))
              .fontSize(this.amountFontSize(this.expenses, 15))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.dangerColor)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Divider()
            .vertical(true)
            .strokeWidth(0.5)
            .color(this.dividerColor)
            .height(26)
            .margin({ left: 6, right: 6 })

          Column({ space: 2 }) {
            Text($r('app.string.today_income_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
              .maxLines(1)
            Text(this.amountText(this.income))
              .fontSize(this.amountFontSize(this.income, 15))
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
            .height(26)
            .margin({ left: 6, right: 6 })

          Column({ space: 2 }) {
            Text($r('app.string.month_expense_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
              .maxLines(1)
            Text(this.amountText(this.monthExpenses))
              .fontSize(this.amountFontSize(this.monthExpenses, 15))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.dangerColor)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Divider()
            .vertical(true)
            .strokeWidth(0.5)
            .color(this.dividerColor)
            .height(26)
            .margin({ left: 6, right: 6 })

          Column({ space: 2 }) {
            Text($r('app.string.month_income_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
              .maxLines(1)
            Text(this.amountText(this.monthIncome))
              .fontSize(this.amountFontSize(this.monthIncome, 15))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryColor)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .borderRadius(14)
        .backgroundColor(this.surfaceVariant)
      } else {
        Row() {
          Column({ space: 2 }) {
            Text($r('app.string.today_expense_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
              .maxLines(1)
            Text(this.amountText(this.expenses))
              .fontSize(this.amountFontSize(this.expenses, 17))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.dangerColor)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Divider()
            .vertical(true)
            .strokeWidth(0.5)
            .color(this.dividerColor)
            .height(26)
            .margin({ left: 6, right: 6 })

          Column({ space: 2 }) {
            Text($r('app.string.today_income_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
              .maxLines(1)
            Text(this.amountText(this.income))
              .fontSize(this.amountFontSize(this.income, 17))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryColor)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .borderRadius(14)
        .backgroundColor(this.surfaceVariant)
      }

      // 快捷入口：圆角方块图标 + 底部文字，主按钮实底、辅助按钮柔色
      Row() {
        Column({ space: 4 }) {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(36)
              .height(36)
              .borderRadius(12)
              .backgroundColor(this.primaryColor)
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
            Column()
              .width(36)
              .height(36)
              .borderRadius(12)
              .backgroundColor(this.accentBlueSoft)
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
            Column()
              .width(36)
              .height(36)
              .borderRadius(12)
              .backgroundColor(this.accentPurpleSoft)
            Image($r('app.media.ai'))
              .width(18)
              .height(18)
              .fillColor(this.accentPurple)
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
      .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 14, right: 14, top: 12, bottom: 10 })
    .backgroundColor(this.bgColor)
  }
}
