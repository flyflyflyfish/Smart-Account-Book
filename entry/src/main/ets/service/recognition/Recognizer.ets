import { RecognitionResult } from '../../models/recognition/RecognitionResult';

/**
 * 账单图片识别器接口：mock 与云端实现统一抽象，上层只依赖接口
 * 一张图片可能包含多笔账单，统一返回识别结果数组
 */
export interface Recognizer {
  recognize(imageUri: string): Promise<RecognitionResult[]>;
}
