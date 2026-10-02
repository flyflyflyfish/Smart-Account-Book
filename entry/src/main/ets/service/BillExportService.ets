import dayjs from 'dayjs';
import util from '@ohos.util';
import { AccountType } from '../models/account/account';
import AccountPO from '../models/account/accountPO';
import CategoryStore from '../models/accountType/CategoryStore';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

const WEEK_CN: string[] = ['日', '一', '二', '三', '四', '五', '六'];

/**
 * 分类统计项
 */
interface CategoryStat {
  type: number;
  accountType: number;
  name: string;
  amount: number;
  count: number;
}

/**
 * 按日分组
 */
interface DayGroup {
  time: number;
  expenses: number;
  income: number;
  records: AccountPO[];
}

/**
 * 账单汇总
 */
export interface BillSummary {
  expenses: number;
  income: number;
  balance: number;
  count: number;
}

/**
 * 导出内容自定义选项
 */
export interface ExportOptions {
  includeSummary: boolean;
  includeCategory: boolean;
  includeDetail: boolean;
  groupByDay: boolean;
}

interface WRunOptions {
  bold?: boolean;
  color?: string;
  sz?: number;
}

interface WParaOptions {
  align?: string;
  spacingAfter?: number;
}

interface ZipEntry {
  name: string;
  data: Uint8Array;
}

/**
 * 账单导出服务：把指定时间跨度内的账单渲染成自包含的 HTML 文档。
 * - Word 模式：A4 版式、pt 字号、纯表格排版，Word/WPS 打开效果规整；
 * - Web 模式：供隐藏 Web 组件加载后交给 Print Kit 生成 PDF。
 */
class BillExportService {
  // 分类名：经分类存储解析，支持用户自定义分类
  private categoryName(type: number, accountType: number): string {
    return CategoryStore.nameText(type, accountType);
  }

