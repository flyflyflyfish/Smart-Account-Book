import dayjs from 'dayjs';
import util from '@ohos.util';
import { BusinessError } from '@kit.BasicServicesKit';
import { AccountRepository } from '../data/AccountRepository';
import { RdbAccountRepository } from '../data/RdbAccountRepository';
import { AccountInfo } from '../models/account/account';
import AccountPO from '../models/account/accountPO';
import BillStore from '../common/BillStore';
import { SOURCE_MANUAL } from '../common/constants';
import { Logger } from '../utils/Logger';
import AuthService from './AuthService';
import CloudAccountRepository from '../data/CloudAccountRepository';
import CloudSettingSync from './CloudSettingSync';

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

  // 本地删除成功后异步同步云端：批量删行 + 一次性记墓碑。
  // 必须走批量接口单次读改写本地墓碑偏好——逐笔 fire-and-forget 并发执行时
  // 各自 load→push→save 互相覆盖，会丢墓碑导致已删账单在其他设备复活
  private syncDeleteMany(ids: string[]): void {
    CloudAccountRepository.deleteAll(ids).catch((error: BusinessError): void => {
      Logger.error('云同步删除账单失败', error.message);
    });
    CloudSettingSync.recordBillDeletions(ids).catch((error: BusinessError): void => {
      Logger.error('云同步删除标记失败', error.message);
    });
  }

  /**
   * 插入一条记录：主键由 UUID 生成，返回新账单 id（供账本记录关联主账单）
   */
  async insert(info: AccountInfo): Promise<string> {
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
    this.syncUpsert(po).catch((error: BusinessError): void => {
      // 云同步失败不影响本地结果，只记日志
      Logger.error('云同步账单失败', error.message);
    });
    return po.id;
  }

  /**
   * 静默插入一条记录：不触发 BillStore 通知。
   * 供周期补记等批量场景使用——一次补记可能插入上百笔，
   * 逐笔广播会引发 UI/卡片刷新风暴；调用方在整批完成后统一 notifyChanged。
   */
  async insertSilently(info: AccountInfo): Promise<void> {
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
    this.syncUpsert(po).catch((error: BusinessError): void => {
      Logger.error('云同步账单失败', error.message);
    });
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
    // 编辑即刷新版本时间戳：同步按 create_time 新者胜合并，编辑过的账单才会被
    // 其他设备拉取落地（保留旧值时两端相等互不覆盖，修改永远不同步）；UI 不依赖创建时间
    po.createTime = Date.now();
    const rows = await this.repository.update(id, po);
    BillStore.notifyChanged();
    this.syncUpsert(po).catch((error: BusinessError): void => {
      Logger.error('云同步账单失败', error.message);
    });
    return rows;
  }

  /**
   * 根据id删除一条记录
   */
  async deleteById(id: string): Promise<number> {
    const rows = await this.repository.deleteById(id);
    BillStore.notifyChanged();
    this.syncDeleteMany([id]);
    return rows;
  }

  /**
   * 批量删除记录：循环删除后只通知一次，避免多次刷新
   */
  async deleteByIds(ids: string[]): Promise<number> {
    let rows = 0;
    for (const id of ids) {
      rows += await this.repository.deleteById(id);
    }
    BillStore.notifyChanged();
    this.syncDeleteMany(ids);
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
