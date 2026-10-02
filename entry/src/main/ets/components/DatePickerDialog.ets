import { ThemeKit, ThemePalette } from '../common/theme/Theme';
@CustomDialog
export default struct DatePickerDialog {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }
  controller: CustomDialogController;
  selectedDate: Date = new Date();
  onChange?: (date: number) => void;

  build() {
    Column({ space: 16 }) {
      DatePicker({
        start: new Date('2020-1-1'),
        end: new Date(),
        selected: this.selectedDate,
      }).onChange((value: DatePickerResult) => {
        this.selectedDate.setFullYear(value.year ?? 0, value.month ?? 0, value.day ?? 0);
      })
      Row({ space: 12 }) {
        Button($r('app.string.cancel'))
          .width(120)
          .backgroundColor(this.tk().outline)
          .onClick(() => {
            this.controller.close();
          })
        Button($r('app.string.submit'))
          .width(120)
          .backgroundColor(this.tk().primary)
          .onClick(() => {
            if (this.onChange) {
              this.onChange(this.selectedDate.getTime())
            }
            this.controller.close();
          })
      }
    }.padding(16)
  }
}