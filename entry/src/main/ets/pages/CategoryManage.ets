import AccountNavigator from '../components/Navigator';
import CategoryStore, {
  CATEGORY_COLOR_OPTIONS,
  CATEGORY_ICON_OPTIONS,
  CATEGORY_NAME_MAX_LENGTH,
  CategoryColorOption,
  CategoryIconOption
} from '../models/accountType/CategoryStore';
import AccountTypeModel from '../models/accountType/AccountTypeModel';
import { AccountType } from '../models/account/account';
import { Toast } from '../components/ToastDialog';
import BreakpointConstants from '../common/breakpoint';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY, SPACE_XLARGE } from '../common/dimens';

/**
 * 分类管理：账单的支出/收入分类支持自定义
 * - 新增分类（名称 + 图标 + 颜色）
 * - 删除分类（默认分类仅隐藏，历史账单不受影响）
 * - 恢复默认分类
 */
@Entry
@Component
struct CategoryManage {
  @State currentIndex: number = 0;
  @State expenseList: AccountTypeModel[] = CategoryStore.list(AccountType.EXPENSES);
  @State incomeList: AccountTypeModel[] = CategoryStore.list(AccountType.INCOME);
  @State showAddSheet: boolean = false;
  @State newCategoryName: string = '';
  @State selectedIconKey: string = 'meals';
  @State selectedColorKey: string = 'green';
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  aboutToAppear(): void {
    this.refresh();
  }

  refresh(): void {
    this.expenseList = CategoryStore.list(AccountType.EXPENSES);
    this.incomeList = CategoryStore.list(AccountType.INCOME);
  }

  currentAccountType(): AccountType {
    return this.currentIndex === 0 ? AccountType.EXPENSES : AccountType.INCOME;
  }

  currentList(): AccountTypeModel[] {
    return this.currentIndex === 0 ? this.expenseList : this.incomeList;
  }

  switchSide(index: number): void {
    if (this.currentIndex === index) {
      return;
    }
    this.currentIndex = index;
    this.resetAddForm();
  }

  resetAddForm(): void {
    this.newCategoryName = '';
    this.selectedIconKey = 'meals';
    this.selectedColorKey = 'green';
  }

  // 新增分类：非空、长度与重名校验后写入存储
  confirmAdd(): void {
    const name = this.newCategoryName.trim();
    if (name.length === 0) {
      Toast.error($r('app.string.category_name_required'));
      return;
    }
    if (name.length > CATEGORY_NAME_MAX_LENGTH) {
      Toast.error($r('app.string.category_name_too_long'));
      return;
    }
    const accountType = this.currentAccountType();
    if (CategoryStore.listNames(accountType).indexOf(name) >= 0) {
      Toast.error($r('app.string.category_name_duplicated'));
      return;
    }
    CategoryStore.add(accountType, name, this.selectedIconKey, this.selectedColorKey);
    this.refresh();
    this.resetAddForm();
    this.showAddSheet = false;
    Toast.success($r('app.string.category_add_success'));
  }

  confirmDelete(item: AccountTypeModel): void {
    AlertDialog.show({
      title: $r('app.string.category_delete_confirm_title'),
      message: $r('app.string.category_delete_confirm_msg'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: $r('app.color.red'),
        action: () => {
          this.deleteCategory(item);
        }
      }
    });
  }

  deleteCategory(item: AccountTypeModel): void {
    const removed = CategoryStore.remove(this.currentAccountType(), item.id);
    if (!removed) {
      Toast.error($r('app.string.category_delete_last'));
      return;
    }
    this.refresh();
    Toast.success($r('app.string.category_delete_success'));
  }

  confirmRestore(): void {
    AlertDialog.show({
      title: $r('app.string.category_restore_confirm_title'),
      message: $r('app.string.category_restore_confirm_msg'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.confirm'),
        fontColor: $r('app.color.red'),
        action: () => {
          CategoryStore.restoreDefaults(this.currentAccountType());
          this.refresh();
          this.resetAddForm();
          Toast.success($r('app.string.category_restore_success'));
        }
      }
    });
  }

