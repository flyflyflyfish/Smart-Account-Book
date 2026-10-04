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
  // 当前弹出的 Toast：重复弹出时先关闭旧的，避免旧弹窗永久残留
  private static current: CustomDialogController | undefined = undefined;
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

  // 关闭指定 Toast：宿主页面可能已销毁（如 Toast 后立即 router.back），close 需兜底
  private static closeQuietly(dialog: CustomDialogController): void {
    try {
      dialog.close();
    } catch (err) {
      // 忽略：页面已销毁时 close 可能抛错
    }
  }

  static success(message: ResourceStr, duration: number = 2000): void {
    Toast.show(message, 'success', duration);
  }

  static error(message: ResourceStr, duration: number = 2000): void {
    Toast.show(message, 'error', duration);
  }

  private static show(message: ResourceStr, type: 'success' | 'error', duration: number): void {
    // 先关闭上一个 Toast 并清掉它的关闭定时器
    if (Toast.timer >= 0) {
      clearTimeout(Toast.timer);
      Toast.timer = -1;
    }
    const prev = Toast.current;
    if (prev) {
      Toast.closeQuietly(prev);
      Toast.current = undefined;
    }
    const dialog = Toast.createDialog(message, type);
    Toast.current = dialog;
    dialog.open();
    Toast.timer = setTimeout(() => {
      const cur = Toast.current;
      if (cur) {
        Toast.closeQuietly(cur);
        Toast.current = undefined;
      }
      Toast.timer = -1;
    }, duration);
  }
}