  // HTML 转义，防止备注/商家中的特殊字符破坏文档结构
  private escapeHtml(text: string): string {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  // 金额格式化：两位小数 + 千分位
  private money(value: number): string {
    const fixed = value.toFixed(2);
    const parts = fixed.split('.');
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    return parts.join('.');
  }

  private sign(record: AccountPO): string {
    return record.accountType === AccountType.EXPENSES ? '-' : '+';
  }

  private weekday(time: number): string {
    return WEEK_CN[dayjs(time).day()];
  }

  // 记录的有效发生时间：优先支付时间
  private recordTime(record: AccountPO): number {
    const payTime = record.payTime ?? 0;
    return payTime > 0 ? payTime : record.time;
  }

  private timeText(record: AccountPO): string {
    return dayjs(this.recordTime(record)).format('HH:mm');
  }

  /**
   * 汇总收支与笔数
   */
  summarize(records: AccountPO[]): BillSummary {
    let expenses = 0;
    let income = 0;
    records.forEach((record: AccountPO) => {
      if (record.accountType === AccountType.EXPENSES) {
        expenses += record.amount;
      } else {
        income += record.amount;
      }
    });
    return { expenses, income, balance: income - expenses, count: records.length };
  }

  /**
   * 按收支类型聚合分类统计，按金额降序
   */
  private buildCategoryStats(records: AccountPO[], accountType: number): CategoryStat[] {
    const map = new Map<number, CategoryStat>();
    records.forEach((record: AccountPO) => {
      if (record.accountType !== accountType) {
        return;
      }
      let stat = map.get(record.type);
      if (!stat) {
        stat = {
          type: record.type,
          accountType: record.accountType,
          name: this.categoryName(record.type, record.accountType),
          amount: 0,
          count: 0
        };
        map.set(record.type, stat);
      }
      stat.amount += record.amount;
      stat.count += 1;
    });
    const list: CategoryStat[] = Array.from(map.values());
    list.sort((a: CategoryStat, b: CategoryStat): number => b.amount - a.amount);
    return list;
  }

  /**
   * 按天分组，日期降序，组内按支付时间降序
   */
  private buildDayGroups(records: AccountPO[]): DayGroup[] {
    const map = new Map<number, DayGroup>();
    records.forEach((record: AccountPO) => {
      const dayTime = dayjs(record.time).startOf('day').valueOf();
      let group = map.get(dayTime);
      if (!group) {
        group = { time: dayTime, expenses: 0, income: 0, records: [] };
        map.set(dayTime, group);
      }
      if (record.accountType === AccountType.EXPENSES) {
        group.expenses += record.amount;
      } else {
        group.income += record.amount;
      }
      group.records.push(record);
    });
    const list: DayGroup[] = Array.from(map.values());
    list.sort((a: DayGroup, b: DayGroup): number => b.time - a.time);
    list.forEach((group: DayGroup) => {
      group.records.sort((a: AccountPO, b: AccountPO): number => this.recordTime(b) - this.recordTime(a));
    });
    return list;
  }

  /**
   * 不分组时的流水列表：按时间倒序
   */
  private flatRecords(records: AccountPO[]): AccountPO[] {
    const list: AccountPO[] = records.slice();
    list.sort((a: AccountPO, b: AccountPO): number => this.recordTime(b) - this.recordTime(a));
    return list;
  }

  // ==================== Web / PDF 版式 ====================

  private renderSummary(summary: BillSummary): string {
    const balColor = summary.balance >= 0 ? 'bal' : 'exp';
    return `<table class="summary"><tr>` +
      `<td><div class="label">总支出</div><div class="value exp">¥ ${this.money(summary.expenses)}</div></td>` +
      `<td><div class="label">总收入</div><div class="value inc">¥ ${this.money(summary.income)}</div></td>` +
      `<td><div class="label">结余</div><div class="value ${balColor}">¥ ${this.money(summary.balance)}</div></td>` +
      `</tr></table>`;
  }

  private renderCategorySection(title: string, stats: CategoryStat[], total: number): string {
    if (stats.length === 0) {
      return '';
    }
    let rows = '';
    stats.forEach((stat: CategoryStat) => {
      const percent = total > 0 ? Math.round(stat.amount / total * 100) : 0;
      rows += `<tr>` +
        `<td width="26%">${this.escapeHtml(stat.name)}</td>` +
        `<td width="30%" class="muted">¥ ${this.money(stat.amount)} · ${stat.count}笔</td>` +
        `<td><table class="bar-bg"><tr><td><div class="bar-fill" style="width:${percent}%"></div></td></tr></table></td>` +
        `<td width="12%" class="muted">${percent}%</td>` +
        `</tr>`;
    });
    return `<div class="section-title">${title}</div>` +
      `<div class="card"><table class="cat">${rows}</table></div>`;
  }

  private renderItemRow(record: AccountPO, timeText: string, wideTime: boolean): string {
    const name = this.categoryName(record.type, record.accountType);
    const title = record.description || record.merchant || name;
    const sub = record.description && record.merchant ? record.merchant : '';
    const amountClass = record.accountType === AccountType.EXPENSES ? 'amt-exp' : 'amt-inc';
    const timeClass = wideTime ? 'time time-wide muted' : 'time muted';
    return `<tr>` +
      `<td class="item-main"><span class="cat-badge">${this.escapeHtml(name)}</span><span class="desc">${this.escapeHtml(title)}</span>` +
      (sub ? `<span class="merchant">${this.escapeHtml(sub)}</span>` : '') +
      `</td>` +
      `<td class="${timeClass}">${timeText}</td>` +
      `<td class="${amountClass}">${this.sign(record)}${this.money(record.amount)}</td>` +
      `</tr>`;
  }

  private renderDayGroup(group: DayGroup): string {
    const date = dayjs(group.time);
    let head = `${date.format('M月D日')} · 周${this.weekday(group.time)}`;
    const parts: string[] = [];
    if (group.expenses > 0) {
      parts.push(`支出 ¥${this.money(group.expenses)}`);
    }
    if (group.income > 0) {
      parts.push(`收入 ¥${this.money(group.income)}`);
    }
    if (parts.length > 0) {
      head += `　${parts.join('　')}`;
    }
    let rows = '';
    group.records.forEach((record: AccountPO) => {
      rows += this.renderItemRow(record, this.timeText(record), false);
    });
    return `<div class="card"><div class="day-head">${head}</div><table class="items">${rows}</table></div>`;
  }

  // 导出文档主题色：固定当前主题浅色套，保证打印/文档可读性
  private docTheme(): ThemePalette {
    return ThemeKit.lightPalette();
  }

  // docx 颜色格式：不带 # 的 RRGGBB
  private docHex(color: string): string {
    return color.substring(1);
  }

  private buildWebHtml(records: AccountPO[], startTime: number, endTime: number, options: ExportOptions): string {
    const summary = this.summarize(records);
    const range = `${dayjs(startTime).format('YYYY-MM-DD')} ~ ${dayjs(endTime).format('YYYY-MM-DD')}`;
    const generatedAt = dayjs().format('YYYY-MM-DD HH:mm');

    let bodyHtml = '';
    if (options.includeSummary) {
      bodyHtml += this.renderSummary(summary);
    }
    if (options.includeCategory) {
      bodyHtml += this.renderCategorySection('分类统计 · 支出',
        this.buildCategoryStats(records, AccountType.EXPENSES), summary.expenses);
      bodyHtml += this.renderCategorySection('分类统计 · 收入',
        this.buildCategoryStats(records, AccountType.INCOME), summary.income);
    }
    if (options.includeDetail) {
      if (records.length > 0) {
        if (options.groupByDay) {
          const dayGroups = this.buildDayGroups(records);
          let days = '';
          dayGroups.forEach((group: DayGroup) => {
            days += this.renderDayGroup(group);
          });
          bodyHtml += `<div class="section-title">收支明细（${summary.count}笔）</div>${days}`;
        } else {
          let rows = '';
          this.flatRecords(records).forEach((record: AccountPO) => {
            rows += this.renderItemRow(record, dayjs(this.recordTime(record)).format('MM-DD HH:mm'), true);
          });
          bodyHtml += `<div class="section-title">收支明细（${summary.count}笔）</div>` +
            `<div class="card"><table class="items">${rows}</table></div>`;
        }
      } else {
        bodyHtml += `<div class="card empty">该时间段暂无账单记录</div>`;
      }
    }

    return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { background:#FFFFFF; color:#1F2329; font-family:"PingFang SC","Microsoft YaHei","Noto Sans CJK SC",sans-serif; }
  .page { max-width:680px; margin:0 auto; padding:16px; }
  .header { background:${this.docTheme().primary}; background:linear-gradient(135deg,${this.docTheme().primary},${this.docTheme().onPrimaryContainer}); color:#fff; padding:24px 20px; border-radius:16px; }
  .header .brand { font-size:13px; opacity:.88; }
  .header .title { font-size:26px; font-weight:bold; margin-top:8px; }
  .header .range { font-size:13px; margin-top:8px; opacity:.92; }
  table.summary { width:100%; border-collapse:separate; border-spacing:8px; margin:12px -8px 0; }
  table.summary td { background:#fff; border:1px solid #F0F0F0; border-radius:12px; padding:16px 10px; text-align:center; }
  .summary .label { font-size:12px; color:#999; }
  .summary .value { font-size:20px; font-weight:bold; margin-top:8px; }
  .exp { color:${this.docTheme().danger}; }
  .inc { color:${this.docTheme().success}; }
  .bal { color:#1F2329; }
  .card { background:#fff; border:1px solid #F0F0F0; border-radius:16px; padding:14px 18px; margin-top:10px; }
  .section-title { font-size:15px; font-weight:bold; margin:18px 4px 4px; color:#333; }
  table.cat { width:100%; border-collapse:collapse; }
  table.cat td { padding:9px 0; border-bottom:1px solid #F0F0F0; font-size:13px; vertical-align:middle; }
  table.cat tr:last-child td { border-bottom:none; }
  .muted { color:#999; }
  table.bar-bg { width:100%; border-collapse:collapse; }
  table.bar-bg td { padding:0; border:none; }
  .bar-bg { background:#F0F0F0; height:6px; border-radius:3px; }
  .bar-fill { height:6px; border-radius:3px; background:${this.docTheme().primary}; }
  .day-head { background:#F4F5F7; font-size:13px; color:#333; font-weight:bold; padding:8px 10px; border-radius:8px; }
  table.items { width:100%; border-collapse:collapse; }
  table.items td { padding:10px 6px; border-bottom:1px solid #F0F0F0; font-size:14px; vertical-align:middle; }
  table.items tr:last-child td { border-bottom:none; }
  .item-main { line-height:1.5; }
  .cat-badge { display:inline-block; padding:2px 8px; border-radius:10px; background:${this.docTheme().primaryContainer}; color:${this.docTheme().onPrimaryContainer}; font-size:12px; margin-right:8px; }
  .desc { color:#1F2329; }
  .merchant { color:#999; font-size:12px; }
  .time { color:#999; font-size:12px; text-align:center; width:52px; }
  .time-wide { width:78px; }
  .amt-exp { color:${this.docTheme().danger}; font-weight:bold; text-align:right; width:110px; }
  .amt-inc { color:${this.docTheme().success}; font-weight:bold; text-align:right; width:110px; }
  .empty { color:#999; text-align:center; padding:40px 0; }
  .footer { text-align:center; color:#999; font-size:12px; margin:24px 0 12px; }
</style>
</head>
<body>
<div class="page">
  <div class="header">
    <div class="brand">记账助手 · 账单明细</div>
    <div class="title">账单明细</div>
    <div class="range">${range}</div>
  </div>
  ${bodyHtml}
  <div class="footer">由「记账助手」生成于 ${generatedAt}</div>
</div>
</body>
</html>`;
  }

  // ==================== Word 版式（A4、pt 字号、纯表格） ====================

  private wordHeader(range: string, count: number): string {
    return `<table width="100%" cellspacing="0" cellpadding="0"><tr>` +
      `<td bgcolor="${this.docTheme().primary}" style="padding:16pt 18pt;">` +
      `<div style="font-size:9pt;color:#D8FBF0;">记账助手</div>` +
      `<div style="font-size:19pt;font-weight:bold;color:#FFFFFF;margin-top:2pt;">账单明细</div>` +
      `<div style="font-size:10pt;color:#EAFFF5;margin-top:4pt;">${this.escapeHtml(range)} · 共 ${count} 笔</div>` +
      `</td></tr></table>`;
  }

  private wordSummary(summary: BillSummary): string {
    return `<table width="100%" cellspacing="8" cellpadding="0" style="margin-top:4pt;"><tr>` +
      `<td width="33%" align="center" style="border:1pt solid #E8E8E8;padding:10pt 6pt;">` +
      `<div style="font-size:9pt;color:#999999;">总支出</div>` +
      `<div style="font-size:14pt;font-weight:bold;color:${this.docTheme().danger};margin-top:3pt;">¥ ${this.money(summary.expenses)}</div></td>` +
      `<td width="33%" align="center" style="border:1pt solid #E8E8E8;padding:10pt 6pt;">` +
      `<div style="font-size:9pt;color:#999999;">总收入</div>` +
      `<div style="font-size:14pt;font-weight:bold;color:${this.docTheme().success};margin-top:3pt;">¥ ${this.money(summary.income)}</div></td>` +
      `<td width="33%" align="center" style="border:1pt solid #E8E8E8;padding:10pt 6pt;">` +
      `<div style="font-size:9pt;color:#999999;">结余</div>` +
      `<div style="font-size:14pt;font-weight:bold;color:#1F2329;margin-top:3pt;">¥ ${this.money(summary.balance)}</div></td>` +
      `</tr></table>`;
  }

  private wordCategorySection(title: string, stats: CategoryStat[], total: number): string {
    if (stats.length === 0) {
      return '';
    }
    let rows = `<tr bgcolor="#F4F5F7">` +
      `<td class="headcell" width="30%">分类</td>` +
      `<td class="headcell" width="30%" align="right">金额</td>` +
      `<td class="headcell" width="20%" align="center">笔数</td>` +
      `<td class="headcell" width="20%" align="right">占比</td></tr>`;
    stats.forEach((stat: CategoryStat) => {
      const percent = total > 0 ? Math.round(stat.amount / total * 100) : 0;
      rows += `<tr>` +
        `<td class="cell">${this.escapeHtml(stat.name)}</td>` +
        `<td class="cell" align="right">¥ ${this.money(stat.amount)}</td>` +
        `<td class="cell muted" align="center">${stat.count} 笔</td>` +
        `<td class="cell muted" align="right">${percent}%</td>` +
        `</tr>`;
    });
    return `<div class="section">${title}</div><table width="100%" cellspacing="0" cellpadding="0">${rows}</table>`;
  }

  private wordItemRows(records: AccountPO[], withDate: boolean): string {
    let rows = '';
    records.forEach((record: AccountPO) => {
      const name = this.categoryName(record.type, record.accountType);
      const title = record.description || record.merchant || name;
      const sub = record.description && record.merchant ? record.merchant : '';
      const content = sub
        ? `${this.escapeHtml(title)} <span class="muted" style="font-size:9pt;">${this.escapeHtml(sub)}</span>`
        : this.escapeHtml(title);
      const amountClass = record.accountType === AccountType.EXPENSES ? 'exp' : 'inc';
      const time = withDate ? dayjs(this.recordTime(record)).format('MM-DD HH:mm') : this.timeText(record);
      const timeWidth = withDate ? '20%' : '12%';
      const contentWidth = withDate ? '46%' : '54%';
      rows += `<tr>` +
        `<td class="cell muted" width="${timeWidth}">${time}</td>` +
        `<td class="cell" width="16%">${this.escapeHtml(name)}</td>` +
        `<td class="cell" width="${contentWidth}">${content}</td>` +
        `<td class="cell ${amountClass}" align="right" width="18%" style="font-weight:bold;">${this.sign(record)}${this.money(record.amount)}</td>` +
        `</tr>`;
    });
    return rows;
  }

  private wordDetail(records: AccountPO[], count: number, groupByDay: boolean): string {
    if (records.length === 0) {
      return `<div class="section">收支明细</div>` +
        `<p class="muted" style="font-size:10pt;">该时间段暂无账单记录</p>`;
    }
    let rows = '';
    if (groupByDay) {
      const groups = this.buildDayGroups(records);
      groups.forEach((group: DayGroup) => {
        const date = dayjs(group.time);
        let head = `${date.format('M月D日')} · 周${this.weekday(group.time)}`;
        const parts: string[] = [];
        if (group.expenses > 0) {
          parts.push(`支出 ¥${this.money(group.expenses)}`);
        }
        if (group.income > 0) {
          parts.push(`收入 ¥${this.money(group.income)}`);
        }
        if (parts.length > 0) {
          head += `　${parts.join('　')}`;
        }
        rows += `<tr><td colspan="4" bgcolor="#F4F5F7" style="padding:5pt 8pt;font-size:10pt;font-weight:bold;">${head}</td></tr>`;
        rows += this.wordItemRows(group.records, false);
      });
    } else {
      rows = `<tr bgcolor="#F4F5F7">` +
        `<td class="headcell" width="20%">时间</td>` +
        `<td class="headcell" width="16%">分类</td>` +
        `<td class="headcell" width="46%">内容</td>` +
        `<td class="headcell" width="18%" align="right">金额</td></tr>`;
      rows += this.wordItemRows(this.flatRecords(records), true);
    }
    return `<div class="section">收支明细（${count} 笔）</div>` +
      `<table width="100%" cellspacing="0" cellpadding="0">${rows}</table>`;
  }

  private buildWordHtml(records: AccountPO[], startTime: number, endTime: number, options: ExportOptions): string {
    const summary = this.summarize(records);
    const range = `${dayjs(startTime).format('YYYY-MM-DD')} ~ ${dayjs(endTime).format('YYYY-MM-DD')}`;
    const generatedAt = dayjs().format('YYYY-MM-DD HH:mm');

    let body = '';
    body += this.wordHeader(range, summary.count);
    if (options.includeSummary) {
      body += this.wordSummary(summary);
    }
    if (options.includeCategory) {
      body += this.wordCategorySection('分类统计 · 支出',
        this.buildCategoryStats(records, AccountType.EXPENSES), summary.expenses);
      body += this.wordCategorySection('分类统计 · 收入',
        this.buildCategoryStats(records, AccountType.INCOME), summary.income);
    }
    if (options.includeDetail) {
      body += this.wordDetail(records, summary.count, options.groupByDay);
    }
    body += `<p class="foot">由「记账助手」生成于 ${generatedAt}</p>`;

    return `<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<title>账单明细</title>
<!--[if gte mso 9]><xml><w:WordDocument><w:View>Print</w:View><w:Zoom>100</w:Zoom></w:WordDocument></xml><![endif]-->
<style>
@page WordSection1 { size:595.3pt 841.9pt; margin:45pt 50pt 45pt 50pt; }
div.WordSection1 { page:WordSection1; }
body { font-family:"微软雅黑","Microsoft YaHei",sans-serif; font-size:10.5pt; color:#1F2329; }
p.foot { text-align:center; color:#999999; font-size:8pt; margin-top:16pt; }
div.section { font-size:12pt; font-weight:bold; margin:14pt 0 6pt; color:#333333; }
table { border-collapse:collapse; }
td { vertical-align:middle; }
td.cell { padding:5pt 8pt; border-bottom:0.75pt solid #EEEEEE; font-size:10.5pt; }
td.headcell { padding:5pt 8pt; font-size:9pt; color:#666666; }
.muted { color:#999999; }
.exp { color:${this.docTheme().danger}; }
.inc { color:${this.docTheme().success}; }
</style>
</head>
<body><div class="WordSection1">${body}</div></body>
</html>`;
  }

  /**
   * 生成自包含 HTML 账单文档
   * @param forWord true 为 Word 版式（.doc），false 为 Web 版式（PDF 打印）
   */
  buildHtml(records: AccountPO[], startTime: number, endTime: number, options: ExportOptions,
    forWord: boolean): string {
    return forWord
      ? this.buildWordHtml(records, startTime, endTime, options)
      : this.buildWebHtml(records, startTime, endTime, options);
  }

  // ==================== Word (.docx) 生成 ====================

  private xmlEscape(text: string): string {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&apos;');
  }

  // OOXML 文本运行（run）
  private wRun(text: string, opts?: WRunOptions): string {
    let props = '';
    if (opts) {
      if (opts.bold) {
        props += '<w:b/>';
      }
      if (opts.color) {
        props += `<w:color w:val="${opts.color}"/>`;
      }
      if (opts.sz !== undefined) {
        props += `<w:sz w:val="${opts.sz}"/><w:szCs w:val="${opts.sz}"/>`;
      }
    }
    const rPr = props ? `<w:rPr>${props}</w:rPr>` : '';
    return `<w:r>${rPr}<w:t xml:space="preserve">${this.xmlEscape(text)}</w:t></w:r>`;
  }

  // OOXML 段落
  private wPara(runs: string, opts?: WParaOptions): string {
    let props = '';
    if (opts) {
      if (opts.align) {
        props += `<w:jc w:val="${opts.align}"/>`;
      }
      if (opts.spacingAfter !== undefined) {
        props += `<w:spacing w:after="${opts.spacingAfter}"/>`;
      }
    }
    const pPr = props ? `<w:pPr>${props}</w:pPr>` : '';
    return `<w:p>${pPr}${runs}</w:p>`;
  }

  // OOXML 表格：rows 中每个 cell 为已构建的段落 XML 字符串
  private wTable(rows: string[][]): string {
    const colCount = rows.length > 0 ? rows[0].length : 0;
    const colWidth = colCount > 0 ? Math.floor(9026 / colCount) : 9026;
    let xml = '<w:tbl><w:tblPr><w:tblW w:w="9026" w:type="dxa"/><w:tblBorders>' +
      '<w:top w:val="single" w:sz="4" w:space="0" w:color="EEEEEE"/>' +
      '<w:left w:val="single" w:sz="4" w:space="0" w:color="EEEEEE"/>' +
      '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="EEEEEE"/>' +
      '<w:right w:val="single" w:sz="4" w:space="0" w:color="EEEEEE"/>' +
      '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="EEEEEE"/>' +
      '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="EEEEEE"/>' +
      '</w:tblBorders></w:tblPr>';
    xml += '<w:tblGrid>';
    for (let c = 0; c < colCount; c++) {
      xml += `<w:gridCol w:w="${colWidth}"/>`;
    }
    xml += '</w:tblGrid>';
    for (const row of rows) {
      xml += '<w:tr>';
      for (const cell of row) {
        xml += `<w:tc>${cell}</w:tc>`;
      }
      xml += '</w:tr>';
    }
    xml += '</w:tbl>';
    return xml;
  }

  private wSection(title: string): string {
    return this.wPara(this.wRun(title, { bold: true, sz: 24, color: '333333' }), { spacingAfter: 120 });
  }

  private wSummaryCell(label: string, value: string, color: string): string {
    return this.wPara(this.wRun(label, { sz: 16, color: '808080' }), { align: 'center', spacingAfter: 40 }) +
      this.wPara(this.wRun(value, { bold: true, sz: 26, color: color }), { align: 'center' });
  }

  private wSummaryTable(summary: BillSummary): string {
    const rows: string[][] = [[
      this.wSummaryCell('总支出', `¥ ${this.money(summary.expenses)}`, this.docHex(this.docTheme().danger)),
      this.wSummaryCell('总收入', `¥ ${this.money(summary.income)}`, this.docHex(this.docTheme().success)),
      this.wSummaryCell('结余', `¥ ${this.money(summary.balance)}`, '1F2329')
    ]];
    return this.wTable(rows);
  }

  private wCategoryTable(stats: CategoryStat[]): string {
    if (stats.length === 0) {
      return '';
    }
    const rows: string[][] = [];
    rows.push([
      this.wPara(this.wRun('分类', { bold: true, sz: 18, color: '666666' })),
      this.wPara(this.wRun('金额', { bold: true, sz: 18, color: '666666' }), { align: 'right' }),
      this.wPara(this.wRun('笔数', { bold: true, sz: 18, color: '666666' }), { align: 'center' }),
      this.wPara(this.wRun('占比', { bold: true, sz: 18, color: '666666' }), { align: 'right' })
    ]);
    let total = 0;
    for (const stat of stats) {
      total += stat.amount;
    }
    for (const stat of stats) {
      const percent = total > 0 ? Math.round(stat.amount / total * 100) : 0;
      rows.push([
        this.wPara(this.wRun(stat.name, { sz: 18 })),
        this.wPara(this.wRun(`¥ ${this.money(stat.amount)}`, { sz: 18 }), { align: 'right' }),
        this.wPara(this.wRun(`${stat.count} 笔`, { sz: 18, color: '808080' }), { align: 'center' }),
        this.wPara(this.wRun(`${percent}%`, { sz: 18, color: '808080' }), { align: 'right' })
      ]);
    }
    return this.wTable(rows);
  }

  private wDetailTable(records: AccountPO[]): string {
    if (records.length === 0) {
      return this.wPara(this.wRun('该时间段暂无账单记录', { color: '808080' }), { align: 'center' });
    }
    const rows: string[][] = [];
    rows.push([
      this.wPara(this.wRun('时间', { bold: true, sz: 18, color: '666666' }), { align: 'center' }),
      this.wPara(this.wRun('分类', { bold: true, sz: 18, color: '666666' }), { align: 'center' }),
      this.wPara(this.wRun('内容', { bold: true, sz: 18, color: '666666' })),
      this.wPara(this.wRun('金额', { bold: true, sz: 18, color: '666666' }), { align: 'right' })
    ]);
    const list = this.flatRecords(records);
    for (const record of list) {
      const name = this.categoryName(record.type, record.accountType);
      const title = record.description || record.merchant || name;
      const color = this.docHex(record.accountType === AccountType.EXPENSES ? this.docTheme().danger : this.docTheme().success);
      const amountText = this.sign(record) + this.money(record.amount);
      rows.push([
        this.wPara(this.wRun(dayjs(this.recordTime(record)).format('MM-DD HH:mm'), { sz: 18, color: '808080' }),
          { align: 'center' }),
        this.wPara(this.wRun(name, { sz: 18 }), { align: 'center' }),
        this.wPara(this.wRun(title, { sz: 18 })),
        this.wPara(this.wRun(amountText, { bold: true, sz: 18, color: color }), { align: 'right' })
      ]);
    }
    return this.wTable(rows);
  }

  private wSectPr(): string {
    return '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>' +
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>' +
      '</w:sectPr>';
  }

  /**
   * 生成 .docx（OOXML）账单文档二进制数据
   */
  buildDocx(records: AccountPO[], startTime: number, endTime: number, options: ExportOptions): Uint8Array {
    const summary = this.summarize(records);
    const range = `${dayjs(startTime).format('YYYY-MM-DD')} ~ ${dayjs(endTime).format('YYYY-MM-DD')}`;
    const generatedAt = dayjs().format('YYYY-MM-DD HH:mm');

    const body: string[] = [];
    body.push(this.wPara(this.wRun('记账助手 · 账单明细', { bold: true, sz: 36, color: this.docHex(this.docTheme().primary) }),
      { align: 'center', spacingAfter: 80 }));
    body.push(this.wPara(this.wRun(`${range} · 共 ${summary.count} 笔`, { sz: 20, color: '808080' }),
      { align: 'center', spacingAfter: 200 }));

    if (options.includeSummary) {
      body.push(this.wSummaryTable(summary));
    }
    if (options.includeCategory) {
      const expStats = this.buildCategoryStats(records, AccountType.EXPENSES);
      const incStats = this.buildCategoryStats(records, AccountType.INCOME);
      if (expStats.length > 0) {
        body.push(this.wSection('分类统计 · 支出'));
        body.push(this.wCategoryTable(expStats));
      }
      if (incStats.length > 0) {
        body.push(this.wSection('分类统计 · 收入'));
        body.push(this.wCategoryTable(incStats));
      }
    }
    if (options.includeDetail) {
      body.push(this.wSection(`收支明细（${summary.count} 笔）`));
      body.push(this.wDetailTable(records));
    }
    body.push(this.wPara(this.wRun(`由「记账助手」生成于 ${generatedAt}`, { sz: 16, color: '999999' }),
      { align: 'center', spacingAfter: 0 }));

    const documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' +
      '<w:body>' + body.join('') + this.wSectPr() + '</w:body></w:document>';

    const contentTypesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
      '<Default Extension="xml" ContentType="application/xml"/>' +
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
      '</Types>';

    const relsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>' +
      '</Relationships>';

    const encoder = new util.TextEncoder();
    const entries: ZipEntry[] = [
      { name: '[Content_Types].xml', data: encoder.encode(contentTypesXml) },
      { name: '_rels/.rels', data: encoder.encode(relsXml) },
      { name: 'word/document.xml', data: encoder.encode(documentXml) }
    ];
    return this.zipStored(entries);
  }

  // ==================== ZIP（stored，无压缩）====================

  private crc32(data: Uint8Array): number {
    let crc = 0xFFFFFFFF;
    for (let i = 0; i < data.length; i++) {
      crc = crc ^ data[i];
      for (let j = 0; j < 8; j++) {
        if ((crc & 1) !== 0) {
          crc = (crc >>> 1) ^ 0xEDB88320;
        } else {
          crc = crc >>> 1;
        }
      }
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  private setU16(out: Uint8Array, pos: number, value: number): void {
    out[pos] = value & 0xFF;
    out[pos + 1] = (value >>> 8) & 0xFF;
  }

  private setU32(out: Uint8Array, pos: number, value: number): void {
    out[pos] = value & 0xFF;
    out[pos + 1] = (value >>> 8) & 0xFF;
    out[pos + 2] = (value >>> 16) & 0xFF;
    out[pos + 3] = (value >>> 24) & 0xFF;
  }

  private zipStored(entries: ZipEntry[]): Uint8Array {
    const encoder = new util.TextEncoder();
    const nameBytes: Uint8Array[] = [];
    let total = 0;
    for (let i = 0; i < entries.length; i++) {
      const nb = encoder.encode(entries[i].name);
      nameBytes.push(nb);
      total += 30 + nb.length + entries[i].data.length + 46 + nb.length;
    }
    total += 22;

    const out = new Uint8Array(total);
    let pos = 0;
    const offsets: number[] = [];

    for (let i = 0; i < entries.length; i++) {
      offsets.push(pos);
      const nb = nameBytes[i];
      const data = entries[i].data;
      const crc = this.crc32(data);
      this.setU32(out, pos, 0x04034b50); pos += 4;
      this.setU16(out, pos, 20); pos += 2;
      this.setU16(out, pos, 0); pos += 2;
      this.setU16(out, pos, 0); pos += 2;
      this.setU16(out, pos, 0); pos += 2;
      this.setU16(out, pos, 0); pos += 2;
      this.setU32(out, pos, crc); pos += 4;
      this.setU32(out, pos, data.length); pos += 4;
      this.setU32(out, pos, data.length); pos += 4;
      this.setU16(out, pos, nb.length); pos += 2;
      this.setU16(out, pos, 0); pos += 2;
      out.set(nb, pos); pos += nb.length;
      out.set(data, pos); pos += data.length;
    }

    const centralOffset = pos;
    for (let i = 0; i < entries.length; i++) {
      const nb = nameBytes[i];
      const data = entries[i].data;
      const crc = this.crc32(data);
      this.setU32(out, pos, 0x02014b50); pos += 4;
      this.setU16(out, pos, 20); pos += 2;
      this.setU16(out, pos, 20); pos += 2;
      this.setU16(out, pos, 0); pos += 2;
      this.setU16(out, pos, 0); pos += 2;
      this.setU16(out, pos, 0); pos += 2;
      this.setU16(out, pos, 0); pos += 2;
      this.setU32(out, pos, crc); pos += 4;
      this.setU32(out, pos, data.length); pos += 4;
      this.setU32(out, pos, data.length); pos += 4;
      this.setU16(out, pos, nb.length); pos += 2;
      this.setU16(out, pos, 0); pos += 2;
      this.setU16(out, pos, 0); pos += 2;
      this.setU16(out, pos, 0); pos += 2;
      this.setU16(out, pos, 0); pos += 2;
      this.setU32(out, pos, 0); pos += 4;
      this.setU32(out, pos, offsets[i]); pos += 4;
      out.set(nb, pos); pos += nb.length;
    }

    const centralSize = pos - centralOffset;
    this.setU32(out, pos, 0x06054b50); pos += 4;
    this.setU16(out, pos, 0); pos += 2;
    this.setU16(out, pos, 0); pos += 2;
    this.setU16(out, pos, entries.length); pos += 2;
    this.setU16(out, pos, entries.length); pos += 2;
    this.setU32(out, pos, centralSize); pos += 4;
    this.setU32(out, pos, centralOffset); pos += 4;
    this.setU16(out, pos, 0); pos += 2;

    return out;
  }
}

export default new BillExportService();
