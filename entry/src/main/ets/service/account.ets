import dayjs from 'dayjs';
import util from '@ohos.util';
import { AccountRepository } from '../data/AccountRepository';
import { RdbAccountRepository } from '../data/RdbAccountRepository';
import { AccountInfo } from '../models/account/account';
import AccountPO from '../models/account/accountPO';
import BillStore from '../common/BillStore';
import { SOURCE_MANUAL } from '../common/constants';
import AuthService from './AuthService';
import CloudAccountRepository from '../data/CloudAccountRepository';

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

  // 本地写成功后异步同步云端；未登录或同步失败静默忽略，不影响本地
  private async syncUpsert(po: AccountPO): Promise<void> {
    const uid = await AuthService.getCurrentUid();
    if (uid) {
      await CloudAccountRepository.upsert(po, uid);
    }
  }

  private async syncDelete(id: string): Promise<void> {
    await CloudAccountRepository.deleteById(id);
  }

  /**
   * 插入一条记录：主键由 UUID 生成
   */
  async insert(info: AccountInfo): Promise<void> {
    const po: AccountPO = new AccountPO();
    po.id = util.generateRandomUUID();
    po.type = info.type;
    po.accountType = info.accountType;
    po.amount = info.amount;
    po.time = info.time;
    po.description = info.description ?? '';
    po.merchant = info.merchant ?? '';
    po.source = info.source ?? SOURCE_MANUAL;
    po.payTime = info.payTime ?? this.buildDefaultPayTime(info.time);
    po.createTime = Date.now();
    await this.repository.insert(po);
    BillStore.notifyChanged();
    this.syncUpsert(po);
  }

  /**
   * 更新一条记录：payTime 为 0（旧数据）时按所选日期加当前时分补齐
   */
  async update(id: string, info: AccountInfo): Promise<number> {
    const po: AccountPO = new AccountPO();
    po.id = id;
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
    this.syncUpsert(po);
    return rows;
  }

  /**
   * 根据id删除一条记录
   */
  async deleteById(id: string): Promise<number> {
    const rows = await this.repository.deleteById(id);
    BillStore.notifyChanged();
    this.syncDelete(id);
    return rows;
  }

  /**
   * 批量删除记录：循环删除后只通知一次，避免多次刷新
   */
  async deleteByIds(ids: string[]): Promise<number> {
    let rows = 0;
    for (const id of ids) {
      rows += await this.repository.deleteById(id);
      this.syncDelete(id);
    }
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

  /**
   * 查询指定日期范围内的全部账单，供去重比较使用
   */
  queryByDateRange(startTime: number, endTime: number): Promise<AccountPO[]> {
    return this.repository.queryByDateRange(startTime, endTime);
  }
}

export default new AccountService(new RdbAccountRepository());
