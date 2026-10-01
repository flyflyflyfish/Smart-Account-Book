import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import { Logger } from './Logger';
import { DbError } from './DbError';
import { ACCOUNT_TABLE_NAME } from '../data/schema';

const DB_FILENAME: string = 'account.db';

class DBUtil {
  private rdbStore: relationalStore.RdbStore | undefined = undefined;
  private readyResolve: (() => void) | undefined = undefined;
  readonly ready: Promise<void>;

  constructor() {
    // 初始化完成后由 markReady 决议，供页面等待初始化时序
    this.ready = new Promise<void>((resolve: () => void) => {
      this.readyResolve = resolve;
    });
  }

  markReady(): void {
    if (this.readyResolve) {
      this.readyResolve();
      this.readyResolve = undefined;
    }
  }

  async initDB(context: common.UIAbilityContext): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: DB_FILENAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    try {
      this.rdbStore = await relationalStore.getRdbStore(context, config);
      Logger.debug('rdbStore 初始化完成');
    } catch (err) {
      const e = err as Error;
      Logger.error('rdbStore 初始化异常', e.message);
      throw new DbError('rdbStore 初始化异常');
    }
  }

  async createTable(createSQL: string): Promise<void> {
    if (!this.rdbStore) {
      throw new DbError('rdbStore 尚未初始化，无法创建数据表');
    }
    try {
      await this.rdbStore.executeSql(createSQL);
      Logger.debug('数据表创建成功');
    } catch (err) {
      const e = err as Error;
      Logger.error('数据表创建失败', e.message);
      throw new DbError('数据表创建失败');
    }
  }

  // 判断表是否已存在：用于区分新装与老库，避免新装重复补列
  private async tableExists(tableName: string): Promise<boolean> {
    if (!this.rdbStore) {
      return false;
    }
    const sql = `SELECT name FROM sqlite_master WHERE type = 'table' AND name = '${tableName}'`;
    const result = await this.rdbStore.querySql(sql);
    const exists = result.goToNextRow();
    result.close();
    return exists;
  }

  /**
   * 数据库版本迁移：老库（version 低于目标版本且账单表已存在）逐条执行补列 SQL，
   * 全部成功后把 version 置为目标版本；新装的库表尚不存在，直接置版本号，
   * 新列由建表语句保证。任一步失败抛错且不更新版本号，下次启动重试。
   */
  async migrateIfNeeded(targetVersion: number, alterSqls: string[]): Promise<void> {
    if (!this.rdbStore) {
      throw new DbError('rdbStore 尚未初始化，无法执行数据库迁移');
    }
    const currentVersion = this.rdbStore.version;
    if (currentVersion >= targetVersion) {
      Logger.debug('数据库版本已是最新', currentVersion);
      return;
    }
    try {
      const hasAccountTable = await this.tableExists(ACCOUNT_TABLE_NAME);
      if (hasAccountTable) {
        for (const sql of alterSqls) {
          await this.rdbStore.executeSql(sql);
          Logger.debug('数据库迁移执行成功');
        }
      }
      this.rdbStore.version = targetVersion;
      Logger.debug('数据库迁移完成, 版本: ', targetVersion);
    } catch (err) {
      const e = err as Error;
      Logger.error('数据库迁移失败', e.message);
      throw new DbError('数据库迁移失败');
    }
  }

  async insert(tableName: string, values: relationalStore.ValuesBucket): Promise<number> {
    if (!this.rdbStore) {
      throw new DbError('rdbStore 尚未初始化');
    }
    const start = Date.now();
    try {
      const id = await this.rdbStore.insert(tableName, values);
      Logger.debug('新增数据成功, 耗时(ms): ', Date.now() - start);
      return id;
    } catch (err) {
      const e = err as Error;
      Logger.error('新增数据失败', e.message);
      throw new DbError('新增数据失败');
    }
  }

  async delete(predicates: relationalStore.RdbPredicates): Promise<number> {
    if (!this.rdbStore) {
      throw new DbError('rdbStore 尚未初始化');
    }
    const start = Date.now();
    try {
      const rows = await this.rdbStore.delete(predicates);
      Logger.debug('删除数据成功, 删除行数: ', rows, '耗时(ms): ', Date.now() - start);
      return rows;
    } catch (err) {
      const e = err as Error;
      Logger.error('删除数据失败', e.message);
      throw new DbError('删除数据失败');
    }
  }

  async update(predicates: relationalStore.RdbPredicates, values: relationalStore.ValuesBucket): Promise<number> {
    if (!this.rdbStore) {
      throw new DbError('rdbStore 尚未初始化');
    }
    const start = Date.now();
    try {
      const rows = await this.rdbStore.update(values, predicates);
      Logger.debug('更新数据成功, 更新行数: ', rows, '耗时(ms): ', Date.now() - start);
      return rows;
    } catch (err) {
      const e = err as Error;
      Logger.error('更新数据失败', e.message);
      throw new DbError('更新数据失败');
    }
  }

  async query(predicates: relationalStore.RdbPredicates, columns: string[]): Promise<relationalStore.ResultSet> {
    if (!this.rdbStore) {
      throw new DbError('rdbStore 尚未初始化');
    }
    const start = Date.now();
    try {
      const result = await this.rdbStore.query(predicates, columns);
      Logger.debug('查询数据成功, 查询总数: ', result.rowCount, '耗时(ms): ', Date.now() - start);
      return result;
    } catch (err) {
      const e = err as Error;
      Logger.error('查询数据失败', e.message);
      throw new DbError('查询数据失败');
    }
  }
}

export default new DBUtil();
