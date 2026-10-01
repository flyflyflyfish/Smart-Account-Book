import relationalStore from '@ohos.data.relationalStore';
import DBUtil from '../utils/DBUtil';
import MerchantCategory from '../models/recognition/MerchantCategory';
import { MERCHANT_CATEGORY_TABLE_NAME } from './schema';

/**
 * 商家-分类存储接口：隔离数据访问，便于测试注入假实现
 */
export interface MerchantCategoryStore {
  queryByMerchant(merchant: string): Promise<MerchantCategory | null>;

  upsert(record: MerchantCategory): Promise<void>;

  clearAll(): Promise<number>;
}

const COL_MERCHANT: string = 'merchant';
const COL_CATEGORY_ID: string = 'category_id';
const COL_ACCOUNT_TYPE: string = 'account_type';
const COL_UPDATED_AT: string = 'updated_at';

const QUERY_COLUMNS: string[] = [COL_MERCHANT, COL_CATEGORY_ID, COL_ACCOUNT_TYPE, COL_UPDATED_AT];

/**
 * 商家-分类映射仓储：读写 merchant_category 表，支撑“同商家下次优先命中”
 */
export default class MerchantCategoryRepository implements MerchantCategoryStore {
  private parseRecord(result: relationalStore.ResultSet): MerchantCategory {
    const record = new MerchantCategory();
    record.merchant = result.getString(result.getColumnIndex(COL_MERCHANT));
    record.categoryId = result.getLong(result.getColumnIndex(COL_CATEGORY_ID));
    record.accountType = result.getLong(result.getColumnIndex(COL_ACCOUNT_TYPE));
    record.updatedAt = result.getLong(result.getColumnIndex(COL_UPDATED_AT));
    return record;
  }

  async queryByMerchant(merchant: string): Promise<MerchantCategory | null> {
    const predicates = new relationalStore.RdbPredicates(MERCHANT_CATEGORY_TABLE_NAME);
    predicates.equalTo(COL_MERCHANT, merchant);
    const result = await DBUtil.query(predicates, QUERY_COLUMNS);
    if (result.goToNextRow()) {
      const record = this.parseRecord(result);
      result.close();
      return record;
    }
    result.close();
    return null;
  }

  // merchant 为主键：已存在则更新，否则插入
  async upsert(record: MerchantCategory): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'merchant': record.merchant,
      'category_id': record.categoryId,
      'account_type': record.accountType,
      'updated_at': record.updatedAt
    };
    const existing = await this.queryByMerchant(record.merchant);
    if (existing) {
      const predicates = new relationalStore.RdbPredicates(MERCHANT_CATEGORY_TABLE_NAME);
      predicates.equalTo(COL_MERCHANT, record.merchant);
      await DBUtil.update(predicates, bucket);
      return;
    }
    await DBUtil.insert(MERCHANT_CATEGORY_TABLE_NAME, bucket);
  }

  // 清除全部商家-分类记忆，返回删除行数；updated_at 恒 >= 0，故可匹配所有行
  async clearAll(): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(MERCHANT_CATEGORY_TABLE_NAME);
    predicates.greaterThanOrEqualTo(COL_UPDATED_AT, 0);
    return DBUtil.delete(predicates);
  }
}
