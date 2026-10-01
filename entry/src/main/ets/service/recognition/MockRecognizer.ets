import { AccountType } from '../../models/account/account';
import { RecognitionResult } from '../../models/recognition/RecognitionResult';
import { Recognizer } from './Recognizer';

// 模拟云端识别耗时
const MOCK_DELAY_MS: number = 1000;

/**
 * 模拟识别器：返回固定多笔假数据，用于在接入云端前走通完整流程
 */
export class MockRecognizer implements Recognizer {
  recognize(imageUri: string): Promise<RecognitionResult[]> {
    return new Promise<RecognitionResult[]>((resolve: (value: RecognitionResult[]) => void) => {
      setTimeout(() => {
        resolve(MockRecognizer.buildResults());
      }, MOCK_DELAY_MS);
    });
  }

  private static buildResults(): RecognitionResult[] {
    const now = Date.now();
    const first: RecognitionResult = {
      accountType: AccountType.EXPENSES,
      amount: 35.5,
      merchant: '星巴克咖啡',
      payTime: now,
      categoryName: '早午晚餐',
      confidence: 0.92,
      isBill: true
    };
    const second: RecognitionResult = {
      accountType: AccountType.EXPENSES,
      amount: 12,
      merchant: '地铁',
      payTime: now - 3600000,
      categoryName: '交通运输',
      confidence: 0.9,
      isBill: true
    };
    return [first, second];
  }
}
