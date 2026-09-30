import dayjs from 'dayjs';
import { AccountRepository } from '../data/AccountRepository';
import { RdbAccountRepository } from '../data/RdbAccountRepository';
import { AccountInfo } from '../models/account/account';
import AccountPO from '../models/account/accountPO';
import BillStore from '../common/BillStore';
import { SOURCE_MANUAL } from '../common/constants';

class AccountService {
  // 依赖仓储接口而非具体实现，便于测试时替换为内存实现
  private repository: AccountRepository;

  constructor(repository: AccountRepository) {
    this.repository = repository;
  }

  // 支付时间默认取所选日期叠加当前时分，保证同一天内的账单有先后顺序
  private buildDefaultPayTime(dateTime: number): number {
    const now = dayjs();
    return dayjs(dateTime)
      .hour(now.hour())
      .minute(now.minute())
      .second(0)
      .millisecond(0)
      .valueOf();
  }

  /**
   * 插入一条记录
   */
  async insert(info: AccountInfo): Promise<number> {
    const po: AccountPO = new AccountPO();
    po.type = info.type;
    po.accountType = info.accountType;
    po.amount = info.amount;
    po.time = info.time;
    po.description = info.description ?? '';
    po.merchant = info.merchant ?? '';
    po.source = info.source ?? SOURCE_MANUAL;
    po.payTime = info.payTime ?? this.buildDefaultPayTime(info.time);
    po.createTime = Date.now();
    const id = await this.repository.insert(po);
    BillStore.notifyChanged();
    return id;
  }

  /**
   * 更新一条记录：payTime 为 0（旧数据）时按所选日期加当前时分补齐
   */
  async update(id: number, info: AccountInfo): Promise<number> {
    const po: AccountPO = new AccountPO();
    po.type = info.type;
    po.accountType = info.accountType;
    po.amount = info.amount;
    po.time = info.time;
    po.description = info.description ?? '';
    po.merchant = info.merchant ?? '';
    po.source = info.source ?? SOURCE_MANUAL;
    po.payTime = info.payTime ? info.payTime : this.buildDefaultPayTime(info.time);
    po.createTime = info.createTime ?? Date.now();
    const rows = await this.repository.update(id, po);
    BillStore.notifyChanged();
    return rows;
  }

  /**
   * 根据id删除一条记录
   */
  async deleteById(id: number): Promise<number> {
    const rows = await this.repository.deleteById(id);
    BillStore.notifyChanged();
    return rows;
  }

  /**
   * 按月份获取记账记录
   */
  getAccountByMonth(time: string | number): Promise<AccountPO[]> {
    const startMonth = dayjs(time).startOf('month').toDate().getTime();
    const endMonth = dayjs(time).endOf('month').toDate().getTime();
    return this.repository.queryByDateRange(startMonth, endMonth);
  }

  /**
   * 按年份获取账单记录
   */
  getAccountByYear(time: string | number): Promise<AccountPO[]> {
    const startMonth = dayjs(time).startOf('year').toDate().getTime();
    const endMonth = dayjs(time).endOf('year').toDate().getTime();
    return this.repository.queryByDateRange(startMonth, endMonth);
  }

  /**
   * 查询指定日期范围内收入/支出的账单数据
   */
  getRangeAccountByType(startTime: number, endTime: number, type: number): Promise<AccountPO[]> {
    return this.repository.queryRangeAndType(startTime, endTime, type);
  }
}

export default new AccountService(new RdbAccountRepository());
