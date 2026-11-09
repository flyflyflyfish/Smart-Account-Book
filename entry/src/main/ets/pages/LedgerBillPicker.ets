import router from '@ohos.router';
import dayjs from 'dayjs';
import AccountNavigator from '../components/Navigator';
import AccountService from '../service/account';
import LedgerRepository from '../data/LedgerRepository';
import LedgerStore from '../common/LedgerStore';
import AccountPO from '../models/account/accountPO';
import { AccountType } from '../models/account/account';
import AccountTypeModel from '../models/accountType/AccountTypeModel';
import CategoryStore from '../models/accountType/CategoryStore';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import DBUtil from '../utils/DBUtil';
import BreakpointConstants from '../common/breakpoint';
import {
  PAGE_PADDING,
  RADIUS_CARD,
  RADIUS_ICON,
  SPACE_LARGE,
  SPACE_MEDIUM,
  SPACE_SMALL,
  SPACE_TINY
} from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

/**
 * 从现有账单勾选导入页路由参数
 */
interface LedgerBillPickerParams {
  id: string;
}

// 分类 chip 数据：分类模型 + 所属收支侧（两侧分类 id 均从 0 编号，必须靠 side 区分）
interface CategoryChipInfo {
  model: AccountTypeModel;
  side: AccountType;
}

/**
 * 从现有账单中勾选导入到账本：主账单不动，勾选项复制为账本记录。
 * 已导入过的账单（通过 bill_id 关联识别）置灰不可再选，防止重复导入。
 */
@Entry
@Component
struct LedgerBillPicker {

  @StorageProp('themeSeq') themeSeq: number = 0;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  @State billList: AccountPO[] = [];
  // 已导入过本账本的主账单 id 集合
  @State importedIds: string[] = [];
  @State selectedIds: string[] = [];
  @State loading: boolean = true;
  // 时间段筛选：0 本月 / 1 近三月 / 2 今年 / 3 全部 / 4 自定义（默认本月，缩小首次查询范围）
  @State rangeIndex: number = 0;
  // 类型筛选：0 全部 / 1 支出 / 2 收入
  @State typeIndex: number = 0;
  // 分类筛选：-1 全部分类，其余为分类 id；配合 categoryFilterSide（所属收支侧）才能唯一定位
  @State categoryFilter: number = -1;
  @State categoryFilterSide: number = -1;
  // 自定义时间段起止（rangeIndex=4 时生效）
  @State customStart: number = 0;
  @State customEnd: number = 0;
  // 搜索关键字：对已加载的账单做备注 / 商家 / 分类名模糊过滤
  @State keyword: string = '';
  // 导入进行中标志：await 期间双击“导入”会重复插入账本记录
  @State importing: boolean = false;

  private ledgerId: string = '';
  private repository: LedgerRepository = new LedgerRepository();

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as LedgerBillPickerParams | undefined;
    this.ledgerId = params && typeof params.id === 'string' ? params.id : '';
    await this.loadBills();
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

  // 切换筛选：清空勾选与分类（当前筛选外的账单不参与导入）并重查
  applyFilter(range: number, type: number): void {
    if (this.rangeIndex === range && this.typeIndex === type && this.categoryFilter < 0) {
      return;
    }
    this.rangeIndex = range;
    this.typeIndex = type;
    this.categoryFilter = -1;
    this.categoryFilterSide = -1;
    this.selectedIds = [];
    this.loading = true;
    this.loadBills();
  }

