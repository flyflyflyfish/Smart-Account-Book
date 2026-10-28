import relationalStore from '@ohos.data.relationalStore';
import util from '@ohos.util';
import DBUtil from '../utils/DBUtil';
import { LEDGER_RECORD_TABLE_NAME, LEDGER_TABLE_NAME } from './schema';
import {
  Ledger,
  LedgerOverview,
  LedgerRecord,
  LEDGER_COLOR_DEFAULT,
  LEDGER_RECORD_EXPENSE,
  LEDGER_RECORD_NO_CATEGORY
} from '../models/ledger/Ledger';

const COL_ID: string = 'id';
const COL_NAME: string = 'name';
const COL_COLOR_KEY: string = 'color_key';
const COL_CREATED_AT: string = 'created_at';
const COL_LEDGER_ID: string = 'ledger_id';
const COL_TYPE: string = 'type';
const COL_AMOUNT: string = 'amount';
const COL_NOTE: string = 'note';
const COL_TIME: string = 'time';
const COL_CATEGORY: string = 'category';
const COL_BILL_ID: string = 'bill_id';

const LEDGER_COLUMNS: string[] = [COL_ID, COL_NAME, COL_COLOR_KEY, COL_CREATED_AT];
const RECORD_COLUMNS: string[] = [
  COL_ID, COL_LEDGER_ID, COL_TYPE, COL_AMOUNT, COL_NOTE, COL_TIME, COL_CREATED_AT, COL_CATEGORY, COL_BILL_ID
];

/**
 * 账本数据仓储：读写 ledger / ledger_record 两张表
 */
export default class LedgerRepository {

  private parseLedger(result: relationalStore.ResultSet): Ledger {
    const ledger = new Ledger();
    ledger.id = result.getString(result.getColumnIndex(COL_ID));
    ledger.name = result.getString(result.getColumnIndex(COL_NAME));
    ledger.colorKey = result.getString(result.getColumnIndex(COL_COLOR_KEY)) || LEDGER_COLOR_DEFAULT;
    ledger.createdAt = result.getLong(result.getColumnIndex(COL_CREATED_AT));
    return ledger;
  }

  private parseRecord(result: relationalStore.ResultSet): LedgerRecord {
    const record = new LedgerRecord();
    record.id = result.getString(result.getColumnIndex(COL_ID));
    record.ledgerId = result.getString(result.getColumnIndex(COL_LEDGER_ID));
    record.type = result.getLong(result.getColumnIndex(COL_TYPE));
    record.amount = result.getDouble(result.getColumnIndex(COL_AMOUNT));
    record.note = result.getString(result.getColumnIndex(COL_NOTE));
    record.time = result.getLong(result.getColumnIndex(COL_TIME));
    record.createdAt = result.getLong(result.getColumnIndex(COL_CREATED_AT));
    // 老库迁移前的记录 category 为空时统一回退未选分类
    const categoryIndex = result.getColumnIndex(COL_CATEGORY);
    record.category = result.isColumnNull(categoryIndex) ? LEDGER_RECORD_NO_CATEGORY
      : result.getLong(categoryIndex);
    // 关联主账单 id：空值回退空串（与主账单无关）
    const billIdIndex = result.getColumnIndex(COL_BILL_ID);
    record.billId = result.isColumnNull(billIdIndex) ? '' : result.getString(billIdIndex);
    return record;
  }

  /** 查询全部账本（按创建时间升序，先建的在前） */
  async queryLedgers(): Promise<Ledger[]> {
    const predicates = new relationalStore.RdbPredicates(LEDGER_TABLE_NAME);
    predicates.orderByAsc(COL_CREATED_AT);
    const result = await DBUtil.query(predicates, LEDGER_COLUMNS);
    const list: Ledger[] = [];
    try {
      while (result.goToNextRow()) {
        list.push(this.parseLedger(result));
      }
    } finally {
      result.close();
    }
    return list;
  }

  /** 按主键查单个账本，不存在返回 null */
  async queryLedgerById(id: string): Promise<Ledger | null> {
    const predicates = new relationalStore.RdbPredicates(LEDGER_TABLE_NAME);
    predicates.equalTo(COL_ID, id);
    const result = await DBUtil.query(predicates, LEDGER_COLUMNS);
    try {
      if (result.goToNextRow()) {
        return this.parseLedger(result);
      }
      return null;
    } finally {
      result.close();
    }
  }

  /** 新建账本，主键由 UUID 生成 */
  async insertLedger(name: string, colorKey: string): Promise<Ledger> {
    const ledger = new Ledger();
    ledger.id = util.generateRandomUUID();
    ledger.name = name;
    ledger.colorKey = colorKey;
    ledger.createdAt = Date.now();
    const bucket: relationalStore.ValuesBucket = {
      'id': ledger.id,
      'name': ledger.name,
      'color_key': ledger.colorKey,
      'created_at': ledger.createdAt
    };
    await DBUtil.insert(LEDGER_TABLE_NAME, bucket);
    return ledger;
  }

