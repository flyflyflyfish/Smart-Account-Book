import dayjs from 'dayjs';
import util from '@ohos.util';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { zlib } from '@kit.BasicServicesKit';
import { AccountType } from '../models/account/account';
import AccountService from './account';
import AccountPO from '../models/account/accountPO';
import { isDuplicateBill } from '../common/dedup';
import CategoryRegistry from '../models/accountType/CategoryRegistry';
import classifier from './recognition/classifier/CompositeClassifier';
import { Logger } from '../utils/Logger';
import { clampAmount } from '../utils/AmountGuard';

/** 账单文件来源平台 */
export enum BillSourceType {
  ALIPAY,
  WECHAT,
}

/** 单笔待导入账单：解析结果的可变载体，页面勾选后入库 */
export class ImportedBill {
  // 自增 uid：ForEach key 与批内去重定位使用
  private static seq: number = 0;
  readonly uid: number;
  amount: number = 0;
  merchant: string = '';
  description: string = '';
  accountType: AccountType = AccountType.EXPENSES;
  categoryId: number = 0;
  categoryName: string = '';
  payTime: number = 0;
  status: string = '';
  duplicated: boolean = false;
  selected: boolean = true;

  constructor() {
    ImportedBill.seq++;
    this.uid = ImportedBill.seq;
  }
}

/** 解析结果汇总 */
export class ImportParseResult {
  sourceType: BillSourceType = BillSourceType.WECHAT;
  sourceLabel: string = '';
  bills: ImportedBill[] = [];
  skippedCount: number = 0;
  incomeTotal: number = 0;
  expenseTotal: number = 0;
}

/** 账单表头 → 列索引映射，-1 表示该列不存在 */
class BillColumnMap {
  time: number = -1;
  category: number = -1;
  merchant: number = -1;
  goods: number = -1;
  direction: number = -1;
  amount: number = -1;
  status: number = -1;

  static fromHeader(header: string[]): BillColumnMap {
    const map = new BillColumnMap();
    for (let i = 0; i < header.length; i++) {
      const cell = header[i].trim();
      if (cell === '交易时间') {
        map.time = i;
      } else if (cell === '收/支') {
        map.direction = i;
      } else if (cell === '交易对方') {
        map.merchant = i;
      } else if (cell === '商品' || cell === '商品说明') {
        map.goods = i;
      } else if (cell === '金额(元)' || cell === '金额') {
        map.amount = i;
      } else if (cell === '交易状态' || cell === '当前状态') {
        map.status = i;
      } else if (cell === '交易分类' || cell === '交易类型') {
        map.category = i;
      }
    }
    return map;
  }

  isValid(): boolean {
    return this.time >= 0 && this.direction >= 0 && this.amount >= 0;
  }
}

/** Excel 列字母（A/K/AA…）→ 0 起始列索引 */
function columnLettersToIndex(letters: string): number {
  let index = 0;
  for (let i = 0; i < letters.length; i++) {
    index = index * 26 + (letters.charCodeAt(i) - 64);
  }
  return index - 1;
}

/** XML 实体还原（&amp; &lt; &gt; &quot; &apos; 及十进制/十六进制数字实体） */
function decodeXmlEntities(text: string): string {
  let out = text.replace(/&#x([0-9a-fA-F]+);/g, (match: string, hex: string): string => {
    return String.fromCharCode(parseInt(hex, 16));
  });
  out = out.replace(/&#(\d+);/g, (match: string, dec: string): string => {
    return String.fromCharCode(parseInt(dec, 10));
  });
  out = out.replace(/&quot;/g, '"')
    .replace(/&apos;/g, '\'')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');
  return out;
}

/** Excel 1900 日期系统的序列值 → 时间戳：按 UTC+8 墙钟时间落到本机时区 */
function excelSerialToTimestamp(serial: number): number {
  const utcMs = Math.round((serial - 25569) * 86400000);
  const d = new Date(utcMs);
  return new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(),
    d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds()).getTime();
}

