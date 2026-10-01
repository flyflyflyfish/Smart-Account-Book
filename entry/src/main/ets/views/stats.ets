import router from '@ohos.router';
import dayjs from 'dayjs';
import StatsHeader from '../components/stats/StatsHeader';
import StatsDetailHeader from '../components/stats/StatsDetailHeader';
import { StatsType, CategoryType } from '../models/stats/stats';
import { AccountType, StatsByDate, StatsByType, StatsData } from '../models/account/account';
import AccountService from '../service/account';
import StatsService from '../service/stats';
import BillStore, { BillChangeListener } from '../common/BillStore';
import { AccountDetailParams } from '../pages/AccountDetail';
import { Logger } from '../utils/Logger';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_TINY } from '../common/dimens';

@Extend(Text) function fontBasicStyle(size: number, lineHeight: number, color: ResourceStr) {
  .fontSize(size)
  .fontColor(color)
  .lineHeight(lineHeight)
}

// 饼图尺寸与内外半径
const PIE_SIZE: number = 180;
const PIE_OUTER_RADIUS: number = 80;
const PIE_INNER_RADIUS: number = 56;

@Component
export default struct Stats {
  @State @Watch('statsAccountData') statsType: StatsType = StatsType.MONTH;
  @State @Watch('statsAccountData') time: number = dayjs().valueOf();
  @State accountType: AccountType = AccountType.EXPENSES;
  @State expenses: number = 0;
  @State income: number = 0;
  @State dateStatsData: StatsData<StatsByDate> = { expenses: [], income: [] };
  @State typeStatsData: StatsData<StatsByType> = { expenses: [], income: [] };
  // 必须是 @State：作为 if 分支条件时只有可观察状态变化才会触发分支切换
  @State categoryType: CategoryType = CategoryType.DATE;
  // 饼图画布：onReady 前绘制无效，用 pieReady 标记
  private pieSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private pieContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.pieSettings);
  private pieReady: boolean = false;
  // 账单增删后由 BillStore 通知刷新
  private billListener: BillChangeListener = () => {
    this.statsAccountData();
  };

  async statsAccountData(): Promise<void> {
    try {
      // 月账单按日统计、年账单按月统计，查询与统计逻辑合并避免重复
      const isMonth = this.statsType === StatsType.MONTH;
      const res = isMonth
        ? await AccountService.getAccountByMonth(this.time)
        : await AccountService.getAccountByYear(this.time);
      if (this.categoryType === CategoryType.DATE) {
        const result = isMonth ? StatsService.statsConsumeByDate(res) : StatsService.statsConsumeByMonth(res);
        this.expenses = result.expenses;
        this.income = result.income;
        this.dateStatsData = result.data;
      } else {
        const result = StatsService.statsConsumeByType(res);
        this.expenses = result.expenses;
        this.income = result.income;
        this.typeStatsData = result.data;
      }
      this.drawPie();
    } catch (err) {
      Logger.error('统计数据加载失败', (err as Error).message);
    }
  }

  aboutToAppear(): void {
    BillStore.subscribe(this.billListener);
    this.statsAccountData()
  }

  aboutToDisappear(): void {
    BillStore.unsubscribe(this.billListener);
  }

  currentDateStats(): StatsByDate[] {
    return this.accountType === AccountType.EXPENSES ? this.dateStatsData.expenses : this.dateStatsData.income;
  }

  currentTypeStats(): StatsByType[] {
    return this.accountType === AccountType.EXPENSES ? this.typeStatsData.expenses : this.typeStatsData.income;
  }

  currentTotal(): number {
    return this.accountType === AccountType.EXPENSES ? this.expenses : this.income;
  }

  // Canvas fillStyle 直接给数值色值可能解析异常，统一转成 #RRGGBB 字符串
  resolveColor(color: ResourceStr): string {
    if (typeof color === 'string') {
      return color;
    }
    // 平台色值为 0xAARRGGBB，取低 24 位拼成 Canvas 可识别的 #RRGGBB
    const colorNum: number = typeof color === 'number'
      ? color
      : getContext(this).resourceManager.getColorSync(color);
    return '#' + (colorNum & 0xFFFFFF).toString(16).padStart(6, '0');
  }

  // 自绘环形饼图：按分类占比分段，颜色取分类激活色
  drawPie(): void {
    if (!this.pieReady || this.categoryType !== CategoryType.TYPE) {
      return;
    }
    try {
      const ctx = this.pieContext;
      ctx.clearRect(0, 0, PIE_SIZE, PIE_SIZE);
      const list = this.currentTypeStats();
      let total = 0;
      list.forEach((item: StatsByType) => {
        total += item.amount;
      });
      if (total <= 0) {
        return;
      }
      // 描边式圆环：单条 arc 加粗描边，比分段 path 填充更稳定
      const center = PIE_SIZE / 2;
      const ringRadius = (PIE_OUTER_RADIUS + PIE_INNER_RADIUS) / 2;
      ctx.lineWidth = PIE_OUTER_RADIUS - PIE_INNER_RADIUS;
      let startAngle = -Math.PI / 2;
      list.forEach((item: StatsByType) => {
        const endAngle = startAngle + item.amount / total * Math.PI * 2;
        ctx.beginPath();
        ctx.arc(center, center, ringRadius, startAngle, endAngle);
        ctx.strokeStyle = this.resolveColor(item.info.activeColor);
        ctx.stroke();
        startAngle = endAngle;
      });
      Logger.debug('饼图绘制完成, 分段数: ', list.length);
    } catch (err) {
      Logger.error('饼图绘制失败', (err as Error).message);
    }
  }

  toAccountDetail(time: number): void {
    let startTime: number = 0;
    let endTime: number = 0;
    if (this.statsType === StatsType.MONTH) {
      startTime = dayjs(time).startOf('day').valueOf();
      endTime = dayjs(time).endOf('day').valueOf()
    } else {
      startTime = dayjs(time).startOf('month').valueOf();
      endTime = dayjs(time).endOf('month').valueOf();
    }
    const params: AccountDetailParams = {
      startTime: startTime,
      endTime: endTime,
      accountType: this.accountType
    };
    router.pushUrl({
      url: 'pages/AccountDetail',
      params: params
    })
  }

  @Builder TotalStats() {
    Row() {
      Column({ space: 8 }) {
        Text(this.statsType === StatsType.MONTH ? $r('app.string.month_expense_label') : $r('app.string.year_expense_label'))
          .fontBasicStyle(12, 14, this.accountType === AccountType.EXPENSES ? $r('app.color.font_1') : $r('app.color.font_2'))
        Text('¥ ' + this.expenses.toFixed(2))
          .fontBasicStyle(24, 30, this.accountType === AccountType.EXPENSES ? $r('app.color.font_1') : $r('app.color.font_2'))
      }.layoutWeight(1)
      .onClick(() => {
        this.accountType = AccountType.EXPENSES;
        this.drawPie();
      })
      Column({ space: 8 }) {
        Text(this.statsType === StatsType.MONTH ? $r('app.string.month_income_label') : $r('app.string.year_income_label'))
          .fontBasicStyle(12, 14, this.accountType === AccountType.INCOME ? $r('app.color.font_1') : $r('app.color.font_2'))
        Text('¥ ' + this.income.toFixed(2))
          .fontBasicStyle(24, 30, this.accountType === AccountType.INCOME ? $r('app.color.font_1') : $r('app.color.font_2'))
      }.layoutWeight(1)
      .onClick(() => {
        this.accountType = AccountType.INCOME;
        this.drawPie();
      })
    }.width('100%')
  }

  @Builder DateStatsItem(item: StatsByDate) {
    Row({ space: 20 }) {
      Column({ space: 2 }) {
        Text(dayjs(item.time).format(this.statsType === StatsType.MONTH ? 'DD日' : 'MM月'))
          .fontBasicStyle(16, 22, $r('app.color.font_3'))
          .fontWeight(500)
        Text(dayjs(item.time).format(this.statsType === StatsType.MONTH ? 'YYYY.MM' : 'YYYY'))
          .fontBasicStyle(12, 15, $r('app.color.font_2'))
      }.alignItems(HorizontalAlign.Start)
      Column({ space: 4 }) {
        Text(this.accountType === AccountType.EXPENSES ? '-' + item.expenses.toFixed(2) : item.income.toFixed(2))
          .fontBasicStyle(16, 20, $r('app.color.font_3'))
          .fontWeight(500)
        Row({ space: 8 }) {
          Text(this.accountType === AccountType.EXPENSES ? $r('app.string.all_expenses') : $r('app.string.all_income'))
            .fontBasicStyle(12, 15, this.accountType === AccountType.EXPENSES ? $r('app.color.green') : $r('app.color.orange'))
          Text(this.accountType === AccountType.EXPENSES ? this.expenses.toFixed(2) : this.income.toFixed(2))
            .fontBasicStyle(12, 15, $r('app.color.font_2'))
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Image($r('app.media.arrow_left'))
        .rotate({ angle: 180 })
        .height(14)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.font_2'))
    }.width('100%')
    .padding({ top: 10, bottom: 10 })
    .onClick(() => this.toAccountDetail(item.time))
  }

  @Builder TypeStatsItem(item: StatsByType) {
    Row({ space: 8 }) {
      Column() {
        Image(item.info.icon)
          .height(14)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.white'))
      }.width(30)
      .height(30)
      .backgroundColor(item.info.activeColor)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(15)
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(item.info.name)
            .fontBasicStyle(16, 22, $r('app.color.font_3'))
            .fontWeight(500)
          Text($r('app.string.count_unit', item.count))
            .fontBasicStyle(12, 15, $r('app.color.font_2'))
          Blank()
          Text(item.amount.toFixed(2))
            .fontBasicStyle(16, 22, $r('app.color.font_3'))
            .fontWeight(500)
        }.width('100%')
        Progress({
          value: item.amount / (this.accountType === AccountType.EXPENSES ? this.expenses : this.income) * 100,
          type: ProgressType.Linear,
          total: 100,
        }).width('100%')
          .color(item.info.activeColor)
          .style({ strokeWidth: 4 })
      }.layoutWeight(1)
    }.width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  @Builder PieChart() {
    Stack() {
      Canvas(this.pieContext)
        .width(PIE_SIZE)
        .height(PIE_SIZE)
        .onReady(() => {
          this.pieReady = true;
          this.drawPie();
        })
      Column({ space: SPACE_TINY }) {
        Text(this.accountType === AccountType.EXPENSES ? $r('app.string.all_expenses') : $r('app.string.all_income'))
          .fontSize(12)
          .fontColor($r('app.color.font_2'))
        Text('¥ ' + this.currentTotal().toFixed(2))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.font_3'))
      }
    }.width(PIE_SIZE)
    .height(PIE_SIZE)
    .margin({ top: SPACE_MEDIUM })
  }

  build() {
    Column({ space: 20 }) {
      StatsHeader({ type: this.statsType, time: this.time })
      this.TotalStats()
      Column() {
        StatsDetailHeader({
          onChange: (type: CategoryType) => {
            this.categoryType = type;
            this.statsAccountData();
          }
        })
        if (this.categoryType === CategoryType.DATE) {
          if (this.currentDateStats().length) {
            Divider().color($r('app.color.grey_1')).margin({ top: 14 })
            List() {
              ForEach(this.currentDateStats(), (item: StatsByDate) => {
                ListItem() {
                  this.DateStatsItem(item);
                }
              })
            }.divider({ color: $r('app.color.grey_1'), strokeWidth: 1 })
          }
        } else {
          if (this.currentTypeStats().length) {
            this.PieChart()
            Divider().color($r('app.color.grey_1')).margin({ top: 14 })
            List() {
              ForEach(this.currentTypeStats(), (item: StatsByType) => {
                ListItem() {
                  this.TypeStatsItem(item)
                }
              })
            }.divider({ color: $r('app.color.grey_1'), strokeWidth: 1 })
          }
        }
      }.width('100%')
      .backgroundColor($r('app.color.white'))
      .borderRadius(RADIUS_CARD)
      .padding(SPACE_LARGE)
    }.width('100%')
    .height('100%')
    .padding({ left: SPACE_LARGE, right: SPACE_LARGE })
  }
}
