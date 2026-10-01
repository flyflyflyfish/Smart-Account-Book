export const H_STORE = 'account_store';
export const PREF_USER_FIRST_KEY = 'userFirstUsed';

// 账单来源：手动录入 / 图片识别
export const SOURCE_MANUAL: number = 0;
export const SOURCE_IMAGE: number = 1;

// 云端识别配置与识别器类型的 Preferences 键
export const PREF_CLOUD_BASE_URL = 'cloud_base_url';
export const PREF_CLOUD_API_KEY = 'cloud_api_key';
export const PREF_CLOUD_MODEL = 'cloud_model';
export const PREF_RECOGNIZER_TYPE = 'recognizer_type';
// 用户是否同意将图片上传至云端识别服务
export const PREF_CLOUD_CONSENT = 'cloud_consent';

// 分类名称（纯字符串，按 id 顺序），供识别/分类逻辑使用，避免依赖资源上下文
export const EXPENSE_CATEGORY_NAMES: string[] = [
  '早午晚餐', '医疗', '交通运输', '住房', '零食烟酒', '学习', '通讯', '社交', '投资支出', '购物', '娱乐', '外借', '其他支出'
];
export const INCOME_CATEGORY_NAMES: string[] = [
  '工资', '奖金', '利息', '投资', '兼职', '红包转账', '借入', '其他收入'
];

// 识别流水线警告文案（不依赖资源上下文，供测试与流水线内部使用）
export const WARN_AMOUNT_INVALID: string = '识别金额无效，请手动填写金额';
export const WARN_PAYTIME_INVALID: string = '支付时间未识别，已使用当前时间';
