export const H_STORE = 'account_store';
export const PREF_USER_FIRST_KEY = 'userFirstUsed';

// 账单来源：手动录入 / 图片识别 / 快捷记账（一键添加与到点自动记入）/ 账单文件导入
export const SOURCE_MANUAL: number = 0;
export const SOURCE_IMAGE: number = 1;
export const SOURCE_RECURRING: number = 2;
export const SOURCE_IMPORT: number = 3;

// 云端识别配置与识别引擎开关的 Preferences 键
// 旧版单配置三键（保留用于迁移历史数据）
export const PREF_CLOUD_BASE_URL = 'cloud_base_url';
export const PREF_CLOUD_API_KEY = 'cloud_api_key';
export const PREF_CLOUD_MODEL = 'cloud_model';
// 新版多服务商：JSON 数组 + 当前激活的服务商 id
export const PREF_CLOUD_PROVIDERS = 'cloud_providers';
export const PREF_CLOUD_ACTIVE_PROVIDER = 'cloud_active_provider';
export const PREF_OCR_ENABLED = 'ocr_enabled';
export const PREF_CLOUD_ENABLED = 'cloud_enabled';
// 用户是否同意将图片上传至云端识别服务
export const PREF_CLOUD_CONSENT = 'cloud_consent';
// 训练数据采集开关（默认关闭，仅存本机，不上传）
export const PREF_TRAIN_COLLECT_ENABLED = 'train_collect_enabled';

// 自定义分类配置（JSON：新增的自定义分类 + 被隐藏的默认分类 id）的 Preferences 键
export const PREF_CATEGORY_CONFIG = 'category_config';

// 账本默认同步主账单（true/false）：账本内记一笔与图片识别入账的默认开关
export const PREF_LEDGER_SYNC_BILLS = 'ledger_sync_bills';

// 月度消费额度：开关 / 金额 / 当月已提醒标记（YYYY-MM）的 Preferences 键
export const PREF_BUDGET_ENABLED = 'budget_enabled';
export const PREF_BUDGET_LIMIT = 'budget_limit';
export const PREF_BUDGET_ALERT_MONTH = 'budget_alert_month';

// 超支系统通知的 requestId
export const BUDGET_NOTIFICATION_ID: number = 1001;

// 重复性账单规则（JSON 数组）的 Preferences 键
export const PREF_RECURRING_BILLS = 'recurring_bills';

// 重复性账单记入成功的系统通知 requestId
export const RECURRING_NOTIFICATION_ID: number = 2001;

// 商家→分类学习记忆：云端 user_setting 行键（JSON 数组）+ 本机清除时间（防已清记忆被云端拉回）
export const PREF_MERCHANT_LEARNING = 'merchant_learning';
export const PREF_MERCHANT_LEARNING_CLEARED_AT = 'merchant_learning_cleared_at';

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

// 小组件：已添加卡片 formId 列表（逗号分隔）、单卡尺寸与单卡统计口径（今日/本月）的 Preferences 键
export const PREF_FORM_IDS = 'widget_form_ids';
export const FORM_DIM_PREFIX = 'form_dim_';
export const FORM_RANGE_PREFIX = 'form_range_';
export const WIDGET_RANGE_TODAY: string = 'today';
export const WIDGET_RANGE_MONTH: string = 'month';

// 显示与外观：主题 / 深浅色模式 / 字号缩放 / 光感（阴影浓度）/ 首页汇总口径的 Preferences 键
export const PREF_THEME_ID = 'theme_id';
export const PREF_COLOR_MODE = 'theme_color_mode';
export const PREF_FONT_SCALE = 'theme_font_scale';
export const PREF_GLOW_LEVEL = 'theme_glow_level';
export const PREF_HOME_STAT_SCOPE = 'home_stat_scope';
// 自定义主题主色（hex，如 #2E9E73），空串代表未设置
export const PREF_CUSTOM_THEME_PRIMARY = 'theme_custom_primary';

// 底部第二页签样式：AI 助手 / 账本（默认 AI 助手）的 Preferences 键
export const PREF_SECOND_TAB_STYLE = 'second_tab_style';
export const SECOND_TAB_STYLE_AI: string = 'ai';
export const SECOND_TAB_STYLE_LEDGER: string = 'ledger';

// 云数据库存储区名称与 schema 文件名，需与 AGC 控制台配置保持一致
export const CLOUD_ZONE_NAME: string = 'AccountZone';
export const CLOUD_SCHEMA_FILE: string = 'schema.json';

// 端云同步：各设置最近一次本地变更时间（JSON：{设置键: 毫秒时间戳}）的 Preferences 键，
// 拉取时用于判断云端值是否比本地新，避免旧值覆盖新值
export const PREF_CLOUD_SYNC_META = 'cloud_sync_meta';

// 端云同步：已删除账单的墓碑 id 列表（JSON 数组）的 Preferences 键，
// 防止某台设备删除后又被另一台设备同步时推回云端（复活）
export const PREF_CLOUD_TOMBSTONES = 'cloud_bill_tombstones';

// 本地墓碑记录上限，超过后淘汰最早记录
export const CLOUD_TOMBSTONE_MAX: number = 500;

// 账本/账本记录删除墓碑 id 前缀：与账单墓碑共用 bill_tombstone 表与本地墓碑列表，
// 同步时按前缀区分类型，账单同步循环不会误匹配带前缀的 id
export const LEDGER_TOMBSTONE_PREFIX: string = 'ledger:';
export const LEDGER_RECORD_TOMBSTONE_PREFIX: string = 'ledger_record:';

// 端云全量同步的最小间隔（毫秒）：回前台等高频触发时按此节流
export const CLOUD_SYNC_MIN_INTERVAL_MS: number = 10 * 60 * 1000;
