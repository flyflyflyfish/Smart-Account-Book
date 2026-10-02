import { StatsType } from '../models/stats/stats';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

export interface StatsTypeOption {
  label: string;
  value: StatsType;
}

@CustomDialog
export default struct PickerDialog {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }
  controller: CustomDialogController;
  private options: StatsTypeOption[] = [];
  private onChange?: (value: StatsType) => void;
  @State selected: number = 0;

  getSelectRange(): string[] {
    return this.options.map((item: StatsTypeOption): string => item.label);
  }

  build() {
    Column() {
      TextPicker({ range: this.getSelectRange(), selected: this.selected })
        .onChange((value: string | string[], index: number | number[]) => {
          if (typeof index === 'number') {
            this.selected = index;
          }
        })
      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .type(ButtonType.Normal)
          .borderRadius(4)
          .backgroundColor(this.tk().toastBg)
          .layoutWeight(1)
          .onClick(() => {
            this.controller.close()
          })
        Button($r('app.string.confirm'))
          .type(ButtonType.Normal)
          .borderRadius(4)
          .backgroundColor(this.tk().primary)
          .layoutWeight(1)
          .onClick(() => {
            if (this.onChange) {
              this.onChange(this.options[this.selected].value)
            }
            this.controller.close();
          })
      }.width('100%')
    }.width('90%')
    .padding(24)
    .borderRadius(12)
    .backgroundColor(this.tk().surface)
  }
}
