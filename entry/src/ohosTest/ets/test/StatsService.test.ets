import { describe, it, expect } from '@ohos/hypium';
import StatsService from '../../../main/ets/service/stats';
import AccountPO from '../../../main/ets/models/account/accountPO';
import { AccountType, AccountExpensesType, AccountIncomeType } from '../../../main/ets/models/account/account';

function buildPo(type: number, accountType: number, amount: number, time: number): AccountPO {
  const po = new AccountPO();
  po.id = time.toString();
  po.type = type;
  po.accountType = accountType;
  po.amount = amount;
  po.time = time;
  po.description = '';
  po.merchant = '';
  po.payTime = time;
  po.createTime = time;
  return po;
}

export default function statsServiceTest() {
  describe('StatsServiceTest', () => {
    it('stats_consume_total', 0, () => {
      const records: AccountPO[] = [
        buildPo(AccountExpensesType.MEALS, AccountType.EXPENSES, 100, 1000),
        buildPo(AccountExpensesType.TRANSPORT, AccountType.EXPENSES, 50, 2000),
        buildPo(AccountIncomeType.SALARY, AccountType.INCOME, 200, 3000)
      ];
      const total = StatsService.statsConsume(records);
      expect(total.expenses).assertEqual(150);
      expect(total.income).assertEqual(200);
    });

    it('stats_consumeByType', 0, () => {
      const records: AccountPO[] = [
        buildPo(AccountExpensesType.MEALS, AccountType.EXPENSES, 100, 1000),
        buildPo(AccountExpensesType.MEALS, AccountType.EXPENSES, 50, 2000),
        buildPo(AccountExpensesType.TRANSPORT, AccountType.EXPENSES, 30, 3000)
      ];
      const result = StatsService.statsConsumeByType(records);
      let mealsAmount = 0;
      let mealsCount = 0;
      for (const s of result.data.expenses) {
        if (s.info.id === AccountExpensesType.MEALS) {
          mealsAmount = s.amount;
          mealsCount = s.count;
        }
      }
      expect(mealsAmount).assertEqual(150);
      expect(mealsCount).assertEqual(2);
    });

    it('stats_groupByDate', 0, () => {
      const records: AccountPO[] = [
        buildPo(AccountExpensesType.MEALS, AccountType.EXPENSES, 100, 1000),
        buildPo(AccountExpensesType.TRANSPORT, AccountType.EXPENSES, 50, 1000)
      ];
      const groups = StatsService.groupByDate(records);
      expect(groups.length).assertEqual(1);
      expect(groups[0].expenses).assertEqual(150);
    });
  });
}
