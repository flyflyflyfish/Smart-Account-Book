import { ThemeKit, ThemePalette } from '../../common/theme/Theme';
import { LEDGER_COLOR_KEYS } from '../../models/ledger/Ledger';
import { ledgerAccent, ledgerAccentSoft } from './ledgerColors';
import { SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL } from '../../common/dimens';

/**
 * 新建/重命名账本弹窗：名称 + 颜色
 */
@CustomDialog
export default struct LedgerEditDialog {
  @StorageProp('themeSeq') themeSeq: number = 0;
  controller: CustomDialogController;
  // 弹窗标题（新建账本 / 重命名）
  private dialogTitle: ResourceStr = $r('app.string.ledger_add');
  // 初始名称与颜色的 getter：builder 参数在构造时求值会拿到旧值，改用回调在打开时取最新值
  private getInitialName: () => string = () => '';
  private getInitialColorKey: () => string = () => 'green';
  // 确认回调：返回名称与颜色 key
  private onConfirm: (name: string, colorKey: string) => void = () => {
  };

  @State ledgerName: string = '';
  @State selectedColorKey: string = 'green';

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  aboutToAppear(): void {
    this.ledgerName = this.getInitialName();
    this.selectedColorKey = this.getInitialColorKey();
  }

  confirmAction(): void {
    const name = this.ledgerName.trim();
    if (name.length === 0) {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.ledger_name_required'),
        duration: 1500
      });
      return;
    }
    this.onConfirm(name, this.selectedColorKey);
    this.controller.close();
  }

  build() {
    Column({ space: SPACE_LARGE }) {
      Text(this.dialogTitle)
        .fontSize(this.fs(16))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tk().textPrimary)
        .width('100%')
        .textAlign(TextAlign.Center)

      TextInput({ placeholder: $r('app.string.ledger_name_placeholder'), text: this.ledgerName })
        .fontSize(this.fs(15))
        .fontColor(this.tk().textPrimary)
        .placeholderColor(this.tk().textSecondary)
        .placeholderFont({ size: this.fs(14) })
        .backgroundColor(this.tk().surfaceVariant)
        .borderRadius(12)
        .height(44)
        .maxLength(12)
        .onChange((value: string) => {
          this.ledgerName = value;
        })

      Row({ space: SPACE_MEDIUM }) {
        ForEach(LEDGER_COLOR_KEYS, (key: string) => {
          Column()
            .width(28)
            .height(28)
            .borderRadius(14)
            .backgroundColor(ledgerAccentSoft(this.tk(), key))
            .border({
              width: this.selectedColorKey === key ? 3 : 1,
              color: this.selectedColorKey === key ? ledgerAccent(this.tk(), key) : this.tk().outline
            })
            .onClick(() => {
              this.selectedColorKey = key;
            })
        }, (key: string): string => 'ledger_color_' + key)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      Row({ space: SPACE_MEDIUM }) {
        Button($r('app.string.cancel'))
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .backgroundColor(this.tk().surfaceVariant)
          .fontColor(this.tk().textSecondary)
          .fontSize(this.fs(15))
          .height(42)
          .layoutWeight(1)
          .onClick(() => {
            this.controller.close();
          })
        Button($r('app.string.confirm'))
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .backgroundColor(this.tk().primary)
          .fontColor(this.tk().onPrimary)
          .fontSize(this.fs(15))
          .height(42)
          .layoutWeight(1)
          .onClick(() => {
            this.confirmAction();
          })
      }
      .width('100%')
    }
    .width('90%')
    .padding(SPACE_LARGE)
    .borderRadius(16)
    .backgroundColor(this.tk().surface)
  }
}