/** CSV 单行拆分：支持双引号包裹与引号转义（""），未闭合引号按行尾处理 */
function splitCsvLine(line: string): string[] {
  const fields: string[] = [];
  let current = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQuotes) {
      if (ch === '"') {
        if (i + 1 < line.length && line[i + 1] === '"') {
          current += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        current += ch;
      }
    } else {
      if (ch === '"') {
        inQuotes = true;
      } else if (ch === ',') {
        fields.push(current);
        current = '';
      } else {
        current += ch;
      }
    }
  }
  fields.push(current);
  return fields;
}

/** 金额文本解析：去掉 ¥、千分位逗号与空白后转数值，非法返回 0，超上限压到统一上限 */
function parseAmountText(text: string): number {
  const cleaned = text.replace('¥', '').replace(/,/g, '').trim();
  if (!cleaned) {
    return 0;
  }
  const value = parseFloat(cleaned);
  return isNaN(value) ? 0 : clampAmount(value);
}

/** 交易时间解析：兼容 "yyyy-MM-dd HH:mm:ss" 文本与 Excel 序列值 */
function parseBillTime(text: string): number {
  const trimmed = text.trim();
  if (!trimmed) {
    return 0;
  }
  if (/^\d+(\.\d+)?$/.test(trimmed)) {
    return excelSerialToTimestamp(parseFloat(trimmed));
  }
  const parsed = dayjs(trimmed);
  if (!parsed.isValid()) {
    return 0;
  }
  return parsed.valueOf();
}

/** 状态过滤：退款/失败/关闭/充值的交易不入账（退款与充值非真实收支） */
function isInvalidStatus(status: string): boolean {
  return status.indexOf('退款') >= 0 || status.indexOf('失败') >= 0
    || status.indexOf('关闭') >= 0 || status.indexOf('充值') >= 0;
}

/**
 * 账单文件导入服务：
 * 支持 支付宝交易明细 CSV（GBK/UTF-8）、微信支付账单 CSV / XLSX
 */
class BillImportService {

  /** 判断文件扩展名是否支持导入 */
  isSupportedFile(fileName: string): boolean {
    const lower = fileName.toLowerCase();
    return lower.endsWith('.csv') || lower.endsWith('.xlsx');
  }

  /**
   * 解析账单文件并完成分类与查重
   * @param uri 文件选择器返回的 URI
   * @param context 应用上下文（XLSX 解压使用缓存目录）
   */
  async parseFile(uri: string, context: common.Context): Promise<ImportParseResult> {
    const bytes = this.readAllBytes(uri);
    const lower = uri.toLowerCase();
    let result: ImportParseResult;
    if (lower.endsWith('.xlsx')) {
      result = await this.parseXlsx(bytes, context);
    } else {
      result = this.parseCsv(this.decodeBytes(bytes));
    }
    if (result.bills.length > 0) {
      await this.classifyBills(result.bills);
      await this.markDuplicates(result.bills);
      for (const bill of result.bills) {
        bill.selected = !bill.duplicated;
        if (bill.accountType === AccountType.INCOME) {
          result.incomeTotal += bill.amount;
        } else {
          result.expenseTotal += bill.amount;
        }
      }
    }
    return result;
  }

  /** 读取文件全部字节；文件为空或不可读时抛出异常 */
  private readAllBytes(uri: string): Uint8Array {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      return new Uint8Array(buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  /**
   * 字节解码：UTF-8 BOM 优先，其次严格 UTF-8，失败回退 GBK（支付宝 CSV 默认编码）
   */
  private decodeBytes(bytes: Uint8Array): string {
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
      const body = bytes.subarray(3);
      return util.TextDecoder.create('utf-8').decodeToString(body);
    }
    try {
      return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes);
    } catch (err) {
      Logger.info('账单文件非 UTF-8 编码，按 GBK 解码');
      return util.TextDecoder.create('gbk').decodeToString(bytes);
    }
  }

