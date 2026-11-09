import router from '@ohos.router';
import dayjs from 'dayjs';
import StatsHeader from '../components/stats/StatsHeader';
import StatsDetailHeader from '../components/stats/StatsDetailHeader';
import { StatsType, CategoryType } from '../models/stats/stats';
import { AccountType, StatsByDate, StatsByType, StatsData } from '../models/account/account';
import AccountService from '../service/account';
import StatsService from '../service/stats';
import BillStore, { BillChangeListener } from '../common/BillStore';
import CategoryStore from '../models/accountType/CategoryStore';
import { AccountDetailParams } from '../pages/AccountDetail';
import { Logger } from '../utils/Logger';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY, SPACE_XLARGE } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

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

  @StorageProp('themeSeq') @Watch('onThemeChanged') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }
  @State @Watch('statsAccountData') statsType: StatsType = StatsType.MONTH;
  @State @Watch('statsAccountData') time: number = dayjs().valueOf();
  @State accountType: AccountType = AccountType.EXPENSES;
  @State expenses: number = 0;
  @State income: number = 0;
  @State dateStatsData: StatsData<StatsByDate> = { expenses: [], income: [] };
  @State typeStatsData: StatsData<StatsByType> = { expenses: [], income: [] };
  // 必须是 @State：作为 if 分支条件时只有可观察状态变化才会触发分支切换
  @State categoryType: CategoryType = CategoryType.DATE;
  // 饼图当前选中的扇区下标（-1 未选中），点击扇区放大并显示该分类详情
  @State selectedPieIndex: number = -1;
  // 柱状图当前选中的条目下标（-1 未选中），点击/滑动柱子查看单日（月）金额
  @State selectedBarIndex: number = -1;
  // 每柱占位宽（柱宽+间隙），点击/滑动换算定位用
  private barUnitWidth: number = 0;
  // 饼图画布：onReady 前绘制无效，用 pieReady 标记
  private pieSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private pieContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.pieSettings);
  private pieReady: boolean = false;
  // 按日期柱状图画布：月账单按日、年账单按月
  private barSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private barContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.barSettings);
  private barReady: boolean = false;
  // 账单增删后由 BillStore 通知刷新
  private billListener: BillChangeListener = () => {
    this.statsAccountData();
  };

  async statsAccountData(): Promise<void> {
    try {
      // 数据集变化后原选中扇区/柱子可能失效，先取消选中
      this.selectedPieIndex = -1;
      this.selectedBarIndex = -1;
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
      this.drawBars();
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

  // 主题切换后重绘图表，保证画布色值与当前调色板一致
  onThemeChanged(): void {
    this.drawPie();
    this.drawBars();
  }

  // 图表色阶：按序取主色不同明度，超出档位后循环（饼图与列表同序对应，随主题走）
  chartColor(index: number): string {
    const chart = this.tk().chart;
    return chart[index % chart.length];
  }

  // 自绘环形饼图：扇区颜色取各分类的和谐色（色相随分类、观感与主题色阶一致），
  // 与列表进度条同色对应，选中扇区外扩放大
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
      const ringWidth = PIE_OUTER_RADIUS - PIE_INNER_RADIUS;
      let startAngle = -Math.PI / 2;
      list.forEach((item: StatsByType, index: number) => {
        const endAngle = startAngle + item.amount / total * Math.PI * 2;
        const selected = index === this.selectedPieIndex;
        ctx.beginPath();
        ctx.arc(center, center, selected ? ringRadius + 4 : ringRadius, startAngle, endAngle);
        ctx.lineWidth = selected ? ringWidth + 8 : ringWidth;
        ctx.strokeStyle = this.chartColor(index);
        ctx.stroke();
        startAngle = endAngle;
      });
      Logger.debug('饼图绘制完成, 分段数: ', list.length);
    } catch (err) {
      Logger.error('饼图绘制失败', (err as Error).message);
    }
  }

  // 点击饼图：命中扇区则选中（再点一次取消），点击环带外/环心空白取消选中
  onPieClick(event: ClickEvent): void {
    const center = PIE_SIZE / 2;
    const dx = event.x - center;
    const dy = event.y - center;
    const distance = Math.sqrt(dx * dx + dy * dy);
    const list = this.currentTypeStats();
    let total = 0;
    list.forEach((item: StatsByType) => {
      total += item.amount;
    });
    if (total <= 0) {
      return;
    }
    if (distance > PIE_OUTER_RADIUS + 6 || distance < PIE_INNER_RADIUS - 4) {
      if (this.selectedPieIndex !== -1) {
        this.selectedPieIndex = -1;
        this.drawPie();
      }
      return;
    }
    // 换算成 12 点方向起、顺时针增长的角度比例
    let angle = Math.atan2(dy, dx) + Math.PI / 2;
    if (angle < 0) {
      angle += Math.PI * 2;
    }
    const ratio = angle / (Math.PI * 2);
    let acc = 0;
    let hit = -1;
    for (let i = 0; i < list.length; i++) {
      acc += list[i].amount / total;
      if (ratio < acc) {
        hit = i;
        break;
      }
    }
    if (hit === -1) {
      hit = list.length - 1;
    }
    this.selectedPieIndex = hit === this.selectedPieIndex ? -1 : hit;
    this.drawPie();
  }

  // 饼图选中项是否仍有效（列表可能因切换口径/时间段而变化）
  pieSelectionValid(): boolean {
    return this.selectedPieIndex >= 0 && this.selectedPieIndex < this.currentTypeStats().length;
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

  // 分类下钻：查看该时间段内此分类的账单明细，标题用分类名
  toAccountDetailByType(item: StatsByType): void {
    const isMonth = this.statsType === StatsType.MONTH;
    const startTime = isMonth
      ? dayjs(this.time).startOf('month').valueOf()
      : dayjs(this.time).startOf('year').valueOf();
    const endTime = isMonth
      ? dayjs(this.time).endOf('month').valueOf()
      : dayjs(this.time).endOf('year').valueOf();
    const params: AccountDetailParams = {
      startTime: startTime,
      endTime: endTime,
      accountType: this.accountType,
      typeId: item.info.id,
      title: CategoryStore.nameText(item.info.id, this.accountType)
    };
    router.pushUrl({
      url: 'pages/AccountDetail',
      params: params
    })
  }

  // 支出/收入双列汇总：左支出右收入，点击切换当前口径
  // 选中侧大字号加粗、未选中侧小字号弱化，切换时层级随之上移
  @Builder SummaryRow() {
    Row({ space: SPACE_LARGE }) {
      Column({ space: SPACE_TINY }) {
        Text(this.statsType === StatsType.MONTH ? $r('app.string.month_expense_label') : $r('app.string.year_expense_label'))
          .fontSize(this.fs(12))
          .lineHeight(this.fs(16))
          .fontWeight(this.accountType === AccountType.EXPENSES ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.accountType === AccountType.EXPENSES ? this.tk().primary : this.tk().textSecondary)
          .opacity(this.accountType === AccountType.EXPENSES ? 1 : 0.7)
        Text('¥ ' + this.expenses.toFixed(2))
          .fontSize(this.fs(this.accountType === AccountType.EXPENSES ? 26 : 15))
          .lineHeight(this.fs(this.accountType === AccountType.EXPENSES ? 32 : 20))
          .fontWeight(this.accountType === AccountType.EXPENSES ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.accountType === AccountType.EXPENSES ? this.tk().textPrimary : this.tk().textSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => this.switchAccountType(AccountType.EXPENSES))

      Divider()
        .vertical(true)
        .strokeWidth(1)
        .height(36)
        .color(this.tk().surfaceVariant)

      Column({ space: SPACE_TINY }) {
        Text(this.statsType === StatsType.MONTH ? $r('app.string.month_income_label') : $r('app.string.year_income_label'))
          .fontSize(this.fs(12))
          .lineHeight(this.fs(16))
          .fontWeight(this.accountType === AccountType.INCOME ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.accountType === AccountType.INCOME ? this.tk().primary : this.tk().textSecondary)
          .opacity(this.accountType === AccountType.INCOME ? 1 : 0.7)
        Text('¥ ' + this.income.toFixed(2))
          .fontSize(this.fs(this.accountType === AccountType.INCOME ? 26 : 15))
          .lineHeight(this.fs(this.accountType === AccountType.INCOME ? 32 : 20))
          .fontWeight(this.accountType === AccountType.INCOME ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.accountType === AccountType.INCOME ? this.tk().textPrimary : this.tk().textSecondary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => this.switchAccountType(AccountType.INCOME))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // 切换支出/收入口径并同步重绘两个图表
  switchAccountType(type: AccountType): void {
    if (this.accountType === type) {
      return;
    }
    this.accountType = type;
    this.selectedPieIndex = -1;
    this.selectedBarIndex = -1;
    this.drawPie();
    this.drawBars();
  }

  // 按日期条目当前口径下的金额
  dateItemAmount(item: StatsByDate): number {
    return this.accountType === AccountType.EXPENSES ? item.expenses : item.income;
  }

  // 当前口径下最高单日/单月金额，用于柱状图刻度和列表进度条
  maxDateAmount(): number {
    let max = 0;
    this.currentDateStats().forEach((item: StatsByDate) => {
      const amount = this.dateItemAmount(item);
      if (amount > max) {
        max = amount;
      }
    });
    return max;
  }

  // 条目相对峰值的比例（0-100），比占总比例更能体现各条目间的差距
  dateItemPercentOfMax(item: StatsByDate): number {
    const max = this.maxDateAmount();
    if (max <= 0) {
      return 0;
    }
    return Math.min(100, this.dateItemAmount(item) / max * 100);
  }

  // 日均/月均金额：总额除以当月天数或全年 12 个月
  avgDateAmount(): number {
    const buckets = this.statsType === StatsType.MONTH ? dayjs(this.time).daysInMonth() : 12;
    return this.currentTotal() / buckets;
  }

  // 峰值日期文案（如 "3日" / "5月"），无数据返回空串
  peakDateLabel(): string {
    let peakTime = 0;
    let peakAmount = 0;
    this.currentDateStats().forEach((item: StatsByDate) => {
      if (this.dateItemAmount(item) > peakAmount) {
        peakAmount = this.dateItemAmount(item);
        peakTime = item.time;
      }
    });
    if (peakTime <= 0) {
      return '';
    }
    return this.statsType === StatsType.MONTH ? dayjs(peakTime).format('D') + '日' : dayjs(peakTime).format('M') + '月';
  }

  // 自绘柱状图：月账单按日、年账单按月；柱子颜色与下方列表行同序取图表色阶，
  // 支持点击/滑动选中单柱（选中柱全亮、其余淡化聚焦）
  drawBars(): void {
    if (!this.barReady || this.categoryType !== CategoryType.DATE) {
      return;
    }
    try {
      const ctx = this.barContext;
      ctx.clearRect(0, 0, ctx.width, ctx.height);
      const isMonth = this.statsType === StatsType.MONTH;
      const buckets = isMonth ? dayjs(this.time).daysInMonth() : 12;
      const values: number[] = [];
      const listIndexOf: number[] = [];
      for (let i = 0; i < buckets; i++) {
        values.push(0);
        listIndexOf.push(-1);
      }
      let maxValue = 0;
      const list = this.currentDateStats();
      list.forEach((item: StatsByDate, index: number) => {
        const bucket = isMonth ? dayjs(item.time).date() - 1 : dayjs(item.time).month();
        if (bucket >= 0 && bucket < buckets) {
          values[bucket] += this.dateItemAmount(item);
          listIndexOf[bucket] = index;
          if (values[bucket] > maxValue) {
            maxValue = values[bucket];
          }
        }
      });
      if (maxValue <= 0) {
        return;
      }
      const gap = buckets > 16 ? 2 : 6;
      const barWidth = (ctx.width - gap * (buckets - 1)) / buckets;
      this.barUnitWidth = barWidth + gap;
      const chartHeight = ctx.height - 2;
      for (let bucket = 0; bucket < buckets; bucket++) {
        const value = values[bucket];
        if (value <= 0) {
          continue;
        }
        const listIndex = listIndexOf[bucket];
        const barHeight = Math.max(3, value / maxValue * chartHeight);
        const x = bucket * this.barUnitWidth;
        const y = ctx.height - barHeight;
        // 顶部圆角柱体：矩形 + 半圆顶盖，比直角更柔和
        const radius = Math.min(3, barWidth / 2, barHeight / 2);
        ctx.fillStyle = this.chartColor(listIndex);
        ctx.globalAlpha = this.selectedBarIndex === -1 || listIndex === this.selectedBarIndex ? 1 : 0.4;
        ctx.beginPath();
        ctx.arc(x + barWidth / 2, y + radius, radius, Math.PI, 0);
        ctx.lineTo(x + barWidth, ctx.height);
        ctx.lineTo(x, ctx.height);
        ctx.closePath();
        ctx.fill();
      }
      ctx.globalAlpha = 1;
      Logger.debug('柱状图绘制完成, 柱数: ', String(buckets));
    } catch (err) {
      Logger.error('柱状图绘制失败', (err as Error).message);
    }
  }

  // 点击/滑动柱状图：换算触点所在柱并选中；点空白柱区取消选中
  selectBarAt(x: number): void {
    if (!this.barReady || this.barUnitWidth <= 0) {
      return;
    }
    const isMonth = this.statsType === StatsType.MONTH;
    const buckets = isMonth ? dayjs(this.time).daysInMonth() : 12;
    const bucket = Math.floor(x / this.barUnitWidth);
    if (bucket < 0 || bucket >= buckets) {
      return;
    }
    const list = this.currentDateStats();
    let listIndex = -1;
    for (let i = 0; i < list.length; i++) {
      const itemBucket = isMonth ? dayjs(list[i].time).date() - 1 : dayjs(list[i].time).month();
      if (itemBucket === bucket) {
        listIndex = i;
        break;
      }
    }
    // 空白天（月）区域：取消选中
    if (listIndex === -1) {
      if (this.selectedBarIndex !== -1) {
        this.selectedBarIndex = -1;
        this.drawBars();
      }
      return;
    }
    if (listIndex !== this.selectedBarIndex) {
      this.selectedBarIndex = listIndex;
      this.drawBars();
    }
  }

  // 选中柱（单日/单月）的标签，如 "3日" / "5月"
  selectedBarLabel(): string {
    const item = this.currentDateStats()[this.selectedBarIndex];
    return this.statsType === StatsType.MONTH ? dayjs(item.time).format('D') + '日' : dayjs(item.time).format('M') + '月';
  }

  // 选中柱是否仍有效
  barSelectionValid(): boolean {
    return this.selectedBarIndex >= 0 && this.selectedBarIndex < this.currentDateStats().length;
  }

  // 柱状图 + 摘要：一眼看出花销趋势与极值；点/滑柱子可查看单日（月）金额
  @Builder DateBarChart() {
    Column() {
      Canvas(this.barContext)
        .width('100%')
        .height(104)
        .onReady(() => {
          this.barReady = true;
          this.drawBars();
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down || event.type === TouchType.Move) {
            this.selectBarAt(event.touches[0].x);
          }
        })
      Row({ space: SPACE_XLARGE }) {
        Column({ space: 2 }) {
          if (this.barSelectionValid()) {
            Text(this.selectedBarLabel())
              .fontSize(this.fs(11))
              .lineHeight(this.fs(14))
              .fontColor(this.tk().textSecondary)
            Text('¥ ' + this.dateItemAmount(this.currentDateStats()[this.selectedBarIndex]).toFixed(2))
              .fontSize(this.fs(14))
              .lineHeight(this.fs(18))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.tk().primary)
          } else {
            Text(this.avgLabel())
              .fontSize(this.fs(11))
              .lineHeight(this.fs(14))
              .fontColor(this.tk().textSecondary)
            Text('¥ ' + this.avgDateAmount().toFixed(2))
              .fontSize(this.fs(14))
              .lineHeight(this.fs(18))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.tk().textPrimary)
          }
        }.alignItems(HorizontalAlign.Start)

        Column({ space: 2 }) {
          Text($r('app.string.stats_peak'))
            .fontSize(this.fs(11))
            .lineHeight(this.fs(14))
            .fontColor(this.tk().textSecondary)
          Text(this.peakDateLabel() + ' ¥ ' + this.maxDateAmount().toFixed(2))
            .fontSize(this.fs(14))
            .lineHeight(this.fs(18))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tk().primary)
        }.alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .margin({ top: SPACE_SMALL })
    }
    .width('100%')
    .margin({ top: SPACE_MEDIUM })
  }

  // 日均/月均标签
  avgLabel(): ResourceStr {
    return this.statsType === StatsType.MONTH ? $r('app.string.stats_avg_daily') : $r('app.string.stats_avg_monthly');
  }

  // 按日期条目：日期 | 相对峰值进度条 | 金额，行高与按分类条目一致
  @Builder DateStatsItem(item: StatsByDate, index: number) {
    Row({ space: SPACE_MEDIUM }) {
      Text(this.statsType === StatsType.MONTH ? dayjs(item.time).format('D') + '日' : dayjs(item.time).format('M') + '月')
        .fontSize(this.fs(14))
        .lineHeight(this.fs(19))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tk().textSecondary)
        .width(36)

      Progress({
        value: this.dateItemPercentOfMax(item),
        type: ProgressType.Linear,
        total: 100
      })
        .layoutWeight(1)
        .color(this.chartColor(index))
        .backgroundColor(this.tk().surfaceVariant)
        .style({ strokeWidth: 4 })

      Text((this.accountType === AccountType.EXPENSES ? '-' : '+') + this.dateItemAmount(item).toFixed(2))
        .fontSize(this.fs(15))
        .lineHeight(this.fs(20))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tk().textPrimary)
    }.width('100%')
    .padding({ top: 15, bottom: 15 })
    .onClick(() => this.toAccountDetail(item.time))
  }

  @Builder TypeStatsItem(item: StatsByType, index: number) {
    Row({ space: 8 }) {
      Column() {
        Image(item.info.icon)
          .height(14)
          .objectFit(ImageFit.Contain)
          .fillColor(this.tk().surface)
      }.width(30)
      .height(30)
      .backgroundColor(item.info.activeColor)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(15)
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(item.info.name)
            .fontBasicStyle(this.fs(14), this.fs(19), this.tk().textPrimary)
            .fontWeight(500)
          Text($r('app.string.count_unit', item.count))
            .fontBasicStyle(this.fs(12), this.fs(15), this.tk().textSecondary)
          Blank()
          Text(item.amount.toFixed(2))
            .fontBasicStyle(this.fs(15), this.fs(20), this.tk().textPrimary)
            .fontWeight(500)
        }.width('100%')
        Progress({
          value: item.amount / (this.accountType === AccountType.EXPENSES ? this.expenses : this.income) * 100,
          type: ProgressType.Linear,
          total: 100,
        }).width('100%')
          .color(this.chartColor(index))
          .style({ strokeWidth: 4 })
      }.layoutWeight(1)
      Image($r('app.media.arrow_left'))
        .rotate({ angle: 180 })
        .height(14)
        .objectFit(ImageFit.Contain)
        .fillColor(this.tk().textSecondary)
    }.width('100%')
    .padding({ top: 10, bottom: 10 })
    .onClick(() => this.toAccountDetailByType(item))
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
      // 选中扇区时环心显示该分类的名称/金额/占比，未选中显示总额
      if (this.pieSelectionValid()) {
        Column({ space: SPACE_TINY }) {
          Text(this.currentTypeStats()[this.selectedPieIndex].info.name)
            .fontSize(this.fs(12))
            .lineHeight(this.fs(16))
            .fontColor(this.tk().textSecondary)
          Text('¥ ' + this.currentTypeStats()[this.selectedPieIndex].amount.toFixed(2))
            .fontSize(this.fs(16))
            .lineHeight(this.fs(20))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tk().textPrimary)
          Text((this.currentTypeStats()[this.selectedPieIndex].amount / this.currentTotal() * 100).toFixed(1) + '%')
            .fontSize(this.fs(12))
            .lineHeight(this.fs(16))
            .fontColor(this.tk().textSecondary)
        }
      } else {
        Column({ space: SPACE_TINY }) {
          Text(this.accountType === AccountType.EXPENSES ? $r('app.string.all_expenses') : $r('app.string.all_income'))
            .fontSize(this.fs(12))
            .fontColor(this.tk().textSecondary)
          Text('¥ ' + this.currentTotal().toFixed(2))
            .fontSize(this.fs(16))
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tk().textPrimary)
        }
      }
    }.width(PIE_SIZE)
    .height(PIE_SIZE)
    .margin({ top: SPACE_MEDIUM })
    .onClick((event: ClickEvent) => this.onPieClick(event))
  }

  // 无数据占位
  @Builder EmptyHint() {
    Column({ space: SPACE_SMALL }) {
      Text($r('app.string.stats_empty'))
        .fontBasicStyle(this.fs(13), this.fs(18), this.tk().textSecondary)
      Text($r('app.string.stats_empty_sub'))
        .fontBasicStyle(this.fs(12), this.fs(16), this.tk().textSecondary)
        .opacity(0.7)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: SPACE_XLARGE, bottom: SPACE_XLARGE })
  }

  build() {
    // 与首页一致的自上而下层级：
    // 时间段选择行 → 支出/收入双列汇总（点击切换口径）→ 明细卡片
    Column({ space: SPACE_MEDIUM }) {
      StatsHeader({ type: this.statsType, time: this.time })

      this.SummaryRow()

      Scroll() {
        Column() {
          // 明细卡
          Column() {
            StatsDetailHeader({
              onChange: (type: CategoryType) => {
                this.categoryType = type;
                this.statsAccountData();
              }
            })
            if (this.categoryType === CategoryType.DATE) {
              if (this.currentDateStats().length) {
                this.DateBarChart()
                Divider().color(this.tk().surfaceVariant).margin({ top: SPACE_MEDIUM + 2 })
                List() {
                  ForEach(this.currentDateStats(), (item: StatsByDate, index: number) => {
                    ListItem() {
                      this.DateStatsItem(item, index);
                    }
                  }, (item: StatsByDate): string => item.time.toString() + '_' + JSON.stringify(item))
                }.divider({ color: this.tk().surfaceVariant, strokeWidth: 1 })
              } else {
                Divider().color(this.tk().surfaceVariant).margin({ top: SPACE_MEDIUM + 2 })
                this.EmptyHint()
              }
            } else {
              if (this.currentTypeStats().length) {
                this.PieChart()
                Divider().color(this.tk().surfaceVariant).margin({ top: SPACE_MEDIUM + 2 })
                List() {
                  ForEach(this.currentTypeStats(), (item: StatsByType, index: number) => {
                    ListItem() {
                      this.TypeStatsItem(item, index)
                    }
                  }, (item: StatsByType): string => item.info.id.toString() + '_' + JSON.stringify(item))
                }.divider({ color: this.tk().surfaceVariant, strokeWidth: 1 })
              } else {
                Divider().color(this.tk().surfaceVariant).margin({ top: SPACE_MEDIUM + 2 })
                this.EmptyHint()
              }
            }
          }.width('100%')
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
          .padding(SPACE_LARGE)
        }
        .width('100%')
        .padding({ bottom: SPACE_MEDIUM })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .layoutWeight(1)
    }.width('100%')
    .height('100%')
    .padding({ left: SPACE_LARGE, right: SPACE_LARGE })
  }
}
