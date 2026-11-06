import router from '@ohos.router';
import { BusinessError } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import LedgerRepository from '../data/LedgerRepository';
import LedgerStore, { LedgerChangeListener } from '../common/LedgerStore';
import { LedgerOverview } from '../models/ledger/Ledger';
import LedgerEditDialog from '../components/ledger/LedgerEditDialog';
import { ledgerAccent, ledgerAccentSoft } from '../components/ledger/ledgerColors';
import { Logger } from '../utils/Logger';
import DBUtil from '../utils/DBUtil';
import {
  PAGE_PADDING,
  SPACE_LARGE,
  SPACE_MEDIUM,
  SPACE_SMALL
} from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

/**
 * 账本页签：多账本容器，卡片展示每本支出汇总与笔数，支持新建账本
 */
@Component
export default struct LedgerView {

  @StorageProp('themeSeq') themeSeq: number = 0;
  @State overviewList: LedgerOverview[] = [];
  @State loading: boolean = true;

  private repository: LedgerRepository = new LedgerRepository();
  // 长按操作的目标账本 id：重命名弹窗 getter 在打开时读取
  private pendingLedgerId: string = '';
  private ledgerListener: LedgerChangeListener = () => {
    this.queryOverviews();
  };
  // 新建账本弹窗
  private addDialogController: CustomDialogController = new CustomDialogController({
    builder: LedgerEditDialog({
      dialogTitle: $r('app.string.ledger_add'),
      getInitialName: (): string => '',
      getInitialColorKey: (): string => 'green',
      onConfirm: (name: string, colorKey: string): void => {
        this.addLedger(name, colorKey);
      }
    }),
    customStyle: true,
    alignment: DialogAlignment.Center
  });
  // 长按卡片的重命名弹窗：getter 在打开时读取待操作账本
  private renameDialogController: CustomDialogController = new CustomDialogController({
    builder: LedgerEditDialog({
      dialogTitle: $r('app.string.ledger_rename'),
      getInitialName: (): string => this.pendingLedgerName(),
      getInitialColorKey: (): string => this.pendingLedgerColorKey(),
      onConfirm: (name: string, colorKey: string): void => {
        this.renameLedger(name, colorKey);
      }
    }),
    customStyle: true,
    alignment: DialogAlignment.Center
  });

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  // 账本结余：收入 - 支出
  overviewBalance(overview: LedgerOverview): number {
    return overview.income - overview.expenses;
  }

  // 结余文案：正负带符号，样式对齐首页 BalanceBadge
  overviewBalanceText(overview: LedgerOverview): string {
    const balance = this.overviewBalance(overview);
    return (balance >= 0 ? '+' : '-') + '¥ ' + Math.abs(balance).toFixed(2);
  }

  async queryOverviews(): Promise<void> {
    try {
      await DBUtil.ready;
      this.overviewList = await this.repository.queryOverviews();
    } catch (err) {
      Logger.error('查询账本列表失败', (err as Error).message);
    } finally {
      this.loading = false;
    }
  }

  async addLedger(name: string, colorKey: string): Promise<void> {
    try {
      await this.repository.insertLedger(name, colorKey);
      LedgerStore.notifyChanged();
    } catch (err) {
      Logger.error('新建账本失败', (err as Error).message);
    }
  }

  // 待操作账本（长按卡片）的名称与颜色，供重命名弹窗 getter 读取
  pendingLedgerName(): string {
    const matched = this.overviewList.find((item: LedgerOverview): boolean =>
      item.ledger.id === this.pendingLedgerId);
    return matched ? matched.ledger.name : '';
  }

  pendingLedgerColorKey(): string {
    const matched = this.overviewList.find((item: LedgerOverview): boolean =>
      item.ledger.id === this.pendingLedgerId);
    return matched ? matched.ledger.colorKey : 'green';
  }

  // 长按账本卡片：弹出 重命名 / 删除 操作菜单，按返回 index 分发
  showCardMenu(overview: LedgerOverview): void {
    this.pendingLedgerId = overview.ledger.id;
    this.getUIContext().getPromptAction().showActionMenu({
      title: overview.ledger.name,
      buttons: [
        { text: $r('app.string.ledger_rename'), color: this.tk().textPrimary },
        { text: $r('app.string.delete'), color: this.tk().danger }
      ]
    })
      .then((response: promptAction.ActionMenuSuccessResponse) => {
        if (response.index === 0) {
          this.renameDialogController.open();
        } else if (response.index === 1) {
          this.confirmDeleteLedger(overview);
        }
      })
      .catch((err: BusinessError): void => {
        Logger.error('打开账本操作菜单失败', err.message);
      });
  }

  async renameLedger(name: string, colorKey: string): Promise<void> {
    try {
      const matched = this.overviewList.find((item: LedgerOverview): boolean =>
        item.ledger.id === this.pendingLedgerId);
      if (!matched) {
        return;
      }
      if (name !== matched.ledger.name) {
        await this.repository.renameLedger(matched.ledger.id, name);
      }
      if (colorKey !== matched.ledger.colorKey) {
        await this.repository.updateLedgerColor(matched.ledger.id, colorKey);
      }
      LedgerStore.notifyChanged();
    } catch (err) {
      Logger.error('重命名账本失败', (err as Error).message);
    }
  }

