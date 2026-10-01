import { AccountType } from '../account/account';

/**
 * 图片识别结果：识别服务返回的结构化数据，经用户确认后才入账
 */
export interface RecognitionResult {
  // 收支类型：支出/收入
  accountType: AccountType;
  // 识别出的金额（元）
  amount: number;
  // 商家名称，识别不到时为空串
  merchant: string;
  // 支付时间戳（毫秒）
  payTime: number;
  // 识别出的分类名称，入账前经 CategoryRegistry 映射为分类 id
  categoryName: string;
  // 置信度 0~1，供界面提示识别可靠程度
  confidence: number;
  // 图片是否为有效账单，false 时不进入确认流程
  isBill: boolean;
  // 分类是否由流水线智能分类自动给出，供确认页展示标记
  autoClassified?: boolean;
  // 是否与已有账单疑似重复，供确认页高亮并默认不勾选
  duplicated?: boolean;
}
