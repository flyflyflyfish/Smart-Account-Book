import router from '@ohos.router'
import { ThemeKit, ThemePalette } from '../common/theme/Theme';
@Component
export default struct AccountNavigator {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }
  title: ResourceStr = $r('app.string.back');

  build() {
    Row(){
      Row({ space: 8 }) {
        Image($r('app.media.arrow_left'))
          .height(14)
          .objectFit(ImageFit.Cover)
          .fillColor(this.tk().textPrimary)
        Text(this.title)
          .fontSize(this.fs(16))
          .fontWeight(500)
          .fontColor(this.tk().textPrimary)
      }.onClick(() => {
        router.back();
      })
    }.width('100%')
    .height(44)
    .padding({ left: 24 })
  }
}