  // 切换分类筛选：清空勾选并重查（id + 收支侧唯一定位分类）
  applyCategoryFilter(item: CategoryChipInfo | null): void {
    const id = item === null ? -1 : item.model.id;
    const side = item === null ? -1 : item.side;
    if (this.categoryFilter === id && this.categoryFilterSide === side) {
      return;
    }
    this.categoryFilter = id;
    this.categoryFilterSide = side;
    this.selectedIds = [];
    this.loading = true;
    this.loadBills();
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
        this.selectedIds = [];
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

  async loadBills(): Promise<void> {
    try {
      await DBUtil.ready;
      const bills = await AccountService.queryByDateRange(this.rangeStart(), this.rangeEnd());
      // 类型过滤：0 全部 / 1 支出 / 2 收入
      let filtered = this.typeIndex === 0 ? bills : bills.filter((bill: AccountPO): boolean =>
        bill.accountType === (this.typeIndex === 1 ? AccountType.EXPENSES : AccountType.INCOME));
      // 分类过滤：-1 不限（id + 收支侧唯一定位，避免两侧同 id 分类误匹配）
      if (this.categoryFilter >= 0) {
        filtered = filtered.filter((bill: AccountPO): boolean =>
          bill.type === this.categoryFilter && bill.accountType === this.categoryFilterSide);
      }
      // 按支付时间倒序，老数据 payTime 为 0 时回退记录日期
      filtered.sort((a: AccountPO, b: AccountPO): number => this.billTime(b) - this.billTime(a));
      this.billList = filtered;
      this.importedIds = await this.repository.queryImportedBillIds(this.ledgerId);
    } catch (err) {
      Logger.error('加载账单列表失败', (err as Error).message);
    } finally {
      this.loading = false;
    }
  }

  // 账单的排序/显示时间：优先支付时间，兼容老数据
  billTime(bill: AccountPO): number {
    return bill.payTime > 0 ? bill.payTime : bill.time;
  }

  isImported(bill: AccountPO): boolean {
    return this.importedIds.indexOf(bill.id) >= 0;
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

  // 关键字过滤后的展示列表：关键字为空时原样返回
  displayBills(): AccountPO[] {
    const keyword = this.keyword.trim().toLowerCase();
    if (keyword.length === 0) {
      return this.billList;
    }
    return this.billList.filter((bill: AccountPO): boolean => this.matchKeyword(bill, keyword));
  }

  // 展示列表中的支出合计
  displayExpenses(): number {
    let sum = 0;
    this.displayBills().forEach((bill: AccountPO) => {
      if (bill.accountType === AccountType.EXPENSES) {
        sum += bill.amount;
      }
    });
    return sum;
  }

  // 展示列表中的收入合计
  displayIncome(): number {
    let sum = 0;
    this.displayBills().forEach((bill: AccountPO) => {
      if (bill.accountType === AccountType.INCOME) {
        sum += bill.amount;
      }
    });
    return sum;
  }

  // 用 checked 入参做幂等更新，避免“全选”时 onChange 反复取反
  toggleSelect(id: string, checked: boolean): void {
    const idx = this.selectedIds.indexOf(id);
    if (checked) {
      if (idx < 0) {
        this.selectedIds.push(id);
        this.selectedIds = this.selectedIds.slice();
      }
    } else {
      if (idx >= 0) {
        this.selectedIds.splice(idx, 1);
        this.selectedIds = this.selectedIds.slice();
      }
    }
  }

  // 可选项 = 未导入过且匹配当前搜索的账单
  selectableCount(): number {
    let count = 0;
    this.displayBills().forEach((bill: AccountPO) => {
      if (!this.isImported(bill)) {
        count++;
      }
    });
    return count;
  }

  toggleSelectAll(): void {
    const selectable: string[] = [];
    this.displayBills().forEach((bill: AccountPO) => {
      if (!this.isImported(bill)) {
        selectable.push(bill.id);
      }
    });
    if (this.selectedIds.length === selectable.length) {
      this.selectedIds = [];
    } else {
      this.selectedIds = selectable;
    }
  }

  // 行主文案：描述 → 商家 → 分类名
  billTitleText(bill: AccountPO): string {
    if (bill.description.length > 0) {
      return bill.description;
    }
    if (bill.merchant.length > 0) {
      return bill.merchant;
    }
    return CategoryStore.nameText(bill.type, bill.accountType);
  }

  // 复制勾选账单为账本记录：主账单不动，关联 bill_id 防重复导入
  async doImport(): Promise<void> {
    if (this.importing) {
      return;
    }
    if (this.selectedIds.length === 0) {
      Toast.error($r('app.string.require_select'));
      return;
    }
    this.importing = true;
    try {
      let imported = 0;
      for (const bill of this.displayBills()) {
        if (this.selectedIds.indexOf(bill.id) < 0) {
          continue;
        }
        await this.repository.insertRecord(this.ledgerId, bill.accountType, bill.amount,
          this.billTitleText(bill), this.billTime(bill), bill.type, bill.id);
        imported++;
      }
      LedgerStore.notifyChanged();
      Toast.success($r('app.string.ledger_import_success', imported));
      router.back();
    } catch (err) {
      Logger.error('导入账单到账本失败', (err as Error).message);
      Toast.error($r('app.string.save_failed'));
    } finally {
      this.importing = false;
    }
  }

  @Builder BillItem(bill: AccountPO) {
    Row({ space: SPACE_MEDIUM }) {
      if (this.isImported(bill)) {
        // 已导入：占位保持与 Checkbox 同宽，行置灰
        Column()
          .width(20)
          .height(20)
      } else {
        // 纯展示勾选态：不响应触摸，避免 Checkbox.onChange 与行 onClick 冒泡双取反
        Checkbox()
          .select(this.selectedIds.indexOf(bill.id) >= 0)
          .hitTestBehavior(HitTestMode.None)
      }

      Column() {
        Image(CategoryStore.getById(bill.type, bill.accountType).icon)
          .width(16)
          .objectFit(ImageFit.Contain)
          .fillColor(this.tk().surface)
      }.width(36)
      .height(36)
      .backgroundColor(CategoryStore.getById(bill.type, bill.accountType).activeColor)
      .borderRadius(RADIUS_ICON)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)

      Column({ space: SPACE_TINY }) {
        Text(this.billTitleText(bill))
          .fontColor(this.isImported(bill) ? this.tk().textSecondary : this.tk().textPrimary)
          .fontSize(this.fs(15))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(dayjs(this.billTime(bill)).format('YYYY-MM-DD HH:mm'))
          .fontSize(this.fs(12))
          .lineHeight(this.fs(14))
          .fontColor(this.tk().textSecondary)
      }.alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.isImported(bill)) {
        Text($r('app.string.ledger_imported_tag'))
          .fontSize(this.fs(11))
          .fontColor(this.tk().textSecondary)
          .padding({ left: SPACE_SMALL, right: SPACE_SMALL, top: SPACE_TINY, bottom: SPACE_TINY })
          .backgroundColor(this.tk().surfaceVariant)
          .borderRadius(999)
      } else {
        Text((bill.accountType === 0 ? '-' : '+') + bill.amount.toFixed(2))
          .fontColor(bill.accountType === 0 ? this.tk().textPrimary : this.tk().primary)
          .fontWeight(FontWeight.Medium)
          .fontSize(this.fs(16))
      }
    }
    .width('100%')
    .height(56)
    .opacity(this.isImported(bill) ? 0.55 : 1)
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
            this.applyFilter(4, this.typeIndex);
          }
          return;
        }
        this.applyFilter(index, this.typeIndex);
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
        this.applyFilter(this.rangeIndex, index);
      })
  }

  // 分类筛选 chip：item 为 null 表示"全部分类"
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

  // 分类筛选行：横向滚动，"全部" + 当前类型侧的分类
  @Builder CategoryFilterRow() {
    Scroll() {
      Row({ space: SPACE_SMALL }) {
        this.CategoryChip(null)
        ForEach(this.categoryChips(), (item: CategoryChipInfo) => {
          this.CategoryChip(item)
        }, (item: CategoryChipInfo) => 'pick_category_' + item.side + '_' + item.model.id)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .align(Alignment.Start)
  }

  // 筛选卡：搜索框 + 时间段 + 类型 + 分类；常显，切换筛选或加载中不隐藏（避免筛选栏闪动消失）
  @Builder FilterCard() {
    Column({ space: SPACE_SMALL }) {
      // 搜索框：对已加载账单按备注 / 商家 / 分类名过滤
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
          .backgroundColor(this.tk().surfaceVariant)
          .caretColor(this.tk().primary)
          .onChange((val: string) => {
            this.keyword = val;
            // 关键字变化后勾选可能指向不可见账单，清空避免“导入数与可见数不符”
            this.selectedIds = [];
          })
      }
      .width('100%')
      .height(40)
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
    .margin({ left: PAGE_PADDING, right: PAGE_PADDING, top: SPACE_LARGE })
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

  // 结果汇总行：共几笔、支出与收入合计（与全局搜索页一致）
  @Builder ResultSummary() {
    Text($r('app.string.search_result_summary', this.displayBills().length,
      this.displayExpenses().toFixed(2), this.displayIncome().toFixed(2)))
      .fontSize(this.fs(12))
      .fontColor(this.tk().textSecondary)
      .margin({ left: PAGE_PADDING, right: PAGE_PADDING, top: SPACE_MEDIUM })
  }

  @Builder EmptyView() {
    Column({ space: SPACE_MEDIUM }) {
      Image($r('app.media.empty'))
        .width(80)
        .objectFit(ImageFit.Contain)
      Text($r('app.string.ledger_no_bills'))
        .fontSize(this.fs(13))
        .lineHeight(this.fs(18))
        .fontColor(this.tk().textSecondary)
    }
    .width('100%')
    .margin({ top: 60 })
  }

  build() {
    Column() {
      AccountNavigator({ title: $r('app.string.ledger_pick_title') })
      this.FilterCard()
      if (this.displayBills().length > 0) {
        this.ResultSummary()
        // 结果列表独立滚动（不能嵌套在 Scroll 里，否则 List 全量渲染导致加载慢）
        List() {
          ForEach(this.displayBills(), (bill: AccountPO) => {
            ListItem() {
              this.BillItem(bill)
            }
            .onClick(() => {
              if (!this.isImported(bill)) {
                this.toggleSelect(bill.id, !(this.selectedIds.indexOf(bill.id) >= 0));
              }
            })
          }, (bill: AccountPO): string => 'pick_bill_' + bill.id + '_' +
            (this.selectedIds.indexOf(bill.id) >= 0 ? 1 : 0) +
            (this.isImported(bill) ? 1 : 0))
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: this.tk().surfaceVariant })
        .backgroundColor(this.tk().surface)
        .borderRadius(RADIUS_CARD)
        .padding(SPACE_LARGE)
        .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
        .margin({ left: PAGE_PADDING, right: PAGE_PADDING, top: SPACE_MEDIUM })
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
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else if (this.billList.length > 0) {
        // 有关键字但无匹配账单
        Column({ space: SPACE_MEDIUM }) {
          Text($r('app.string.search_no_result'))
            .fontSize(this.fs(13))
            .lineHeight(this.fs(18))
            .fontColor(this.tk().textSecondary)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        Scroll() {
          this.EmptyView()
        }
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .layoutWeight(1)
        .width('100%')
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: SPACE_LARGE })
      }

      // 底部操作栏：全选（仅未导入项）+ 导入
      Row({ space: SPACE_MEDIUM }) {
        Button(this.selectedIds.length === this.selectableCount()
          ? $r('app.string.cancel_select_all') : $r('app.string.select_all'))
          .layoutWeight(1)
          .height(44)
          .fontSize(this.fs(15))
          .backgroundColor(this.tk().surface)
          .fontColor(this.tk().textPrimary)
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .onClick(() => {
            this.toggleSelectAll();
          })
        Button($r('app.string.ledger_import_count', this.selectedIds.length))
          .layoutWeight(1)
          .height(44)
          .fontSize(this.fs(15))
          .backgroundColor(this.tk().primary)
          .fontColor(this.tk().onPrimary)
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .enabled(!this.importing)
          .opacity(this.importing ? 0.6 : 1)
          .onClick(() => {
            this.doImport();
          })
      }
      .width('100%')
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: SPACE_MEDIUM, bottom: SPACE_LARGE })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }
}
