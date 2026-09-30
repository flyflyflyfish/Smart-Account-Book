/**
 * 应用级配置：识别器类型等开关集中在此，避免散落硬编码
 */

// 账单图片识别器类型：本地模拟 / 云端多模态大模型
export enum RecognizerType {
  MOCK,
  CLOUD
}
