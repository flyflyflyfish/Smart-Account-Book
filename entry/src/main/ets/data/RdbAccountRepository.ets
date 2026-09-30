import relationalStore from '@ohos.data.relationalStore';
import AccountPO from '../models/account/accountPO';
import DBUtil from '../utils/DBUtil';
import { AccountRepository } from './AccountRepository';
import { ACCOUNT_TABLE_NAME } from './schema';

const ID_COLUMN: string = 'id';
const DATE_COLUMN: string = 'time';
const TYPE_COLUMN: string = 'account_type';
const QUERY_COLUMNS: string[] = [
  'id',
  'type',
  'account_type',
  'amount',
  'create_time',
  'description',
  'time',
  'merchant',
  'source',
  'pay_time'
];

/**
 * 基于关系型数据库的账单仓储实现
 */
export class RdbAccountRepository implements AccountRepository {
  private buildValueBucket(record: AccountPO): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'type': record.type,
      'account_type': record.accountType,
      'amount': record.amount,
      'create_time': record.createTime,
      'description': record.description,
      'time': record.time,
      'merchant': record.merchant,
      'source': record.source,
      'pay_time': record.payTime
    };
    return bucket;
  }

  private parseAccount(result: relationalStore.ResultSet): AccountPO {
    const po = new AccountPO();
    po.id = result.getLong(result.getColumnIndex('id'));
    po.type = result.getLong(result.getColumnIndex('type'));
    po.accountType = result.getLong(result.getColumnIndex('account_type'));
    po.amount = result.getDouble(result.getColumnIndex('amount'));
    po.createTime = result.getLong(result.getColumnIndex('create_time'));
    po.description = result.getString(result.getColumnIndex('description'));
    po.time = result.getLong(result.getColumnIndex('time'));
    po.merchant = result.getString(result.getColumnIndex('merchant'));
    po.source = result.getLong(result.getColumnIndex('source'));
    po.payTime = result.getLong(result.getColumnIndex('pay_time'));
    return po;
  }

  async insert(record: AccountPO): Promise<number> {
    return DBUtil.insert(ACCOUNT_TABLE_NAME, this.buildValueBucket(record));
  }

  async deleteById(id: number): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(ACCOUNT_TABLE_NAME);
    predicates.equalTo(ID_COLUMN, id);
    return DBUtil.delete(predicates);
  }

  private async queryAccount(predicates: relationalStore.RdbPredicates): Promise<AccountPO[]> {
    const result = await DBUtil.query(predicates, QUERY_COLUMNS);
    const list: AccountPO[] = [];
    while (result.goToNextRow()) {
      list.push(this.parseAccount(result));
    }
    result.close();
    return list;
  }

  async queryByDateRange(startDate: number, endDate: number): Promise<AccountPO[]> {
    const predicates = new relationalStore.RdbPredicates(ACCOUNT_TABLE_NAME);
    predicates
      .greaterThanOrEqualTo(DATE_COLUMN, startDate)
      .and()
      .lessThanOrEqualTo(DATE_COLUMN, endDate);
    return this.queryAccount(predicates);
  }

  async queryRangeAndType(startDate: number, endDate: number, type: number): Promise<AccountPO[]> {
    const predicates = new relationalStore.RdbPredicates(ACCOUNT_TABLE_NAME);
    predicates
      .greaterThanOrEqualTo(DATE_COLUMN, startDate)
      .and()
      .lessThanOrEqualTo(DATE_COLUMN, endDate)
      .and()
      .equalTo(TYPE_COLUMN, type);
    return this.queryAccount(predicates);
  }

  async update(id: number, record: AccountPO): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(ACCOUNT_TABLE_NAME);
    predicates.equalTo(ID_COLUMN, id);
    return DBUtil.update(predicates, this.buildValueBucket(record));
  }
}
