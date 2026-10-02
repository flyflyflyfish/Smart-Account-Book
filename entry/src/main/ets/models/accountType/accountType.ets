import { AccountExpensesType, AccountIncomeType } from '../account/account';
import AccountTypeModel from './AccountTypeModel';

export const expenses: AccountTypeModel[] = [
  new AccountTypeModel(AccountExpensesType.MEALS, $r('app.string.diet'), $r('app.media.meals'), 'yellow'),
  new AccountTypeModel(AccountExpensesType.MEDICAL, $r('app.string.healthy'), $r('app.media.medical'), 'green'),
  new AccountTypeModel(AccountExpensesType.TRANSPORT, $r('app.string.transport'), $r('app.media.traffic'), 'blue'),
  new AccountTypeModel(AccountExpensesType.HOUSE, $r('app.string.house'), $r('app.media.house'), 'blue'),
  new AccountTypeModel(AccountExpensesType.TOBACCO, $r('app.string.snack'), $r('app.media.tobacco'), 'yellow'),
  new AccountTypeModel(AccountExpensesType.STUDY, $r('app.string.study'), $r('app.media.educate'), 'blue'),
  new AccountTypeModel(AccountExpensesType.COMMUNICATE, $r('app.string.communicate'), $r('app.media.communication'), 'blue'),
  new AccountTypeModel(AccountExpensesType.SOCIAL, $r('app.string.social'), $r('app.media.social'), 'purple'),
  new AccountTypeModel(AccountExpensesType.INVEST, $r('app.string.investment_expenditure'), $r('app.media.invest'), 'green'),
  new AccountTypeModel(AccountExpensesType.SHOPPING, $r('app.string.shopping'), $r('app.media.shoping'), 'purple'),
  new AccountTypeModel(AccountExpensesType.ENTERTAINMENT, $r('app.string.entertainment'), $r('app.media.game'), 'red'),
  new AccountTypeModel(AccountExpensesType.LOAN, $r('app.string.loan'), $r('app.media.loan'), 'green'),
  new AccountTypeModel(AccountExpensesType.OTHER, $r('app.string.other_expenses'), $r('app.media.other'), 'green'),
];

export const incomes: AccountTypeModel[] = [
  new AccountTypeModel(AccountIncomeType.SALARY, $r('app.string.salary'), $r('app.media.salary'), 'green'),
  new AccountTypeModel(AccountIncomeType.BONUS, $r('app.string.bonus'), $r('app.media.bonus'), 'orange'),
  new AccountTypeModel(AccountIncomeType.INTEREST, $r('app.string.interest'), $r('app.media.Interest'), 'yellow'),
  new AccountTypeModel(AccountIncomeType.INVEST, $r('app.string.invest'), $r('app.media.invest'), 'red'),
  new AccountTypeModel(AccountIncomeType.PART_TIME, $r('app.string.part_time'), $r('app.media.part_time'), 'blue'),
  new AccountTypeModel(AccountIncomeType.RED_ENVELOP, $r('app.string.red_envelope'), $r('app.media.red_envalope'), 'red'),
  new AccountTypeModel(AccountIncomeType.BORROW, $r('app.string.borrow'), $r('app.media.borrow'), 'purple'),
  new AccountTypeModel(AccountIncomeType.OTHER, $r('app.string.other_income'), $r('app.media.other'), 'green'),
]