import { ThemeKit, ThemePalette } from '../common/theme/Theme';
@CustomDialog
export default struct ToastDialog {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }
  controller: CustomDialogController;
  message: ResourceStr = '';
  type: 'error' | 'success' = 'success';

  getTypeImage(): Resource {
    switch (this.type) {
      case 'success':
        return $r('app.media.success')
      case 'error':
        return $r('app.media.error')
    }
  }

  getTypeColor(): string {
    switch (this.type) {
      case 'success':
        return this.tk().primary
      case 'error':
        return this.tk().danger
    }
  }

  build() {
    Column({ space: 12 }) {
      Image(this.getTypeImage())
        .width(45)
        .height(45)
        .fillColor(this.getTypeColor())
      Text(this.message)
        .fontSize(this.fs(15))
        .lineHeight(this.fs(21))
        .fontColor(this.tk().surface)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width(160)
    .padding(24)
    .backgroundColor(this.tk().toastBg)
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
