import AccountPO from '../models/account/accountPO';

/**
 * 账单数据仓储接口：隔离数据访问实现，便于测试时替换
 */
export interface AccountRepository {
  insert(record: AccountPO): Promise<number>;

  deleteById(id: number): Promise<number>;

  queryByDateRange(startDate: number, endDate: number): Promise<AccountPO[]>;

  queryRangeAndType(startDate: number, endDate: number, type: number): Promise<AccountPO[]>;

  update(id: number, record: AccountPO): Promise<number>;
}
