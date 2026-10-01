import { describe, it, expect } from '@ohos/hypium';
import { CloudResultParser } from '../../../main/ets/service/recognition/CloudResultParser';
import { AccountType } from '../../../main/ets/models/account/account';

export default function cloudResultParserTest() {
  describe('CloudResultParserTest', () => {
    it('parseResult_normal', 0, () => {
      const parser = new CloudResultParser();
      const content = '[{"accountType":"支出","amount":35.5,"merchant":"星巴克","payTime":"2024-01-15 10:30","category":"早午晚餐"}]';
      const results = parser.parseResult(content);
      expect(results.length).assertEqual(1);
      expect(results[0].accountType).assertEqual(AccountType.EXPENSES);
      expect(results[0].amount).assertEqual(35.5);
      expect(results[0].merchant).assertEqual('星巴克');
      expect(results[0].categoryName).assertEqual('早午晚餐');
    });

    it('parseResult_codeBlock', 0, () => {
      const parser = new CloudResultParser();
      const content = '```json\n[{"accountType":"收入","amount":100,"merchant":"工资","payTime":"2024-01-01 09:00","category":"工资"}]\n```';
      const results = parser.parseResult(content);
      expect(results.length).assertEqual(1);
      expect(results[0].accountType).assertEqual(AccountType.INCOME);
      expect(results[0].amount).assertEqual(100);
    });

    it('parseResult_missingFields', 0, () => {
      const parser = new CloudResultParser();
      const content = '[{"accountType":"支出"}]';
      const results = parser.parseResult(content);
      expect(results.length).assertEqual(1);
      expect(results[0].amount).assertEqual(0);
      expect(results[0].merchant).assertEqual('');
      expect(results[0].categoryName).assertEqual('其他支出');
    });

    it('parseResult_invalid_throws', 0, () => {
      const parser = new CloudResultParser();
      let threw = false;
      try {
        parser.parseResult('not-a-json');
      } catch (error) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('normalizeCategory_unknown', 0, () => {
      const parser = new CloudResultParser();
      expect(parser.normalizeCategory('早午晚餐', AccountType.EXPENSES)).assertEqual('早午晚餐');
      expect(parser.normalizeCategory('不存在的分类', AccountType.EXPENSES)).assertEqual('其他支出');
      expect(parser.normalizeCategory('不存在的分类', AccountType.INCOME)).assertEqual('其他收入');
    });

    it('parsePayTime_invalid_fallback', 0, () => {
      const parser = new CloudResultParser();
      const valid = parser.parsePayTime('2024-01-15 10:30');
      expect(valid).assertLarger(0);
      const before = Date.now();
      const invalid = parser.parsePayTime('not-a-date');
      expect(invalid >= before).assertTrue();
    });
  });
}