  /** CSV 解析：定位含「交易时间/收/支」的表头行，逐行解析数据 */
  private parseCsv(text: string): ImportParseResult {
    const result = new ImportParseResult();
    const lines = text.split(/\r?\n/);
    let headerIndex = -1;
    let map: BillColumnMap = new BillColumnMap();
    for (let i = 0; i < lines.length; i++) {
      const fields = splitCsvLine(lines[i]);
      const candidate = BillColumnMap.fromHeader(fields);
      if (candidate.isValid()) {
        headerIndex = i;
        map = candidate;
        result.sourceType = this.detectSourceFromHeader(fields);
        break;
      }
    }
    if (headerIndex < 0) {
      return result;
    }
    result.sourceLabel = this.sourceTypeLabel(result.sourceType);
    for (let i = headerIndex + 1; i < lines.length; i++) {
      if (!lines[i].trim()) {
        continue;
      }
      const bill = this.buildBill(splitCsvLine(lines[i]), map);
      if (bill) {
        result.bills.push(bill);
      } else {
        result.skippedCount++;
      }
    }
    return result;
  }

  /** 按表头特征判断来源平台：含「商品说明/交易分类」为支付宝，含「金额(元)/当前状态」为微信 */
  private detectSourceFromHeader(header: string[]): BillSourceType {
    for (const cell of header) {
      const trimmed = cell.trim();
      if (trimmed === '商品说明' || trimmed === '交易分类' || trimmed === '收/付款方式') {
        return BillSourceType.ALIPAY;
      }
      if (trimmed === '金额(元)' || trimmed === '当前状态' || trimmed === '支付方式') {
        return BillSourceType.WECHAT;
      }
    }
    return BillSourceType.WECHAT;
  }

  private sourceTypeLabel(sourceType: BillSourceType): string {
    return sourceType === BillSourceType.ALIPAY ? '支付宝' : '微信支付';
  }

  /** 一行字段 → 待导入账单；收支方向不符 / 状态无效 / 金额时间非法时返回 null */
  private buildBill(fields: string[], map: BillColumnMap): ImportedBill | null {
    if (map.direction >= fields.length) {
      return null;
    }
    const direction = map.direction >= 0 ? fields[map.direction].trim() : '';
    if (direction !== '收入' && direction !== '支出') {
      return null;
    }
    const status = map.status >= 0 && map.status < fields.length ? fields[map.status].trim() : '';
    if (isInvalidStatus(status)) {
      return null;
    }
    const amount = map.amount >= 0 && map.amount < fields.length
      ? parseAmountText(fields[map.amount]) : 0;
    if (!(amount > 0)) {
      return null;
    }
    const timeText = map.time >= 0 && map.time < fields.length ? fields[map.time] : '';
    const payTime = parseBillTime(timeText);
    if (payTime <= 0) {
      return null;
    }
    const merchant = map.merchant >= 0 && map.merchant < fields.length
      ? fields[map.merchant].trim() : '';
    const goods = map.goods >= 0 && map.goods < fields.length ? fields[map.goods].trim() : '';
    const bill = new ImportedBill();
    bill.accountType = direction === '收入' ? AccountType.INCOME : AccountType.EXPENSES;
    bill.amount = amount;
    bill.payTime = payTime;
    bill.status = status;
    bill.merchant = merchant && merchant !== '/' ? merchant : goods;
    bill.description = goods && goods !== '/' ? goods : bill.merchant;
    return bill;
  }

