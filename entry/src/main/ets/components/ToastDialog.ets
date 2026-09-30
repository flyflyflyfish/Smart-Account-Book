@CustomDialog
export default struct ToastDialog {
  controller: CustomDialogController;
  message: ResourceStr = '';
  type: 'error' | 'success' = 'success';

  getTypeImage() {
    switch (this.type) {
      case 'success':
        return $r('app.media.success')
      case 'error':
        return $r('app.media.error')
    }
  }

  getTypeColor() {
    switch (this.type) {
      case 'success':
        return $r('app.color.green')
      case 'error':
        return $r('app.color.red')
    }
  }

  build() {
    Column({ space: 12 }) {
      Image(this.getTypeImage())
        .width(45)
        .height(45)
        .fillColor(this.getTypeColor())
      Text(this.message)
        .fontSize(15)
        .lineHeight(21)
        .fontColor($r('app.color.font_1'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width(160)
    .padding(24)
    .backgroundColor($r('app.color.grey_3'))
    .borderRadius(12)
  }
}

export class Toast {
  // 记录定时器句柄，便于在重复弹出时清理旧定时器
  private static timer: number = -1;

  private static createDialog(message: ResourceStr, type: 'success' | 'error'): CustomDialogController {
    return new CustomDialogController({
      builder: ToastDialog({
        type,
        message
      }),
      alignment: DialogAlignment.Center,
      customStyle: true,
    })
  }

  static success(message: ResourceStr, duration: number = 2000): void {
    Toast.show(message, 'success', duration);
  }

  static error(message: ResourceStr, duration: number = 2000): void {
    Toast.show(message, 'error', duration);
  }

  private static show(message: ResourceStr, type: 'success' | 'error', duration: number): void {
    const dialog = Toast.createDialog(message, type);
    dialog.open();
    if (Toast.timer >= 0) {
      clearTimeout(Toast.timer);
      Toast.timer = -1;
    }
    Toast.timer = setTimeout(() => {
      dialog.close();
      Toast.timer = -1;
    }, duration);
  }
}
