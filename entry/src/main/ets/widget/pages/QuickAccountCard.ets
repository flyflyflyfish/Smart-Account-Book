let storage = new LocalStorage();

/**
 * 快捷记账卡片。
 * 大卡（2*4）：今日/本月口径切换 + 支出/收入两列 + 三个图标快捷入口。
 * 小卡（2*2）：第一排今日支出、第二排今日收入，右上角「+」点击展开
 * 手动添加 / 拍照识别 / AI助手三个入口，任选其一跳转对应页面。
 * 金额单位固定为元，不做万位缩写；按金额长度自适应字号，保证 100001.00 这类金额完整显示。
 * 颜色由 EntryFormAbility 按当前应用主题解析后随卡片数据推送，
 * 默认值仅为主题数据到达前的兜底（松雾绿浅色）。
 */
@Entry(storage)
@Component
struct QuickAccountCard {
  @LocalStorageProp('expenses') expenses: string = '--';
  @LocalStorageProp('income') income: string = '--';
  // 当前统计口径：today 今日 / month 本月，由 EntryFormAbility 随卡片数据下发
  @LocalStorageProp('range') range: string = 'today';
  // 小卡「+」菜单展开标记：1 展开 / 0 收起
  @LocalStorageProp('menuVisible') menuVisible: string = '0';
  @LocalStorageProp('bg') bgColor: string = '#F3F5F4';
  @LocalStorageProp('textPrimary') textPrimary: string = '#1D221F';
  @LocalStorageProp('textSecondary') textSecondary: string = '#5F6660';
  @LocalStorageProp('primary') primaryColor: string = '#2E9E73';
  @LocalStorageProp('onPrimary') onPrimary: string = '#FFFFFF';
  @LocalStorageProp('primarySoft') primarySoft: string = '#292E9E73';
  @LocalStorageProp('divider') dividerColor: string = '#CBCDCC';
  // 三个快捷入口颜色：主色锚定的同色系渐变色（手动添加用实色主色，拍照/AI 用色相渐变色）
  @LocalStorageProp('entryAdd') entryAdd: string = '#2E9E73';
  @LocalStorageProp('entryCamera') entryCamera: string = '#2E8FA6';
  @LocalStorageProp('entryCameraSoft') entryCameraSoft: string = '#292E8FA6';
  @LocalStorageProp('entryAi') entryAi: string = '#6FA02E';
  @LocalStorageProp('entryAiSoft') entryAiSoft: string = '#296FA02E';
  // 大卡（2*4）宽布局标记，由 EntryFormAbility 按卡片尺寸下发
  @LocalStorageProp('isWide') isWideFlag: string = '0';
  // 第三入口样式：ai AI助手 / ledger 账本，跟随外观-首页统计的底部第二页签设置下发
  @LocalStorageProp('thirdEntry') thirdEntry: string = 'ai';
  // 账本入口配色（取主题蓝点缀色）
  @LocalStorageProp('accentBlue') accentBlue: string = '#3D94F0';
  @LocalStorageProp('accentBlueSoft') accentBlueSoft: string = '#293D94F0';

  // 双击检测：记录上一次点击时间戳，400ms 内连点两次非按钮区域进入应用首页
  private lastTapTime: number = 0;
  // 按钮 onClick 先于根容器 onClick 执行（点击事件冒泡），按钮先打标记，根容器据此跳过本次点击
  private buttonTap: boolean = false;

  /** 按钮 onClick 首行调用：标记本次点击来自按钮，根容器不做双击检测 */
  markButtonTap(): void {
    this.buttonTap = true;
  }

