import router from '@ohos.router';
import dayjs from 'dayjs';
import AccountNavigator from '../components/Navigator';
import AccountService from '../service/account';
import StatsService from '../service/stats';
import AccountPO from '../models/account/accountPO';
import { AccountType, GroupByDate, ItemRecordInfo } from '../models/account/account';
import AccountTypeModel from '../models/accountType/AccountTypeModel';
import CategoryStore from '../models/accountType/CategoryStore';
import AccountItem from '../components/AccountItem';
import GroupHeader from '../components/GroupHeader';
import { Logger } from '../utils/Logger';
import DBUtil from '../utils/DBUtil';
import {
  PAGE_PADDING,
  RADIUS_CARD,
  SPACE_LARGE,
  SPACE_MEDIUM,
  SPACE_SMALL,
  SPACE_TINY
} from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

// 分类 chip 数据：分类模型 + 所属收支侧（两侧分类 id 均从 0 编号，必须靠 side 区分）
interface CategoryChipInfo {
  model: AccountTypeModel;
  side: AccountType;
}

/**
 * 全局账单搜索页：默认搜全部账单，
 * 可按时间段 / 收支类型 / 分类 / 关键字（备注、商家、分类名）筛选，
 * 筛选项与“账本-从账单导入”保持一致。
 */
@Entry
@Component
struct BillSearch {

  @StorageProp('themeSeq') themeSeq: number = 0;
  // 搜索关键字（备注 / 商家 / 分类名模糊匹配）
  @State keyword: string = '';
  // 时间段筛选：0 本月 / 1 近三月 / 2 今年 / 3 全部 / 4 自定义（默认本月，避免全量查询太慢）
  @State rangeIndex: number = 0;
  // 类型筛选：0 全部 / 1 支出 / 2 收入
  @State typeIndex: number = 0;
  // 分类筛选：-1 全部分类，其余为分类 id；配合 categoryFilterSide（所属收支侧）才能唯一定位
  @State categoryFilter: number = -1;
  @State categoryFilterSide: number = -1;
  // 自定义时间段起止（rangeIndex=4 时生效）
  @State customStart: number = 0;
  @State customEnd: number = 0;
  // 搜索结果：按日分组，样式对齐首页
  @State groupList: GroupByDate[] = [];
  @State resultCount: number = 0;
  @State expenses: number = 0;
  @State income: number = 0;
  @State loading: boolean = true;

  // 当前时间段内的全量账单（数据库查询结果），关键字/类型/分类在内存中过滤，避免逐键重查
  private allBills: AccountPO[] = [];

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  // 时间段筛选的查询起点
  rangeStart(): number {
    if (this.rangeIndex === 0) {
      return dayjs().startOf('month').valueOf();
    }
    if (this.rangeIndex === 1) {
      return dayjs().subtract(2, 'month').startOf('month').valueOf();
    }
    if (this.rangeIndex === 2) {
      return dayjs().startOf('year').valueOf();
    }
    if (this.rangeIndex === 4) {
      return this.customStart;
    }
    return 0;
  }

  // 时间段筛选的查询终点：自定义段到所选结束日的当天末尾（分步选择未完成时按当前时间）
  rangeEnd(): number {
    if (this.rangeIndex === 4) {
      return this.customEnd > 0 ? this.customEnd : Date.now();
    }
    return Date.now();
  }

  rangeLabel(index: number): ResourceStr {
    if (index === 0) {
      return $r('app.string.ledger_filter_month');
    }
    if (index === 1) {
      return $r('app.string.ledger_filter_3m');
    }
    if (index === 2) {
      return $r('app.string.ledger_filter_year');
    }
    if (index === 4) {
      return $r('app.string.ledger_filter_custom');
    }
    return $r('app.string.ledger_filter_all');
  }

  typeLabel(index: number): ResourceStr {
    if (index === 1) {
      return $r('app.string.expenditure');
    }
    if (index === 2) {
      return $r('app.string.income');
    }
    return $r('app.string.ledger_filter_all');
  }

  // 当前类型筛选下可选的分类 chip：支出/收入取对应侧，全部时合并两侧（带 side 区分）
  categoryChips(): CategoryChipInfo[] {
    const chips: CategoryChipInfo[] = [];
    if (this.typeIndex === 2) {
      for (const model of CategoryStore.list(AccountType.INCOME)) {
        chips.push({ model: model, side: AccountType.INCOME });
      }
      return chips;
    }
    for (const model of CategoryStore.list(AccountType.EXPENSES)) {
      chips.push({ model: model, side: AccountType.EXPENSES });
    }
    if (this.typeIndex === 0) {
      for (const model of CategoryStore.list(AccountType.INCOME)) {
        chips.push({ model: model, side: AccountType.INCOME });
      }
    }
    return chips;
  }

