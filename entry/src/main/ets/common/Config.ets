/**
 * 应用级配置：识别引擎开关等集中在此，避免散落硬编码
 */

// 去重：金额相同且支付时间差不超过该毫秒数视为疑似重复
export const DEDUP_TIME_WINDOW_MS: number = 5 * 60 * 1000;
// 去重：查询最近多少天的已有账单参与比较
export const DEDUP_QUERY_DAYS: number = 30;
// 图片记账：相册多选最大张数
export const MAX_PICK_IMAGES: number = 9;
// 批量识别：同时进行的请求上限
export const RECOGNIZE_CONCURRENCY: number = 2;
// 识别器组合：主识别器结果最小置信度低于该值时降级到备用识别器
// 0.8 由 40 图留出集扫描选定（0.6/0.7/0.75/0.8/0.85/0.9 中最优，混合 F1 0.946，
// 超过全云端基线 0.909；约半数低置信图整图回退云端）
export const RECOGNIZE_CONFIDENCE_THRESHOLD: number = 0.8;
// 识别器组合：失败重试次数（含首次共 maxAttempts 次尝试）
export const RECOGNIZE_RETRY_MAX_ATTEMPTS: number = 2;
// 识别器组合：重试间隔基数（毫秒），逐次翻倍
export const RECOGNIZE_RETRY_BASE_DELAY_MS: number = 500;
// 识别器组合：按图片内容哈希的结果缓存上限（条）
export const RECOGNIZE_CACHE_SIZE: number = 20;