  /** 卡片主体点击：双击非按钮区域拉起应用首页 */
  onCardClick(): void {
    if (this.buttonTap) {
      this.buttonTap = false;
      this.lastTapTime = 0;
      return;
    }
    const now = Date.now();
    if (this.lastTapTime > 0 && now - this.lastTapTime <= 400) {
      this.lastTapTime = 0;
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { targetPage: 'home' }
      });
    } else {
      this.lastTapTime = now;
    }
  }

  /** 大卡金额字号随长度自适应：越长字号越小，确保长金额（如 100001.00）不被截断 */
  amountFontSize(value: string): number {
    const base = 16;
    const len = value.length;
    if (len <= 7) {
      return base;
    }
    if (len <= 9) {
      return base - 2;
    }
    if (len <= 11) {
      return base - 4;
    }
    return base - 6;
  }

  /** 小卡金额与标签同行排布，可用宽度更窄，字号自适应更积极 */
  smallAmountFontSize(value: string): number {
    const len = value.length;
    if (len <= 7) {
      return 16;
    }
    if (len <= 9) {
      return 14;
    }
    if (len <= 11) {
      return 12;
    }
    return 10;
  }

  build() {
    if (this.isWideFlag === '1') {
      Column() {
        Row({ space: 6 }) {
          Text($r('app.string.widget_range_today'))
            .fontSize(11)
            .fontColor(this.range === 'today' ? this.primaryColor : this.textSecondary)
            .backgroundColor(this.range === 'today' ? this.primarySoft : Color.Transparent)
            .borderRadius(9)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .onClick(() => {
              this.markButtonTap();
              postCardAction(this, {
                action: 'message',
                params: { range: 'today' }
              });
            })

          Text($r('app.string.widget_range_month'))
            .fontSize(11)
            .fontColor(this.range === 'month' ? this.primaryColor : this.textSecondary)
            .backgroundColor(this.range === 'month' ? this.primarySoft : Color.Transparent)
            .borderRadius(9)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .onClick(() => {
              this.markButtonTap();
              postCardAction(this, {
                action: 'message',
                params: { range: 'month' }
              });
            })
        }
        .width('100%')

        Row() {
          Column({ space: 2 }) {
            Text($r('app.string.widget_expense_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
            Text(this.expenses)
              .fontSize(this.amountFontSize(this.expenses))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.textPrimary)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column({ space: 2 }) {
            Text($r('app.string.widget_income_label'))
              .fontSize(10)
              .fontColor(this.textSecondary)
            Text(this.income)
              .fontSize(this.amountFontSize(this.income))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryColor)
              .maxLines(1)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: 7 })

        Divider()
          .color(this.dividerColor)
          .strokeWidth(0.5)
          .margin({ top: 8, bottom: 8 })

        Row() {
          Column({ space: 4 }) {
            Stack({ alignContent: Alignment.Center }) {
              Circle()
                .width(36)
                .height(36)
                .fill(this.entryAdd)
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
            this.markButtonTap();
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
                .fill(this.entryCameraSoft)
              Image($r('app.media.camera'))
                .width(18)
                .height(18)
                .fillColor(this.entryCamera)
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
            this.markButtonTap();
            postCardAction(this, {
              action: 'router',
              abilityName: 'EntryAbility',
              params: { targetPage: 'recognize' }
            });
          })

          if (this.thirdEntry === 'ledger') {
            // 第三入口为账本：跟随底部第二页签设置
            Column({ space: 4 }) {
              Stack({ alignContent: Alignment.Center }) {
                Circle()
                  .width(36)
                  .height(36)
                  .fill(this.accentBlueSoft)
                Image($r('app.media.ledger'))
                  .width(18)
                  .height(18)
                  .fillColor(this.accentBlue)
              }
              .width(36)
              .height(36)
              Text($r('app.string.ledger'))
                .fontSize(10)
                .fontColor(this.textSecondary)
                .maxLines(1)
            }
            .layoutWeight(1)
            .onClick(() => {
              this.markButtonTap();
              postCardAction(this, {
                action: 'router',
                abilityName: 'EntryAbility',
                params: { targetPage: 'ledger' }
              });
            })
          } else {
            // 第三入口为 AI 助手
            Column({ space: 4 }) {
              Stack({ alignContent: Alignment.Center }) {
                Circle()
                  .width(36)
                  .height(36)
                  .fill(this.entryAiSoft)
                Image($r('app.media.ai'))
                  .width(18)
                  .height(18)
                  .fillColor(this.entryAi)
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
              this.markButtonTap();
              postCardAction(this, {
                action: 'router',
                abilityName: 'EntryAbility',
                params: { targetPage: 'ai' }
              });
            })
          }
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 14, right: 14, top: 10, bottom: 8 })
      .backgroundColor(this.bgColor)
      .onClick(() => {
        this.onCardClick();
      })
    } else {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (this.menuVisible === '1') {
          // 「+」菜单展开：三个添加入口，任选其一跳转对应页面
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Stack({ alignContent: Alignment.Center }) {
                Circle()
                  .width(28)
                  .height(28)
                  .fill(this.entryAdd)
                Image($r('app.media.add'))
                  .width(14)
                  .height(14)
                  .fillColor(this.onPrimary)
              }
              .width(28)
              .height(28)
              Text($r('app.string.add_menu_manual'))
                .fontSize(12)
                .fontColor(this.textPrimary)
            }
            .onClick(() => {
              this.markButtonTap();
              postCardAction(this, {
                action: 'router',
                abilityName: 'EntryAbility',
                params: { targetPage: 'add' }
              });
            })

            Row({ space: 8 }) {
              Stack({ alignContent: Alignment.Center }) {
                Circle()
                  .width(28)
                  .height(28)
                  .fill(this.entryCameraSoft)
                Image($r('app.media.camera'))
                  .width(14)
                  .height(14)
                  .fillColor(this.entryCamera)
              }
              .width(28)
              .height(28)
              Text($r('app.string.pick_from_camera'))
                .fontSize(12)
                .fontColor(this.textPrimary)
            }
            .onClick(() => {
              this.markButtonTap();
              postCardAction(this, {
                action: 'router',
                abilityName: 'EntryAbility',
                params: { targetPage: 'recognize' }
              });
            })

            if (this.thirdEntry === 'ledger') {
              // 第三入口为账本：跟随底部第二页签设置
              Row({ space: 8 }) {
                Stack({ alignContent: Alignment.Center }) {
                  Circle()
                    .width(28)
                    .height(28)
                    .fill(this.accentBlueSoft)
                  Image($r('app.media.ledger'))
                    .width(14)
                    .height(14)
                    .fillColor(this.accentBlue)
                }
                .width(28)
                .height(28)
                Text($r('app.string.ledger'))
                  .fontSize(12)
                  .fontColor(this.textPrimary)
              }
              .onClick(() => {
                this.markButtonTap();
                postCardAction(this, {
                  action: 'router',
                  abilityName: 'EntryAbility',
                  params: { targetPage: 'ledger' }
                });
              })
            } else {
              // 第三入口为 AI 助手
              Row({ space: 8 }) {
                Stack({ alignContent: Alignment.Center }) {
                  Circle()
                    .width(28)
                    .height(28)
                    .fill(this.entryAiSoft)
                  Image($r('app.media.ai'))
                    .width(14)
                    .height(14)
                    .fillColor(this.entryAi)
                }
                .width(28)
                .height(28)
                Text($r('app.string.ai_assistant'))
                  .fontSize(12)
                  .fontColor(this.textPrimary)
              }
              .onClick(() => {
                this.markButtonTap();
                postCardAction(this, {
                  action: 'router',
                  abilityName: 'EntryAbility',
                  params: { targetPage: 'ai' }
                });
              })
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ left: 16, right: 16, top: 34, bottom: 12 })
        } else {
          // 收起状态：第一排今日支出、第二排今日收入
          Column({ space: 12 }) {
            Row() {
              Text($r('app.string.widget_today_expense_label'))
                .fontSize(10)
                .fontColor(this.textSecondary)
              Text(this.expenses)
                .layoutWeight(1)
                .textAlign(TextAlign.End)
                .fontSize(this.smallAmountFontSize(this.expenses))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.textPrimary)
                .maxLines(1)
            }
            .width('100%')

            Row() {
              Text($r('app.string.widget_today_income_label'))
                .fontSize(10)
                .fontColor(this.textSecondary)
              Text(this.income)
                .layoutWeight(1)
                .textAlign(TextAlign.End)
                .fontSize(this.smallAmountFontSize(this.income))
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryColor)
                .maxLines(1)
            }
            .width('100%')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }

        // 右上角「+」：点击展开/收起菜单
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(26)
            .height(26)
            .fill(this.primaryColor)
          Image($r('app.media.add'))
            .width(14)
            .height(14)
            .fillColor(this.onPrimary)
        }
        .width(26)
        .height(26)
        .margin({ top: 2, right: 2 })
        .onClick(() => {
          this.markButtonTap();
          postCardAction(this, {
            action: 'message',
            params: { menu: 'toggle' }
          });
        })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(this.bgColor)
      .onClick(() => {
        this.onCardClick();
      })
    }
  }
}
