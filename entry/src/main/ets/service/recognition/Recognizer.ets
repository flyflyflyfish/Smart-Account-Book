import { RecognitionResult } from '../../models/recognition/RecognitionResult';

/**
 * 账单图片识别器接口：mock 与云端实现统一抽象，上层只依赖接口
 */
export interface Recognizer {
  recognize(imageUri: string): Promise<RecognitionResult>;
}
