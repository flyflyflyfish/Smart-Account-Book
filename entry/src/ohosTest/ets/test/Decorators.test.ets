import { describe, it, expect } from '@ohos/hypium';
import { FallbackRecognizer } from '../../../main/ets/service/recognition/decorators/FallbackRecognizer';
import { RetryRecognizer } from '../../../main/ets/service/recognition/decorators/RetryRecognizer';
import { CachingRecognizer } from '../../../main/ets/service/recognition/decorators/CachingRecognizer';
import { Recognizer } from '../../../main/ets/service/recognition/Recognizer';
import { RecognitionResult } from '../../../main/ets/models/recognition/RecognitionResult';
import { AccountType } from '../../../main/ets/models/account/account';

class FakeRecognizer implements Recognizer {
  failTimes: number = 0;
  results: RecognitionResult[] = [];
  callCount: number = 0;

  async recognize(imageUri: string): Promise<RecognitionResult[]> {
    this.callCount++;
    if (this.failTimes > 0) {
      this.failTimes--;
      throw new Error('fake fail');
    }
    return this.results;
  }
}

function buildResult(confidence: number): RecognitionResult {
  const result: RecognitionResult = {
    accountType: AccountType.EXPENSES,
    amount: 10,
    merchant: '星巴克',
    payTime: Date.now(),
    categoryName: '早午晚餐',
    confidence: confidence,
    isBill: true
  };
  return result;
}

export default function decoratorsTest() {
  describe('DecoratorsTest', () => {
    it('fallback_primarySuccess', 0, async () => {
      const primary = new FakeRecognizer();
      primary.results = [buildResult(0.9)];
      const secondary = new FakeRecognizer();
      secondary.results = [buildResult(0.9)];
      const fallback = new FallbackRecognizer(primary, secondary, 0.6, true);
      const results = await fallback.recognize('uri');
      expect(results.length).assertEqual(1);
      expect(primary.callCount).assertEqual(1);
      expect(secondary.callCount).assertEqual(0);
    });

    it('fallback_primaryFail_useSecondary', 0, async () => {
      const primary = new FakeRecognizer();
      primary.failTimes = 1;
      const secondary = new FakeRecognizer();
      secondary.results = [buildResult(0.9)];
      const fallback = new FallbackRecognizer(primary, secondary, 0.6, true);
      const results = await fallback.recognize('uri');
      expect(results.length).assertEqual(1);
      expect(secondary.callCount).assertEqual(1);
    });

    it('fallback_lowConfidence_useSecondary', 0, async () => {
      const primary = new FakeRecognizer();
      primary.results = [buildResult(0.2)];
      const secondary = new FakeRecognizer();
      secondary.results = [buildResult(0.9)];
      const fallback = new FallbackRecognizer(primary, secondary, 0.6, true);
      const results = await fallback.recognize('uri');
      expect(results.length).assertEqual(1);
      expect(secondary.callCount).assertEqual(1);
    });

    it('fallback_lowConfidence_keepPrimary_whenFallbackDisabled', 0, async () => {
      // fallbackOnLowConfidence=false（secondary 弱于 primary 的场景）：低置信不再降级
      const primary = new FakeRecognizer();
      primary.results = [buildResult(0.2)];
      const secondary = new FakeRecognizer();
      secondary.results = [buildResult(0.9)];
      const fallback = new FallbackRecognizer(primary, secondary, 0.6, false);
      const results = await fallback.recognize('uri');
      expect(results.length).assertEqual(1);
      expect(secondary.callCount).assertEqual(0);
    });

    it('retry_successAfterRetry', 0, async () => {
      const inner = new FakeRecognizer();
      inner.failTimes = 1;
      inner.results = [buildResult(0.9)];
      const retry = new RetryRecognizer(inner, 3, 10);
      const results = await retry.recognize('uri');
      expect(results.length).assertEqual(1);
      expect(inner.callCount).assertEqual(2);
    });

    it('retry_exhausted_throws', 0, async () => {
      const inner = new FakeRecognizer();
      inner.failTimes = 3;
      const retry = new RetryRecognizer(inner, 2, 10);
      let threw = false;
      try {
        await retry.recognize('uri');
      } catch (error) {
        threw = true;
      }
      expect(threw).assertTrue();
      expect(inner.callCount).assertEqual(2);
    });

    it('caching_hit', 0, async () => {
      const inner = new FakeRecognizer();
      inner.results = [buildResult(0.9)];
      const caching = new CachingRecognizer(inner, 10, async (uri: string): Promise<string> => {
        return 'fixed-key';
      });
      const r1 = await caching.recognize('uri-a');
      const r2 = await caching.recognize('uri-b');
      expect(r1.length).assertEqual(1);
      expect(r2.length).assertEqual(1);
      expect(inner.callCount).assertEqual(1);
    });
  });
}
