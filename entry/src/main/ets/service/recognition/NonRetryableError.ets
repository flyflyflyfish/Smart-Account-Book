/**
 * 不可重试错误：请求被服务端明确拒绝（如 Key 无效、模型不支持图片输入），
 * 重试必然得到相同结果。RetryRecognizer 识别到此类型后直接上抛，不再退避重试。
 */
export class NonRetryableError extends Error {
}
