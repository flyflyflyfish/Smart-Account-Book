import router from '@ohos.router';
import dayjs from 'dayjs';
import Home from '../views/home';
import Stats from '../views/stats';
import PreferenceUtil from '../utils/PreferenceUtil';
import DBUtil from '../utils/DBUtil';
import * as CONSTANTS from '../common/constants';
import BreakpointSystem from '../utils/BreakpointSystem';
import BreakpointConstants from '../common/breakpoint';
import { SPACE_MEDIUM } from '../common/dimens';

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  private breakpointSystem: BreakpointSystem = new BreakpointSystem();
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  async aboutToAppear() {
    this.breakpointSystem.register();
    // 等待首选项与数据库初始化完成，避免读取到未初始化的数据
    await DBUtil.ready;
    const firstUseTime = Number(await PreferenceUtil.getPreferenceValue(CONSTANTS.PREF_USER_FIRST_KEY, 0));
    if (!firstUseTime) {
      PreferenceUtil.putPreferenceValue(CONSTANTS.PREF_USER_FIRST_KEY, dayjs().valueOf());
    }
  }

  aboutToDisappear() {
    this.breakpointSystem.unRegister();
  }

  @Builder TabBarBuilder(title: ResourceStr, image: ResourceStr, index: number) {
    Column({ space: 8 }) {
      Image(image)
        .width(20)
        .height(20)
        .fillColor(this.currentTab === index ? $r('app.color.green') : $r('app.color.font_1'))
      Text(title)
        .fontSize(14)
        .fontColor(this.currentTab === index ? $r('app.color.green') : $r('app.color.font_1'))
    }
  }

  build() {
    Stack({ alignContent: BreakpointConstants.addBtn_stack_align.getValue(this.currentBreakpoint) }) {
      Tabs({ barPosition: BreakpointConstants.bar_position.getValue(this.currentBreakpoint) }) {
        TabContent(){
          Home()
            .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
        }.tabBar(this.TabBarBuilder($r('app.string.home'), $r('app.media.home'), 0))

        TabContent(){
          Stats()
            .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
        }.tabBar(this.TabBarBuilder($r('app.string.statistics'), $r('app.media.stats'), 1))
      }
      .height('100%')
      .width('100%')
      .vertical(BreakpointConstants.bar_vertical.getValue(this.currentBreakpoint))
      .backgroundColor($r('app.color.bg'))
      .onChange((index) => {
        this.currentTab = index;
      })
      Column({ space: SPACE_MEDIUM }) {
        // 图片记账入口：拍照/选图识别账单
        Column() {
          Image($r('app.media.camera'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.green'))
        }.width(BreakpointConstants.addBtn_stack_size.getValue(this.currentBreakpoint))
        .height(BreakpointConstants.addBtn_stack_size.getValue(this.currentBreakpoint))
        .backgroundColor($r('app.color.white'))
        .borderRadius(BreakpointConstants.addBtn_stack_size.getValue(this.currentBreakpoint) / 2)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          router.pushUrl({
            url: 'pages/RecognizeBill'
          })
        })
        Column() {
          Image($r('app.media.add'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.font_1'))
        }.width(BreakpointConstants.addBtn_stack_size.getValue(this.currentBreakpoint))
        .height(BreakpointConstants.addBtn_stack_size.getValue(this.currentBreakpoint))
        .backgroundColor($r('app.color.green'))
        .borderRadius(BreakpointConstants.addBtn_stack_size.getValue(this.currentBreakpoint) / 2)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          router.pushUrl({
            url: 'pages/AddAccount'
          })
        })
      }.margin({
        bottom: this.currentBreakpoint === BreakpointConstants.BREAKPOINT_SM ? 20 : 0,
        left: this.currentBreakpoint !== BreakpointConstants.BREAKPOINT_SM ? 15 : 0,
      })
    }
  }
}