  // 账单的排序/显示时间：优先支付时间，兼容老数据
  billTime(bill: AccountPO): number {
    return bill.payTime > 0 ? bill.payTime : bill.time;
  }

  // 关键字匹配：备注 → 商家 → 分类名
  matchKeyword(bill: AccountPO, keyword: string): boolean {
    if (bill.description.toLowerCase().includes(keyword)) {
      return true;
    }
    if (bill.merchant.toLowerCase().includes(keyword)) {
      return true;
    }
    return CategoryStore.nameText(bill.type, bill.accountType).toLowerCase().includes(keyword);
  }

  // 按时间段重查数据库，随后套用内存过滤
  async loadBills(): Promise<void> {
    try {
      await DBUtil.ready;
      this.allBills = await AccountService.queryByDateRange(this.rangeStart(), this.rangeEnd());
    } catch (err) {
      Logger.error('搜索账单失败', (err as Error).message);
      this.allBills = [];
    } finally {
      this.loading = false;
      this.refilter();
    }
  }

  // 内存过滤：类型 → 分类 → 关键字，并按日分组统计
  refilter(): void {
    let filtered = this.allBills;
    if (this.typeIndex !== 0) {
      filtered = filtered.filter((bill: AccountPO): boolean =>
        bill.accountType === (this.typeIndex === 1 ? AccountType.EXPENSES : AccountType.INCOME));
    }
    if (this.categoryFilter >= 0) {
      filtered = filtered.filter((bill: AccountPO): boolean =>
        bill.type === this.categoryFilter && bill.accountType === this.categoryFilterSide);
    }
    const keyword = this.keyword.trim().toLowerCase();
    if (keyword.length > 0) {
      filtered = filtered.filter((bill: AccountPO): boolean => this.matchKeyword(bill, keyword));
    }
    // 按支付时间倒序，保证分组内新的在前
    filtered.sort((a: AccountPO, b: AccountPO): number => this.billTime(b) - this.billTime(a));
    const groups = StatsService.groupByDate(filtered);
    let count = 0;
    let expenses = 0;
    let income = 0;
    groups.forEach((group: GroupByDate) => {
      count += group.records.length;
      expenses = Math.round((expenses + group.expenses) * 100) / 100;
      income = Math.round((income + group.income) * 100) / 100;
    });
    this.groupList = groups;
    this.resultCount = count;
    this.expenses = expenses;
    this.income = income;
  }

  // 切换时间段筛选：清空分类并重查数据库
  applyRange(range: number): void {
    if (this.rangeIndex === range) {
      return;
    }
    this.rangeIndex = range;
    this.categoryFilter = -1;
    this.categoryFilterSide = -1;
    this.loading = true;
    this.loadBills();
  }

  // 切换类型筛选：清空分类后内存过滤
  applyType(type: number): void {
    if (this.typeIndex === type) {
      return;
    }
    this.typeIndex = type;
    this.categoryFilter = -1;
    this.categoryFilterSide = -1;
    this.refilter();
  }

  // 切换分类筛选：内存过滤（id + 收支侧唯一定位分类）
  applyCategoryFilter(item: CategoryChipInfo | null): void {
    const id = item === null ? -1 : item.model.id;
    const side = item === null ? -1 : item.side;
    if (this.categoryFilter === id && this.categoryFilterSide === side) {
      return;
    }
    this.categoryFilter = id;
    this.categoryFilterSide = side;
    this.refilter();
  }

  // 分类 chip 是否选中：null 表示“全部分类”
  isCategorySelected(item: CategoryChipInfo | null): boolean {
    if (item === null) {
      return this.categoryFilter === -1;
    }
    return this.categoryFilter === item.model.id && this.categoryFilterSide === item.side;
  }

