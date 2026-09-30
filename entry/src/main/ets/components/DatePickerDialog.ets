@CustomDialog
export default struct DatePickerDialog {
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
          .backgroundColor($r('app.color.grey_2'))
          .onClick(() => {
            this.controller.close();
          })
        Button($r('app.string.submit'))
          .width(120)
          .backgroundColor($r('app.color.green'))
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