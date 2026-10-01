/**
 * 应用级配置：识别器类型等开关集中在此，避免散落硬编码
 */

// 账单图片识别器类型：本地模拟 / 云端多模态大模型
export enum RecognizerType {
  MOCK,
  CLOUD
}

// 去重：金额相同且支付时间差不超过该毫秒数视为疑似重复
export const DEDUP_TIME_WINDOW_MS: number = 5 * 60 * 1000;
// 去重：查询最近多少天的已有账单参与比较
export const DEDUP_QUERY_DAYS: number = 30;
// 图片记账：相册多选最大张数
export const MAX_PICK_IMAGES: number = 9;
// 批量识别：同时进行的请求上限
export const RECOGNIZE_CONCURRENCY: number = 2;
