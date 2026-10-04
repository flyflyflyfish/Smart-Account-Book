import dayjs from 'dayjs';
import { AccountType } from '../account/account';
import AccountTypeModel from '../accountType/AccountTypeModel';
import CategoryRegistry from '../accountType/CategoryRegistry';
import { RecognitionResult } from './RecognitionResult';

/**
 * 图片识别确认页的单笔草稿：翻页编辑时承载每笔的可变状态
 */
export class BillDraft {
  // 草稿唯一自增 id：一张图可产生多笔草稿，ForEach key 与删除后重排必须靠它区分
  private static seq: number = 0;
  readonly uid: number;
  amountText: string = '';
  merchant: string = '';
  accountType: AccountType = AccountType.EXPENSES;
  selectType: AccountTypeModel | undefined = undefined;
  selectedDate: number = 0;
  payTime: number = 0;
  // 已入库记录 id，0 表示尚未保存
  id: number = 0;
  // 是否已写入数据库：回退后“保存”走更新，“跳过”走撤销删除
  saved: boolean = false;
  // 分类是否由流水线智能分类自动给出，用户手改后清除
  autoClassified: boolean = false;
  // 是否与已有账单疑似重复，确认页高亮并默认不勾选
  duplicated: boolean = false;
  // 是否勾选待入账
  selected: boolean = true;
  // 来源图片地址，用于编辑面板展示与失败定位
  imageUri: string = '';

  constructor() {
    BillDraft.seq++;
    this.uid = BillDraft.seq;
  }

  // 金额 ≤0 时留空，交给用户在确认页补填；疑似重复默认不勾选
  static fromResult(result: RecognitionResult, imageUri: string): BillDraft {
    const draft = new BillDraft();
    draft.amountText = result.amount > 0 ? result.amount.toFixed(2) : '';
    draft.merchant = result.merchant;
    draft.accountType = result.accountType;
    draft.selectType = BillDraft.matchCategory(result.categoryName, result.accountType);
    draft.selectedDate = dayjs(result.payTime).startOf('day').valueOf();
    draft.payTime = result.payTime;
    draft.autoClassified = result.autoClassified === true;
    draft.duplicated = result.duplicated === true;
    draft.selected = !draft.duplicated;
    draft.imageUri = imageUri;
    return draft;
  }

  // 分类名映射到注册表，映射不到时回退该收支侧的“其他”
  static matchCategory(name: string, accountType: AccountType): AccountTypeModel | undefined {
    const matched = CategoryRegistry.getByName(name, accountType);
    if (matched) {
      return matched;
    }
    return CategoryRegistry.getOther(accountType);
  }
}