  // 删除账本前二次确认：账本内记录一并删除
  confirmDeleteLedger(overview: LedgerOverview): void {
    AlertDialog.show({
      title: $r('app.string.delete_confirm_title'),
      message: $r('app.string.ledger_delete_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: this.tk().danger,
        action: (): void => {
          this.deleteLedger(overview);
        }
      }
    });
  }

  async deleteLedger(overview: LedgerOverview): Promise<void> {
    try {
      await this.repository.deleteLedger(overview.ledger.id);
      LedgerStore.notifyChanged();
    } catch (err) {
      Logger.error('删除账本失败', (err as Error).message);
    }
  }

  openDetail(overview: LedgerOverview): void {
    const param: Record<string, Object> = { 'id': overview.ledger.id };
    router.pushUrl({ url: 'pages/LedgerDetail', params: param }).catch((err: BusinessError): void => {
      Logger.error('跳转账本详情失败', err.message);
    });
  }

  aboutToAppear(): void {
    LedgerStore.subscribe(this.ledgerListener);
    this.queryOverviews();
  }

  aboutToDisappear(): void {
    LedgerStore.unsubscribe(this.ledgerListener);
  }

  @Builder LedgerCard(overview: LedgerOverview) {
    Column({ space: SPACE_SMALL }) {
      Row({ space: SPACE_SMALL }) {
        Column() {
          Image($r('app.media.ledger'))
            .width(18)
            .height(18)
            .fillColor(ledgerAccent(this.tk(), overview.ledger.colorKey))
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .backgroundColor(ledgerAccentSoft(this.tk(), overview.ledger.colorKey))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Text(overview.ledger.name)
          .fontSize(this.fs(13))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')

      Text(this.overviewBalanceText(overview))
        .fontSize(this.fs(22))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.overviewBalance(overview) >= 0 ? this.tk().textPrimary : this.tk().danger)
      Text($r('app.string.ledger_card_sub', overview.recordCount,
        overview.expenses.toFixed(2), overview.income.toFixed(2)))
        .fontSize(this.fs(11))
        .fontColor(this.tk().textSecondary)
    }
    .width('48.5%')
    .alignItems(HorizontalAlign.Start)
    .padding(SPACE_MEDIUM)
    .borderRadius(18)
    .backgroundColor(this.tk().surface)
    .border({
      width: 1,
      color: this.tk().outline
    })
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
    .margin({ bottom: SPACE_MEDIUM })
    .onClick(() => {
      this.openDetail(overview);
    })
    // 长按卡片弹出 重命名 / 删除 菜单（300ms 触发，与页签/口径长按手感一致）
    .gesture(LongPressGesture({ repeat: false, duration: 300 })
      .onAction(() => {
        this.showCardMenu(overview);
      }))
  }

  @Builder AddLedgerCard() {
    Row({ space: SPACE_MEDIUM }) {
      Column() {
        Text('+')
          .fontSize(this.fs(18))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().primary)
      }
      .width(34)
      .height(34)
      .borderRadius(17)
      .backgroundColor(this.tk().primarySoft)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text($r('app.string.ledger_add'))
        .fontSize(this.fs(13))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tk().textPrimary)
        .layoutWeight(1)
      Text($r('app.string.ledger_add_hint'))
        .fontSize(this.fs(11))
        .fontColor(this.tk().textSecondary)
    }
    .width('48.5%')
    .height(96)
    .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM })
    .margin({ bottom: SPACE_MEDIUM })
    .borderRadius(18)
    .border({ width: 1.5, color: this.tk().outline, style: BorderStyle.Dashed })
    .onClick(() => {
      this.addDialogController.open();
    })
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: SPACE_LARGE }) {
          Text($r('app.string.ledger'))
            .fontSize(this.fs(18))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tk().textPrimary)

          if (this.overviewList.length > 0) {
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(this.overviewList, (overview: LedgerOverview) => {
                this.LedgerCard(overview)
              }, (overview: LedgerOverview): string => 'ledger_card_' + overview.ledger.id + '_' +
                overview.ledger.name + '_' + overview.ledger.colorKey + '_' +
                overview.expenses + '_' + overview.income + '_' + overview.recordCount)
              this.AddLedgerCard()
            }
            .width('100%')
          } else if (this.loading) {
            Column({ space: SPACE_MEDIUM }) {
              LoadingProgress()
                .width(40)
                .height(40)
                .color(this.tk().primary)
              Text($r('app.string.loading_tip'))
                .fontSize(this.fs(13))
                .fontColor(this.tk().textSecondary)
            }
            .width('100%')
            .margin({ top: 60 })
          } else {
            Column({ space: SPACE_LARGE }) {
              Image($r('app.media.empty'))
                .width(100)
                .objectFit(ImageFit.Contain)
              Column({ space: SPACE_SMALL }) {
                Text($r('app.string.ledger_empty_tip'))
                  .fontSize(this.fs(13))
                  .lineHeight(this.fs(18))
                  .fontColor(this.tk().textSecondary)
                Text($r('app.string.ledger_empty_sub'))
                  .fontSize(this.fs(12))
                  .lineHeight(this.fs(17))
                  .fontColor(this.tk().textSecondary)
                  .opacity(0.7)
              }
              this.AddLedgerCard()
            }
            .width('100%')
            .margin({ top: 60 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(PAGE_PADDING)
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }
}
