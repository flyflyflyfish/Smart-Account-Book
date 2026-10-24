import MerchantCategory from '../models/recognition/MerchantCategory';
import MerchantCategoryRepository from '../data/MerchantCategoryRepository';
import CloudSettingSync from './CloudSettingSync';
import { SettingCloud } from '../models/cloud/SettingCloud';
import PreferenceUtil from '../utils/PreferenceUtil';
import { Logger } from '../utils/Logger';
import * as CONSTANTS from '../common/constants';

/**
 * 云端学习记忆行的原始 JSON 条目（解析中转，字段经校验后才进入本地模型）
 */
class MerchantLearningRaw {
  merchant: string = '';
  categoryId: number = 0;
  accountType: number = 0;
  updatedAt: number = 0;
}

/**
 * 学习记忆合并结果：mergedJson 为合并后的快照文本，needPush 表示与云端不一致需补推
 */
export class MerchantLearningSyncResult {
  mergedJson: string = '';
  needPush: boolean = false;
}

/**
 * 商家→分类学习记忆的端云同步：
 * - 云端形态：user_setting 的一行 JSON（key=merchant_learning），不新增对象类型
 * - 本地形态：rdb merchant_category 表
 * - 合并规则：按商家并集，单条 updatedAt 新者胜；本机清除后早于清除时间的云端条目不再恢复
 */
class MerchantLearningSyncService {
  private repository: MerchantCategoryRepository = new MerchantCategoryRepository();

  /** 学习成功后即时合并上传；未登录静默跳过（下次全量同步按内容差异补推） */
  async pushAfterLearn(): Promise<void> {
    if (!CloudSettingSync.isAttached()) {
      return;
    }
    const rows = await CloudSettingSync.querySettings();
    const cloudRow = rows.find((row: SettingCloud): boolean =>
      row.setting_key === CONSTANTS.PREF_MERCHANT_LEARNING);
    await this.syncAndPush(cloudRow ? cloudRow.setting_value : undefined);
  }

  /** 全量同步入口：云端值与本地表合并，必要时补推云端 */
  async syncAndPush(cloudValue: string | undefined): Promise<void> {
    const result = await this.sync(cloudValue);
    if (result.needPush) {
      await CloudSettingSync.upsertSettingRow(CONSTANTS.PREF_MERCHANT_LEARNING,
        result.mergedJson, Date.now());
    }
  }

  /**
   * 清除全部学习记忆时调用：记录本机清除时间并删除云端行，
   * 防止下次同步把已清除的记忆从云端拉回
   */
  async recordCleared(): Promise<void> {
    await PreferenceUtil.putPreferenceValue(
      CONSTANTS.PREF_MERCHANT_LEARNING_CLEARED_AT, Date.now());
    if (CloudSettingSync.isAttached()) {
      await CloudSettingSync.deleteSettingRow(
        `${CloudSettingSync.getUid()}:${CONSTANTS.PREF_MERCHANT_LEARNING}`);
    }
  }

  /**
   * 云端 JSON 与本地表按 updatedAt 并集合并：云端新条目写回本地，
   * 合并结果与云端不一致时 needPush=true
   */
  async sync(cloudValue: string | undefined): Promise<MerchantLearningSyncResult> {
    const result = new MerchantLearningSyncResult();
    const localEntries = await this.repository.queryAll();
    const cloudEntries = this.parseCloud(cloudValue);
    const clearedAt = Number(await PreferenceUtil.getPreferenceValue(
      CONSTANTS.PREF_MERCHANT_LEARNING_CLEARED_AT, 0));
    const localMap = new Map<string, MerchantCategory>();
    for (const item of localEntries) {
      localMap.set(item.merchant, item);
    }
    const merged = new Map<string, MerchantCategory>();
    // 云端 → 合并：早于本机清除时间的云端条目视为已清除，不再恢复
    for (const cloud of cloudEntries) {
      if (clearedAt > 0 && cloud.updatedAt < clearedAt) {
        continue;
      }
      merged.set(cloud.merchant, cloud);
    }
    // 本地 → 合并：单条 updatedAt 新者胜
    for (const local of localEntries) {
      const cloud = merged.get(local.merchant);
      if (!cloud || local.updatedAt >= cloud.updatedAt) {
        merged.set(local.merchant, local);
      }
    }
    // 云端新增或更新的条目写回本地表
    for (const entry of merged.values()) {
      const local = localMap.get(entry.merchant);
      if (!local || local.updatedAt < entry.updatedAt) {
        await this.repository.upsert(entry);
      }
    }
    const mergedJson = this.toSortedJson(merged);
    result.mergedJson = mergedJson;
    const bothEmpty = merged.size === 0 && (cloudValue === undefined || cloudValue.length === 0);
    result.needPush = !bothEmpty && mergedJson !== cloudValue;
    return result;
  }

  /** 解析云端 JSON 行；空值/格式非法按空处理，不中断同步 */
  private parseCloud(cloudValue: string | undefined): MerchantCategory[] {
    if (!cloudValue || cloudValue.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(cloudValue) as MerchantLearningRaw[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const list: MerchantCategory[] = [];
      for (const item of parsed) {
        if (!item || typeof item.merchant !== 'string' || item.merchant.length === 0) {
          continue;
        }
        const record = new MerchantCategory();
        record.merchant = item.merchant;
        record.categoryId = Number(item.categoryId) || 0;
        record.accountType = Number(item.accountType) || 0;
        record.updatedAt = Number(item.updatedAt) || 0;
        list.push(record);
      }
      return list;
    } catch (err) {
      Logger.warn('云端学习记忆解析失败，按空处理');
      return [];
    }
  }

  /** 合并结果按商家名排序后序列化，保证同内容产出同文本、避免无谓补推 */
  private toSortedJson(map: Map<string, MerchantCategory>): string {
    const list: MerchantCategory[] = [];
    map.forEach((value: MerchantCategory): void => {
      list.push(value);
    });
    list.sort((a: MerchantCategory, b: MerchantCategory): number =>
      a.merchant.localeCompare(b.merchant));
    return JSON.stringify(list);
  }
}

export default new MerchantLearningSyncService();