  /**
   * XLSX 解析：复制为 zip 后经 zlib 解压，读取 sharedStrings 与 sheet1 的 XML 解析行列
   */
  private async parseXlsx(bytes: Uint8Array, context: common.Context): Promise<ImportParseResult> {
    const result = new ImportParseResult();
    const zipPath = `${context.cacheDir}/bill_import_temp.zip`;
    const extractDir = `${context.cacheDir}/bill_import_extract`;
    // 清理上次解压残留，避免旧文件干扰
    this.removeIfExist(zipPath);
    this.removeDirIfExist(extractDir);
    const file = fs.openSync(zipPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes.buffer);
    } finally {
      fs.closeSync(file);
    }
    fs.mkdirSync(extractDir, true);
    await zlib.decompressFile(zipPath, extractDir);
    try {
      const sharedPath = `${extractDir}/xl/sharedStrings.xml`;
      const sheetPath = `${extractDir}/xl/worksheets/sheet1.xml`;
      const shared = fs.accessSync(sharedPath)
        ? util.TextDecoder.create('utf-8').decodeToString(this.readAllBytesByPath(sharedPath)) : '';
      const sheet = util.TextDecoder.create('utf-8').decodeToString(this.readAllBytesByPath(sheetPath));
      const sharedStrings = this.parseSharedStrings(shared);
      const rows = this.parseSheetRows(sheet, sharedStrings);
      result.bills = this.buildBillsFromRows(rows, result);
    } finally {
      this.removeIfExist(zipPath);
      this.removeDirIfExist(extractDir);
    }
    return result;
  }

  private removeIfExist(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (err) {
      Logger.error('清理临时文件失败', (err as Error).message);
    }
  }

  private removeDirIfExist(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.rmdirSync(path);
      }
    } catch (err) {
      Logger.error('清理临时目录失败', (err as Error).message);
    }
  }

  private readAllBytesByPath(path: string): Uint8Array {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      return new Uint8Array(buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  /** 解析 sharedStrings.xml：每个 <si> 内拼接所有 <t> 片段（兼容富文本 run） */
  private parseSharedStrings(xml: string): string[] {
    const strings: string[] = [];
    const siRegex = /<si>([\s\S]*?)<\/si>/g;
    const tRegex = /<t[^>]*>([\s\S]*?)<\/t>/g;
    let siMatch = siRegex.exec(xml);
    while (siMatch !== null) {
      const block = siMatch[1];
      let text = '';
      let tMatch = tRegex.exec(block);
      while (tMatch !== null) {
        text += decodeXmlEntities(tMatch[1]);
        tMatch = tRegex.exec(block);
      }
      tRegex.lastIndex = 0;
      strings.push(text);
      siMatch = siRegex.exec(xml);
    }
    return strings;
  }

  /**
   * 解析 sheet1.xml 为二维行数组：
   * 单元格支持 t="s"（共享字符串）/ t="str" / t="inlineStr" / 数值
   */
  private parseSheetRows(xml: string, sharedStrings: string[]): string[][] {
    const rows: string[][] = [];
    const rowRegex = /<row[^>]*?>([\s\S]*?)<\/row>/g;
    const cellRegex = /<c r="([A-Z]+)\d+"([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g;
    let rowMatch = rowRegex.exec(xml);
    while (rowMatch !== null) {
      const cells: string[] = [];
      const rowContent = rowMatch[1];
      let cellMatch = cellRegex.exec(rowContent);
      while (cellMatch !== null) {
        const colIndex = columnLettersToIndex(cellMatch[1]);
        const attrs = cellMatch[2];
        const content = cellMatch[3] ?? '';
        let value = '';
        if (attrs.indexOf('t="s"') >= 0) {
          const v = this.extractTagText(content, 'v');
          const idx = parseInt(v, 10);
          value = idx >= 0 && idx < sharedStrings.length ? sharedStrings[idx] : '';
        } else if (attrs.indexOf('t="inlineStr"') >= 0) {
          value = decodeXmlEntities(this.extractTagText(content, 't'));
        } else if (attrs.indexOf('t="str"') >= 0) {
          value = decodeXmlEntities(this.extractTagText(content, 'v'));
        } else {
          value = this.extractTagText(content, 'v');
        }
        while (cells.length < colIndex) {
          cells.push('');
        }
        if (colIndex === cells.length) {
          cells.push(value);
        } else if (colIndex < cells.length) {
          cells[colIndex] = value;
        }
        cellMatch = cellRegex.exec(rowContent);
      }
      cellRegex.lastIndex = 0;
      rows.push(cells);
      rowMatch = rowRegex.exec(xml);
    }
    return rows;
  }

  /** 提取 XML 片段中首个指定标签的文本内容 */
  private extractTagText(content: string, tag: string): string {
    const regex = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`);
    const match = regex.exec(content);
    return match !== null ? match[1] : '';
  }

  /** 行数组 → 账单列表：定位表头行后逐行转换 */
  private buildBillsFromRows(rows: string[][], result: ImportParseResult): ImportedBill[] {
    const bills: ImportedBill[] = [];
    let headerIndex = -1;
    let map: BillColumnMap = new BillColumnMap();
    for (let i = 0; i < rows.length; i++) {
      const candidate = BillColumnMap.fromHeader(rows[i]);
      if (candidate.isValid()) {
        headerIndex = i;
        map = candidate;
        result.sourceType = this.detectSourceFromHeader(rows[i]);
        break;
      }
    }
    if (headerIndex < 0) {
      return bills;
    }
    result.sourceLabel = this.sourceTypeLabel(result.sourceType);
    for (let i = headerIndex + 1; i < rows.length; i++) {
      const bill = this.buildBill(rows[i], map);
      if (bill) {
        bills.push(bill);
      } else if (rows[i].length > 0) {
        result.skippedCount++;
      }
    }
    return bills;
  }

  /** 智能分类：商家名 + 商品说明推断分类 id，并回填分类名 */
  private async classifyBills(bills: ImportedBill[]): Promise<void> {
    for (const bill of bills) {
      try {
        const categoryId = await classifier.classify(bill.merchant, bill.description, bill.accountType);
        if (categoryId !== null) {
          bill.categoryId = categoryId;
        }
        bill.categoryName = CategoryRegistry.nameText(bill.categoryId, bill.accountType);
      } catch (err) {
        Logger.error('导入账单分类失败', (err as Error).message);
        bill.categoryName = CategoryRegistry.nameText(bill.categoryId, bill.accountType);
      }
    }
  }

  /** 查重：先与库内已有账单比较，再批内去重（重复项默认不勾选） */
  private async markDuplicates(bills: ImportedBill[]): Promise<void> {
    if (bills.length === 0) {
      return;
    }
    let minTime = bills[0].payTime;
    let maxTime = bills[0].payTime;
    for (const bill of bills) {
      if (bill.payTime < minTime) {
        minTime = bill.payTime;
      }
      if (bill.payTime > maxTime) {
        maxTime = bill.payTime;
      }
    }
    let existing: AccountPO[] = [];
    try {
      existing = await AccountService.queryByDateRange(minTime - 24 * 60 * 60 * 1000,
        maxTime + 24 * 60 * 60 * 1000);
    } catch (err) {
      Logger.error('导入查重查询失败', (err as Error).message);
    }
    for (let i = 0; i < bills.length; i++) {
      const bill = bills[i];
      for (const po of existing) {
        if (isDuplicateBill(bill.amount, bill.merchant, bill.payTime,
          po.amount, po.merchant, po.payTime)) {
          bill.duplicated = true;
          break;
        }
      }
      if (bill.duplicated) {
        continue;
      }
      for (let j = 0; j < i; j++) {
        const prev = bills[j];
        if (isDuplicateBill(bill.amount, bill.merchant, bill.payTime,
          prev.amount, prev.merchant, prev.payTime)) {
          bill.duplicated = true;
          break;
        }
      }
    }
  }
}

export default new BillImportService();