  @Builder SideTab(name: ResourceStr, index: number) {
    Column() {
      Text(name)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.currentIndex === index ? $r('app.color.font_1') : $r('app.color.font_2'))
    }
    .layoutWeight(1)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(SPACE_MEDIUM)
    .backgroundColor(this.currentIndex === index ? $r('app.color.green_alpha') : Color.Transparent)
    .onClick(() => {
      this.switchSide(index);
    })
  }

  @Builder CategoryRow(item: AccountTypeModel) {
    Row({ space: SPACE_MEDIUM }) {
      Column() {
        Image(item.icon)
          .width(20)
          .height(20)
          .fillColor(item.activeColor)
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.green_alpha'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text(item.name)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.font_3'))
        .layoutWeight(1)

      Text(CategoryStore.isCustom(item.id) ? $r('app.string.category_custom_tag') : $r('app.string.category_default_tag'))
        .fontSize(11)
        .fontColor($r('app.color.font_2'))
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .backgroundColor($r('app.color.grey_1'))
        .borderRadius(SPACE_SMALL)

      Text($r('app.string.delete'))
        .fontSize(13)
        .fontColor($r('app.color.red'))
        .padding({ left: SPACE_MEDIUM, right: SPACE_SMALL, top: SPACE_SMALL, bottom: SPACE_SMALL })
        .onClick(() => {
          this.confirmDelete(item);
        })
    }
    .width('100%')
    .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_MEDIUM, bottom: SPACE_MEDIUM })
    .backgroundColor($r('app.color.white'))
    .borderRadius(RADIUS_CARD)
  }

  @Builder IconOptionItem(option: CategoryIconOption) {
    Column() {
      Image(option.icon)
        .width(22)
        .height(22)
        .fillColor(this.selectedIconKey === option.key ? $r('app.color.green') : $r('app.color.font_2'))
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.selectedIconKey === option.key ? $r('app.color.green_alpha') : $r('app.color.grey_1'))
    .border({
      width: this.selectedIconKey === option.key ? 2 : 0,
      color: $r('app.color.green')
    })
    .margin(SPACE_TINY)
    .onClick(() => {
      this.selectedIconKey = option.key;
    })
  }

  @Builder ColorOptionItem(option: CategoryColorOption) {
    Column()
      .width(30)
      .height(30)
      .borderRadius(15)
      .backgroundColor(option.color)
      .border({
        width: this.selectedColorKey === option.key ? 3 : 0,
        color: $r('app.color.font_1')
      })
      .margin(SPACE_TINY)
      .onClick(() => {
        this.selectedColorKey = option.key;
      })
  }

  @Builder AddSheetBuilder() {
    Column({ space: SPACE_LARGE }) {
      Text($r('app.string.category_add'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.font_1'))

      Column({ space: SPACE_SMALL }) {
        Text($r('app.string.category_add_name_label'))
          .fontSize(14)
          .fontColor($r('app.color.font_2'))
        TextInput({ text: this.newCategoryName, placeholder: $r('app.string.category_add_name_placeholder') })
          .height(44)
          .fontSize(15)
          .backgroundColor($r('app.color.grey_1'))
          .borderRadius(SPACE_MEDIUM)
          .onChange((value: string) => {
            this.newCategoryName = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: SPACE_SMALL }) {
        Text($r('app.string.category_add_icon_label'))
          .fontSize(14)
          .fontColor($r('app.color.font_2'))
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(CATEGORY_ICON_OPTIONS, (option: CategoryIconOption) => {
            this.IconOptionItem(option)
          }, (option: CategoryIconOption) => option.key)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: SPACE_SMALL }) {
        Text($r('app.string.category_add_color_label'))
          .fontSize(14)
          .fontColor($r('app.color.font_2'))
        Row({ space: SPACE_MEDIUM }) {
          ForEach(CATEGORY_COLOR_OPTIONS, (option: CategoryColorOption) => {
            this.ColorOptionItem(option)
          }, (option: CategoryColorOption) => option.key)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Button($r('app.string.category_add'))
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor($r('app.color.white'))
        .backgroundColor($r('app.color.green'))
        .type(ButtonType.Normal)
        .borderRadius(SPACE_MEDIUM)
        .onClick(() => {
          this.confirmAdd();
        })
    }
    .width('100%')
    .padding({ left: SPACE_XLARGE, right: SPACE_XLARGE, top: SPACE_LARGE, bottom: SPACE_XLARGE })
  }

  build() {
    Column() {
      AccountNavigator({ title: $r('app.string.category_manage') })

      Column() {
        Row() {
          this.SideTab($r('app.string.expenditure'), 0)
          this.SideTab($r('app.string.income'), 1)
        }
        .width('100%')
        .height(44)
        .padding(SPACE_TINY)
        .backgroundColor($r('app.color.white'))
        .borderRadius(RADIUS_CARD)
        .margin({ top: SPACE_MEDIUM, bottom: SPACE_MEDIUM })

        Scroll() {
          Column({ space: SPACE_SMALL }) {
            ForEach(this.currentList(), (item: AccountTypeModel) => {
              this.CategoryRow(item)
            }, (item: AccountTypeModel) => item.id.toString())
          }
          .width('100%')
          .padding({ top: SPACE_TINY, bottom: SPACE_SMALL })
        }
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .layoutWeight(1)

        Row({ space: SPACE_MEDIUM }) {
          Button($r('app.string.category_add'))
            .layoutWeight(1)
            .height(44)
            .fontSize(15)
            .fontColor($r('app.color.white'))
            .backgroundColor($r('app.color.green'))
            .type(ButtonType.Normal)
            .borderRadius(SPACE_MEDIUM)
            .onClick(() => {
              this.resetAddForm();
              this.showAddSheet = true;
            })
          Button($r('app.string.category_restore'))
            .layoutWeight(1)
            .height(44)
            .fontSize(15)
            .fontColor($r('app.color.font_3'))
            .backgroundColor($r('app.color.white'))
            .type(ButtonType.Normal)
            .borderRadius(SPACE_MEDIUM)
            .border({ width: 1, color: $r('app.color.grey_2') })
            .onClick(() => {
              this.confirmRestore();
            })
        }
        .width('100%')
        .padding({ top: SPACE_SMALL, bottom: SPACE_LARGE })
      }
      .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .bindSheet($$this.showAddSheet, this.AddSheetBuilder(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      onDisappear: () => {
        this.showAddSheet = false;
      }
    })
  }
}
