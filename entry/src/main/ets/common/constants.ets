export const H_STORE = 'account_store';
export const PREF_USER_FIRST_KEY = 'userFirstUsed';

// 账单来源：手动录入 / 图片识别
export const SOURCE_MANUAL: number = 0;
export const SOURCE_IMAGE: number = 1;

// 云端识别配置与识别引擎开关的 Preferences 键
export const PREF_CLOUD_BASE_URL = 'cloud_base_url';
export const PREF_CLOUD_API_KEY = 'cloud_api_key';
export const PREF_CLOUD_MODEL = 'cloud_model';
export const PREF_OCR_ENABLED = 'ocr_enabled';
export const PREF_CLOUD_ENABLED = 'cloud_enabled';
// 用户是否同意将图片上传至云端识别服务
export const PREF_CLOUD_CONSENT = 'cloud_consent';

// 自定义分类配置（JSON：新增的自定义分类 + 被隐藏的默认分类 id）的 Preferences 键
export const PREF_CATEGORY_CONFIG = 'category_config';

// 月度消费额度：开关 / 金额 / 当月已提醒标记（YYYY-MM）的 Preferences 键
export const PREF_BUDGET_ENABLED = 'budget_enabled';
export const PREF_BUDGET_LIMIT = 'budget_limit';
export const PREF_BUDGET_ALERT_MONTH = 'budget_alert_month';

// 超支系统通知的 requestId
export const BUDGET_NOTIFICATION_ID: number = 1001;

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

// 云数据库存储区名称与 schema 文件名，需与 AGC 控制台配置保持一致
export const CLOUD_ZONE_NAME: string = 'AccountZone';
export const CLOUD_SCHEMA_FILE: string = 'schema.json';
