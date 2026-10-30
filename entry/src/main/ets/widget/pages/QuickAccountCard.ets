let storage = new LocalStorage();

/**
 * 快捷记账卡片：今日收支 + 三个图标快捷入口（记一笔 / 拍照 / AI）。
 * 颜色由 EntryFormAbility 按当前应用主题解析后随卡片数据推送，
 * 默认值仅为主题数据到达前的兜底（松雾绿浅色）。
 * 金额“万”单位拆分为独立小号文本，主数字按长度自适应字号并占满剩余宽度，
 * 保证四位及以上数字与单位完整显示、末尾字符不被截断。
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

  // 金额数值部分：去掉“万”单位后的纯数字文本
  amountNumber(text: string): string {
    return text.endsWith('万') ? text.substring(0, text.length - 1) : text;
  }

  // 金额单位部分：有“万”返回“万”，否则返回空串
  amountUnit(text: string): string {
    return text.endsWith('万') ? '万' : '';
  }

  // 金额主文本：无数据时显示占位符；withSymbol 控制是否带“¥”前缀（宽卡四列空间紧张省略）
  amountMain(text: string, withSymbol: boolean): string {
    const num = this.amountNumber(text);
    if (num === '--') {
      return '--';
    }
    return withSymbol ? '¥ ' + num : num;
  }

  // 金额字号按数字长度自适应：每多出字符降档，保证四位及以上数字完整显示
  amountFontSize(text: string, base: number): number {
    const len = this.amountNumber(text).length;
    if (len > 8) {
      return Math.max(10, base - 5);
    }
    if (len > 6) {
      return Math.max(10, base - 4);
    }
    return base;
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
            Row({ space: 1 }) {
              Text(this.amountMain(this.expenses, false))
                .fontSize(this.amountFontSize(this.expenses, 15))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.dangerColor)
                .maxLines(1)
                .layoutWeight(1)
              Text(this.amountUnit(this.expenses))
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.dangerColor)
                .maxLines(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Divider()
            .vertical(true)
            .strokeWidth(0.5)
            .color(this.dividerColor)
            .height(26)
            .margin({ left: 4, right: 4 })

          Column({ space: 2 }) {
            Text($r('app.string.today_income_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
              .maxLines(1)
            Row({ space: 1 }) {
              Text(this.amountMain(this.income, false))
                .fontSize(this.amountFontSize(this.income, 15))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryColor)
                .maxLines(1)
                .layoutWeight(1)
              Text(this.amountUnit(this.income))
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryColor)
                .maxLines(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Divider()
            .vertical(true)
            .strokeWidth(0.5)
            .color(this.dividerColor)
            .height(26)
            .margin({ left: 4, right: 4 })

          Column({ space: 2 }) {
            Text($r('app.string.month_expense_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
              .maxLines(1)
            Row({ space: 1 }) {
              Text(this.amountMain(this.monthExpenses, false))
                .fontSize(this.amountFontSize(this.monthExpenses, 15))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.dangerColor)
                .maxLines(1)
                .layoutWeight(1)
              Text(this.amountUnit(this.monthExpenses))
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.dangerColor)
                .maxLines(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Divider()
            .vertical(true)
            .strokeWidth(0.5)
            .color(this.dividerColor)
            .height(26)
            .margin({ left: 4, right: 4 })

          Column({ space: 2 }) {
            Text($r('app.string.month_income_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
              .maxLines(1)
            Row({ space: 1 }) {
              Text(this.amountMain(this.monthIncome, false))
                .fontSize(this.amountFontSize(this.monthIncome, 15))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryColor)
                .maxLines(1)
                .layoutWeight(1)
              Text(this.amountUnit(this.monthIncome))
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryColor)
                .maxLines(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 10, bottom: 10 })
        .borderRadius(14)
        .backgroundColor(this.surfaceVariant)
      } else {
        Row() {
          Column({ space: 2 }) {
            Text($r('app.string.today_expense_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
              .maxLines(1)
            Row({ space: 1 }) {
              Text(this.amountMain(this.expenses, true))
                .fontSize(this.amountFontSize(this.expenses, 17))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.dangerColor)
                .maxLines(1)
                .layoutWeight(1)
              Text(this.amountUnit(this.expenses))
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.dangerColor)
                .maxLines(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)
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
            Row({ space: 1 }) {
              Text(this.amountMain(this.income, true))
                .fontSize(this.amountFontSize(this.income, 17))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryColor)
                .maxLines(1)
                .layoutWeight(1)
              Text(this.amountUnit(this.income))
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryColor)
                .maxLines(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)
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
