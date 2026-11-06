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
  // 不含主键：更新时主键不可变，插入时单独补充 id
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
    po.id = result.getString(result.getColumnIndex('id'));
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

  async insert(record: AccountPO): Promise<void> {
    const bucket = this.buildValueBucket(record);
    // 主键为 UUID 文本，插入时显式写入，不再依赖自增
    bucket.id = record.id;
    await DBUtil.insert(ACCOUNT_TABLE_NAME, bucket);
  }

  async deleteById(id: string): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(ACCOUNT_TABLE_NAME);
    predicates.equalTo(ID_COLUMN, id);
    return DBUtil.delete(predicates);
  }

  /** 清空全部本地账单（隐私页“清空全部账单数据”用，墓碑由调用方统一记录） */
  async deleteAll(): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(ACCOUNT_TABLE_NAME);
    return DBUtil.delete(predicates);
  }

  private async queryAccount(predicates: relationalStore.RdbPredicates): Promise<AccountPO[]> {
    const result = await DBUtil.query(predicates, QUERY_COLUMNS);
    const list: AccountPO[] = [];
    try {
      while (result.goToNextRow()) {
        list.push(this.parseAccount(result));
      }
    } finally {
      // 读取抛错时 ResultSet 也不能泄漏
      result.close();
    }
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

  async update(id: string, record: AccountPO): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(ACCOUNT_TABLE_NAME);
    predicates.equalTo(ID_COLUMN, id);
    return DBUtil.update(predicates, this.buildValueBucket(record));
  }

  /** 查询全部本地账单，供端云全量同步做合并比较 */
  async queryAll(): Promise<AccountPO[]> {
    const predicates = new relationalStore.RdbPredicates(ACCOUNT_TABLE_NAME);
    return this.queryAccount(predicates);
  }

  /** 按主键插入或整体替换，供端云同步恢复云端账单时写入本地库 */
  async upsert(record: AccountPO): Promise<void> {
    await DBUtil.executeSql(
      `INSERT OR REPLACE INTO ${ACCOUNT_TABLE_NAME}` +
      ' (id, type, account_type, amount, create_time, description, time, merchant, source, pay_time)' +
      ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        record.id, record.type, record.accountType, record.amount, record.createTime,
        record.description, record.time, record.merchant, record.source, record.payTime
      ]
    );
  }
}