  /** 重命名账本，返回更新行数 */
  async renameLedger(id: string, name: string): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(LEDGER_TABLE_NAME);
    predicates.equalTo(COL_ID, id);
    const bucket: relationalStore.ValuesBucket = { 'name': name };
    return DBUtil.update(predicates, bucket);
  }

  /** 更新账本颜色 key，返回更新行数 */
  async updateLedgerColor(id: string, colorKey: string): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(LEDGER_TABLE_NAME);
    predicates.equalTo(COL_ID, id);
    const bucket: relationalStore.ValuesBucket = { 'color_key': colorKey };
    return DBUtil.update(predicates, bucket);
  }

  /** 删除账本及其全部记录，返回删除的账本行数 */
  async deleteLedger(id: string): Promise<number> {
    const recordPredicates = new relationalStore.RdbPredicates(LEDGER_RECORD_TABLE_NAME);
    recordPredicates.equalTo(COL_LEDGER_ID, id);
    await DBUtil.delete(recordPredicates);
    const predicates = new relationalStore.RdbPredicates(LEDGER_TABLE_NAME);
    predicates.equalTo(COL_ID, id);
    return DBUtil.delete(predicates);
  }

  /** 查询账本内全部记录（按记录时间倒序，新的在前） */
  async queryRecords(ledgerId: string): Promise<LedgerRecord[]> {
    const predicates = new relationalStore.RdbPredicates(LEDGER_RECORD_TABLE_NAME);
    predicates.equalTo(COL_LEDGER_ID, ledgerId);
    predicates.orderByDesc(COL_TIME);
    const result = await DBUtil.query(predicates, RECORD_COLUMNS);
    const list: LedgerRecord[] = [];
    try {
      while (result.goToNextRow()) {
        list.push(this.parseRecord(result));
      }
    } finally {
      result.close();
    }
    return list;
  }

  /** 按主键查单笔记录，不存在返回 null */
  async queryRecordById(id: string): Promise<LedgerRecord | null> {
    const predicates = new relationalStore.RdbPredicates(LEDGER_RECORD_TABLE_NAME);
    predicates.equalTo(COL_ID, id);
    const result = await DBUtil.query(predicates, RECORD_COLUMNS);
    try {
      if (result.goToNextRow()) {
        return this.parseRecord(result);
      }
      return null;
    } finally {
      result.close();
    }
  }

  /** 新增一笔账本记录，主键由 UUID 生成；billId 为关联主账单 id（无关联传空串） */
  async insertRecord(ledgerId: string, type: number, amount: number, note: string,
    time: number, category: number, billId: string): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'id': util.generateRandomUUID(),
      'ledger_id': ledgerId,
      'type': type,
      'amount': amount,
      'note': note,
      'time': time,
      'created_at': Date.now(),
      'category': category,
      'bill_id': billId
    };
    await DBUtil.insert(LEDGER_RECORD_TABLE_NAME, bucket);
  }

  /** 查询账本内已关联的主账单 id 集合，供“从现有账单导入”防重复勾选 */
  async queryImportedBillIds(ledgerId: string): Promise<string[]> {
    const predicates = new relationalStore.RdbPredicates(LEDGER_RECORD_TABLE_NAME);
    predicates.equalTo(COL_LEDGER_ID, ledgerId);
    const result = await DBUtil.query(predicates, [COL_BILL_ID]);
    const ids: string[] = [];
    try {
      while (result.goToNextRow()) {
        const billIdIndex = result.getColumnIndex(COL_BILL_ID);
        if (!result.isColumnNull(billIdIndex)) {
          const billId = result.getString(billIdIndex);
          if (billId.length > 0) {
            ids.push(billId);
          }
        }
      }
    } finally {
      result.close();
    }
    return ids;
  }

  /** 编辑一笔账本记录（金额/类型/备注/时间/分类），返回更新行数 */
  async updateRecord(id: string, type: number, amount: number, note: string,
    time: number, category: number): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(LEDGER_RECORD_TABLE_NAME);
    predicates.equalTo(COL_ID, id);
    const bucket: relationalStore.ValuesBucket = {
      'type': type,
      'amount': amount,
      'note': note,
      'time': time,
      'category': category
    };
    return DBUtil.update(predicates, bucket);
  }

  /** 删除一笔账本记录，返回删除行数 */
  async deleteRecord(id: string): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(LEDGER_RECORD_TABLE_NAME);
    predicates.equalTo(COL_ID, id);
    return DBUtil.delete(predicates);
  }

  /** 批量删除账本记录，返回删除行数 */
  async deleteRecords(ids: string[]): Promise<number> {
    // 不用 RdbPredicates.in()：真机实测抛 Parameter error. The value must be a ValueType array，
    // 对齐主账单 deleteByIds 的已验证路径，循环单条删除
    let rows = 0;
    for (const id of ids) {
      rows += await this.deleteRecord(id);
    }
    return rows;
  }

  /**
   * 查询全部账本的汇总视图：账本列表 + 每本支出/收入/笔数。
   * 一次性读出全部记录在内存聚合，避免列表页逐本查询。
   */
  async queryOverviews(): Promise<LedgerOverview[]> {
    const ledgers = await this.queryLedgers();
    const predicates = new relationalStore.RdbPredicates(LEDGER_RECORD_TABLE_NAME);
    const result = await DBUtil.query(predicates, RECORD_COLUMNS);
    const overviews: LedgerOverview[] = ledgers.map((ledger: Ledger): LedgerOverview => {
      const overview = new LedgerOverview();
      overview.ledger = ledger;
      return overview;
    });
    try {
      while (result.goToNextRow()) {
        const record = this.parseRecord(result);
        const matched = overviews.find((item: LedgerOverview): boolean => item.ledger.id === record.ledgerId);
        if (matched) {
          matched.recordCount += 1;
          if (record.type === LEDGER_RECORD_EXPENSE) {
            matched.expenses += record.amount;
          } else {
            matched.income += record.amount;
          }
        }
      }
    } finally {
      result.close();
    }
    return overviews;
  }
}