  // 自定义时间段第 1 步：选开始日（页内引导，选完停在“选结束日”步骤）
  showCustomStartPicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-1-1'),
      end: new Date(),
      selected: new Date(this.customStart > 0 ? this.customStart : Date.now()),
      onDateAccept: (value: Date) => {
        this.customStart = dayjs(value).startOf('day').valueOf();
      }
    });
  }

  // 自定义时间段第 2 步：选结束日（早于开始日时按同一天处理），选完立即重查
  showCustomEndPicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-1-1'),
      end: new Date(),
      selected: new Date(this.customStart > 0 ? this.customStart : Date.now()),
      onDateAccept: (value: Date) => {
        const end = dayjs(value).startOf('day').valueOf();
        this.customEnd = end >= this.customStart ? dayjs(end).endOf('day').valueOf()
          : dayjs(this.customStart).endOf('day').valueOf();
        this.loading = true;
        this.loadBills();
      }
    });
  }

  // 重新选择自定义区间：清空起止回到第 1 步
  resetCustomPick(): void {
    this.customStart = 0;
    this.customEnd = 0;
  }

  // 点击结果进入编辑页（与首页一致，经 AppStorage 传参）
  openEditPage(record: ItemRecordInfo): void {
    AppStorage.setOrCreate('editRecord', record);
    router.pushUrl({ url: 'pages/AddAccount' }).catch((err: Error): void => {
      Logger.error('跳转编辑页失败', err.message);
    });
  }

  aboutToAppear(): void {
    this.loadBills();
  }

  // 从编辑页返回时刷新结果（编辑/删除后保持结果最新）
  onPageShow(): void {
    if (!this.loading) {
      this.loadBills();
    }
  }

  @Builder SearchBar() {
    Row({ space: SPACE_SMALL }) {
      Image($r('app.media.search'))
        .width(16)
        .height(16)
        .objectFit(ImageFit.Contain)
        .fillColor(this.tk().textSecondary)
      TextInput({ placeholder: $r('app.string.search_placeholder'), text: this.keyword })
        .placeholderColor(this.tk().textSecondary)
        .placeholderFont({ size: this.fs(13) })
        .fontSize(this.fs(13))
        .layoutWeight(1)
        .padding({ top: 0, bottom: 0 })
        .backgroundColor(this.tk().surface)
        .caretColor(this.tk().primary)
        .onChange((val: string) => {
          this.keyword = val;
          this.refilter();
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM })
    .borderRadius(RADIUS_CARD)
    .backgroundColor(this.tk().surface)
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
    .margin({ left: PAGE_PADDING, right: PAGE_PADDING })
  }

  @Builder RangeChip(index: number) {
    Text(this.rangeLabel(index))
      .fontSize(this.fs(12))
      .fontColor(this.rangeIndex === index ? this.tk().onPrimary : this.tk().textSecondary)
      .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM, top: 6, bottom: 6 })
      .borderRadius(999)
      .backgroundColor(this.rangeIndex === index ? this.tk().primary : this.tk().surfaceVariant)
      .onClick(() => {
        if (index === 4) {
          // 已选完区间时点击清空重选；否则进入自定义模式，由页内提示行引导分步选起止
          if (this.rangeIndex === 4 && this.customStart > 0) {
            this.resetCustomPick();
          } else {
            this.applyRange(4);
          }
          return;
        }
        this.applyRange(index);
      })
  }

  @Builder TypeChip(index: number) {
    Text(this.typeLabel(index))
      .fontSize(this.fs(12))
      .fontColor(this.typeIndex === index ? this.tk().onPrimary : this.tk().textSecondary)
      .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM, top: 6, bottom: 6 })
      .borderRadius(999)
      .backgroundColor(this.typeIndex === index ? this.tk().primary : this.tk().surfaceVariant)
      .onClick(() => {
        this.applyType(index);
      })
  }

  // 分类筛选 chip：item 为 null 表示“全部分类”
  @Builder CategoryChip(item: CategoryChipInfo | null) {
    Text(item === null ? $r('app.string.ledger_filter_all') : item.model.name)
      .fontSize(this.fs(12))
      .fontColor(this.isCategorySelected(item) ? this.tk().onPrimary : this.tk().textSecondary)
      .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM, top: 6, bottom: 6 })
      .borderRadius(999)
      .backgroundColor(this.isCategorySelected(item) ? this.tk().primary : this.tk().surfaceVariant)
      .onClick(() => {
        this.applyCategoryFilter(item);
      })
  }

  // 分类筛选行：横向滚动，“全部” + 当前类型侧的分类
  @Builder CategoryFilterRow() {
    Scroll() {
      Row({ space: SPACE_SMALL }) {
        this.CategoryChip(null)
        ForEach(this.categoryChips(), (item: CategoryChipInfo) => {
          this.CategoryChip(item)
        }, (item: CategoryChipInfo) => 'search_category_' + item.side + '_' + item.model.id)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .align(Alignment.Start)
  }

  // 自定义时间段的分步引导胶囊：按当前步骤跳转对应选择器或重选
  @Builder CustomPickHint(label: ResourceStr) {
    Text(label)
      .fontSize(this.fs(11))
      .fontColor(this.tk().primary)
      .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM, top: 4, bottom: 4 })
      .backgroundColor(this.tk().primarySoft)
      .borderRadius(999)
      .onClick(() => {
        if (this.customStart <= 0) {
          this.showCustomStartPicker();
        } else if (this.customEnd <= 0) {
          this.showCustomEndPicker();
        } else {
          this.resetCustomPick();
        }
      })
  }

  // 筛选卡：时间段 + 类型 + 分类；常显，切换筛选不隐藏（避免加载时闪动）
  @Builder FilterCard() {
    Column({ space: SPACE_SMALL }) {
      Row({ space: SPACE_SMALL }) {
        this.RangeChip(0)
        this.RangeChip(1)
        this.RangeChip(2)
        this.RangeChip(3)
        this.RangeChip(4)
      }
      Row({ space: SPACE_SMALL }) {
        this.TypeChip(0)
        this.TypeChip(1)
        this.TypeChip(2)
      }
      this.CategoryFilterRow()
      // 自定义时间段分步引导：未选开始→引导选开始；已选开始→引导选结束；选完显示区间可重选
      if (this.rangeIndex === 4) {
        if (this.customStart <= 0) {
          this.CustomPickHint($r('app.string.ledger_custom_pick_start'))
        } else if (this.customEnd <= 0) {
          this.CustomPickHint($r('app.string.ledger_custom_pick_end',
            dayjs(this.customStart).format('YYYY-MM-DD')))
        } else {
          this.CustomPickHint($r('app.string.ledger_custom_range',
            dayjs(this.customStart).format('YYYY-MM-DD'), dayjs(this.customEnd).format('YYYY-MM-DD')))
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_MEDIUM, bottom: SPACE_MEDIUM })
    .backgroundColor(this.tk().surface)
    .borderRadius(RADIUS_CARD)
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
    .margin({ left: PAGE_PADDING, right: PAGE_PADDING, top: SPACE_MEDIUM })
  }

  // 结果汇总行：共几笔、支出与收入合计
  @Builder ResultSummary() {
    Text($r('app.string.search_result_summary', this.resultCount,
      this.expenses.toFixed(2), this.income.toFixed(2)))
      .fontSize(this.fs(12))
      .fontColor(this.tk().textSecondary)
      .margin({ left: PAGE_PADDING, right: PAGE_PADDING, top: SPACE_MEDIUM })
  }

  // ListItemGroup 的 header 需要 CustomBuilder：包一层 @Builder 传入组件
  @Builder GroupHeaderBuilder(group: GroupByDate) {
    GroupHeader({ group: group })
  }

  @Builder ResultList() {
    List() {
      ForEach(this.groupList, (group: GroupByDate) => {
        ListItemGroup({ header: this.GroupHeaderBuilder(group) }) {
          ForEach(group.records, (record: ItemRecordInfo) => {
            ListItem() {
              AccountItem({ account: record })
            }
            .onClick(() => {
              this.openEditPage(record);
            })
          }, (record: ItemRecordInfo): string => 'search_record_' + record.id + '_' + JSON.stringify(record))
        }
      }, (group: GroupByDate): string => 'search_group_' + group.time + '_' + JSON.stringify(group.records))
    }
    .width('100%')
    .layoutWeight(1)
    .divider({ strokeWidth: 1, color: this.tk().surfaceVariant })
    .backgroundColor(this.tk().surface)
    .borderRadius(RADIUS_CARD)
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
    .padding(SPACE_LARGE)
    .margin({ bottom: SPACE_LARGE })
  }

  @Builder EmptyView() {
    Column({ space: SPACE_MEDIUM }) {
      Image($r('app.media.empty'))
        .width(80)
        .objectFit(ImageFit.Contain)
      Text($r('app.string.search_no_result'))
        .fontSize(this.fs(13))
        .lineHeight(this.fs(18))
        .fontColor(this.tk().textSecondary)
    }
    .width('100%')
    .margin({ top: 60 })
  }

  build() {
    Column() {
      AccountNavigator({ title: $r('app.string.search_bills_title') })
      // 固定头部：搜索框 + 筛选卡 + 汇总，不随结果滚动
      Column() {
        this.SearchBar()
        this.FilterCard()
        if (this.groupList.length > 0) {
          this.ResultSummary()
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      // 结果列表独立滚动（不能嵌套在 Scroll 里，否则 List 全量渲染导致加载慢）
      if (this.groupList.length > 0) {
        this.ResultList()
      } else if (this.loading) {
        Column({ space: SPACE_MEDIUM }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.tk().primary)
          Text($r('app.string.loading_tip'))
            .fontSize(this.fs(13))
            .fontColor(this.tk().textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          this.EmptyView()
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }
}
