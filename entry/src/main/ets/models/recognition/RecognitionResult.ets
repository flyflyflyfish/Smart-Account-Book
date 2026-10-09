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
  // 识别引擎标识：'local_model'（端侧模型）/ 'cloud'（云端大模型）/ 'ocr_rule'（纯 OCR 规则）
  engine?: string;
}

// 深拷贝单条识别结果：缓存与训练样本需要与后续流水线的就地修改隔离
export function copyRecognitionResult(source: RecognitionResult): RecognitionResult {
  return {
    accountType: source.accountType,
    amount: source.amount,
    merchant: source.merchant,
    payTime: source.payTime,
    categoryName: source.categoryName,
    confidence: source.confidence,
    isBill: source.isBill,
    autoClassified: source.autoClassified,
    duplicated: source.duplicated,
    engine: source.engine
  };
}
