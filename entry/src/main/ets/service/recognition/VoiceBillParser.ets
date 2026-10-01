import dayjs from 'dayjs';
import { AccountType } from '../../models/account/account';
import CategoryRegistry from '../../models/accountType/CategoryRegistry';

export interface ParsedVoiceBill {
  amount: number;
  accountType: AccountType;
  categoryId: number;
  merchant: string;
  time: number;
}

interface KeywordRule {
  keyword: string;
  categoryName: string;
}

/**
 * 语音记账本地解析：从识别文本中提取金额、收支类型、分类与商家
 */
export class VoiceBillParser {
  private static readonly EXPENSE_RULES: KeywordRule[] = [
    { keyword: '早餐', categoryName: '早午晚餐' },
    { keyword: '午餐', categoryName: '早午晚餐' },
    { keyword: '晚饭', categoryName: '早午晚餐' },
    { keyword: '面包', categoryName: '早午晚餐' },
    { keyword: '吃饭', categoryName: '早午晚餐' },
    { keyword: '外卖', categoryName: '早午晚餐' },
    { keyword: '奶茶', categoryName: '零食烟酒' },
    { keyword: '咖啡', categoryName: '零食烟酒' },
    { keyword: '打车', categoryName: '交通运输' },
    { keyword: '地铁', categoryName: '交通运输' },
    { keyword: '公交', categoryName: '交通运输' },
    { keyword: '加油', categoryName: '交通运输' },
    { keyword: '房租', categoryName: '住房' },
    { keyword: '电影', categoryName: '娱乐' },
    { keyword: '药', categoryName: '医疗' },
    { keyword: '医院', categoryName: '医疗' },
    { keyword: '话费', categoryName: '通讯' },
    { keyword: '书', categoryName: '学习' },
    { keyword: '购物', categoryName: '购物' }
  ];

  private static readonly INCOME_RULES: KeywordRule[] = [
    { keyword: '工资', categoryName: '工资' },
    { keyword: '奖金', categoryName: '奖金' },
    { keyword: '利息', categoryName: '利息' },
    { keyword: '兼职', categoryName: '兼职' },
    { keyword: '红包', categoryName: '红包转账' },
    { keyword: '转账', categoryName: '红包转账' },
    { keyword: '借入', categoryName: '借入' }
  ];

  static parse(text: string): ParsedVoiceBill | null {
    const trimmed = text.trim();
    if (!trimmed) {
      return null;
    }
    const amount = VoiceBillParser.extractAmount(trimmed);
    if (!(amount > 0)) {
      return null;
    }
    const accountType = VoiceBillParser.detectAccountType(trimmed);
    const merchant = VoiceBillParser.extractMerchant(trimmed);
    const categoryId = VoiceBillParser.matchCategory(trimmed, accountType);
    const time = VoiceBillParser.resolveTime(trimmed);
    return {
      amount: amount,
      accountType: accountType,
      categoryId: categoryId,
      merchant: merchant,
      time: time
    };
  }

  // 从文本解析日期与时间：支持 今天/昨天/前天/明天、X月X日、X点/X时X分
  static resolveTime(text: string): number {
    const now = dayjs();
    let base = now.startOf('day');
    if (text.includes('前天')) {
      base = now.subtract(2, 'day').startOf('day');
    } else if (text.includes('昨天')) {
      base = now.subtract(1, 'day').startOf('day');
    } else if (text.includes('明天')) {
      base = now.add(1, 'day').startOf('day');
    } else if (!text.includes('今天')) {
      const dateRegex = /(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]/;
      const dm = text.match(dateRegex);
      if (dm && dm.length > 2) {
        const month = parseInt(dm[1]);
        const day = parseInt(dm[2]);
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          base = now.month(month - 1).date(day).startOf('day');
        }
      }
    }
    const hourRegex = /(\d{1,2})\s*[点时]/;
    const hm = text.match(hourRegex);
    if (hm && hm.length > 1) {
      let hour = parseInt(hm[1]);
      if (hour < 0 || hour > 23) {
        hour = 0;
      }
      let minute = 0;
      const minuteRegex = /[点时](\d{1,2})\s*分/;
      const mm = text.match(minuteRegex);
      if (mm && mm.length > 1) {
        minute = parseInt(mm[1]);
        if (minute < 0 || minute > 59) {
          minute = 0;
        }
      }
      return base.hour(hour).minute(minute).second(0).millisecond(0).valueOf();
    }
    return base.valueOf();
  }

  // 一句话多笔：按标点/“和”拆分后逐段解析，例如“早餐10元，午餐20元”
  static parseMultiple(text: string): ParsedVoiceBill[] {
    const trimmed = text.trim();
    const result: ParsedVoiceBill[] = [];
    if (!trimmed) {
      return result;
    }
    const parts = trimmed.split(/[，。；;、\n和]+/);
    for (const raw of parts) {
      const part = raw.trim();
      if (!part) {
        continue;
      }
      const parsed = VoiceBillParser.parse(part);
      if (parsed) {
        result.push(parsed);
      }
    }
    if (result.length === 0) {
      const single = VoiceBillParser.parse(trimmed);
      if (single) {
        result.push(single);
      }
    }
    return result;
  }

  private static extractAmount(text: string): number {
    // 1. 阿拉伯数字 + 单位
    const regex = /(\d+(?:\.\d{1,2})?)\s*(?:块钱|元|块)/;
    const m = text.match(regex);
    if (m && m.length > 1) {
      return parseFloat(m[1]);
    }
    // 2. 中文数字 + 块/块钱
    const blockRegex = /([零一二三四五六七八九十两]+)\s*块/;
    const bm = text.match(blockRegex);
    if (bm && bm.length > 1) {
      const base = VoiceBillParser.chineseToNumber(bm[1]);
      if (base > 0) {
        // 处理“X块Y”（Y 为角）
        const jiaoRegex = /块(?:钱)?([零一二三四五六七八九十两])/;
        const jm = text.match(jiaoRegex);
        if (jm && jm.length > 1) {
          const jiao = VoiceBillParser.chineseToNumber(jm[1]);
          if (jiao > 0 && jiao < 10) {
            return base + jiao * 0.1;
          }
        }
        return base;
      }
    }
    // 3. 中文数字 + 元
    const yuanRegex = /([零一二三四五六七八九十两]+)\s*元/;
    const ym = text.match(yuanRegex);
    if (ym && ym.length > 1) {
      const value = VoiceBillParser.chineseToNumber(ym[1]);
      if (value > 0) {
        return value;
      }
    }
    // 4. 兜底：第一个阿拉伯数字
    const numRegex = /(\d+(?:\.\d{1,2})?)/;
    const n = text.match(numRegex);
    if (n && n.length > 1) {
      return parseFloat(n[1]);
    }
    return 0;
  }

  // 中文数字转阿拉伯（支持个/十/百/千，含“两”），无法解析返回 -1
  private static chineseToNumber(chinese: string): number {
    if (chinese.length === 0) {
      return -1;
    }
    if (chinese.length === 1) {
      const single = VoiceBillParser.simpleChineseDigit(chinese);
      if (single >= 0) {
        return single;
      }
    }
    let total = 0;
    let current = 0;
    let hasUnit = false;
    for (let i = 0; i < chinese.length; i++) {
      const ch = chinese.charAt(i);
      const digit = VoiceBillParser.simpleChineseDigit(ch);
      if (digit >= 0) {
        current = digit;
        continue;
      }
      const unit = VoiceBillParser.chineseUnit(ch);
      if (unit > 0) {
        if (current === 0) {
          current = 1;
        }
        total += current * unit;
        current = 0;
        hasUnit = true;
      }
    }
    total += current;
    return hasUnit || total > 0 ? total : -1;
  }

  private static simpleChineseDigit(ch: string): number {
    switch (ch) {
      case '零':
        return 0;
      case '一':
        return 1;
      case '二':
        return 2;
      case '两':
        return 2;
      case '三':
        return 3;
      case '四':
        return 4;
      case '五':
        return 5;
      case '六':
        return 6;
      case '七':
        return 7;
      case '八':
        return 8;
      case '九':
        return 9;
      default:
        return -1;
    }
  }

  private static chineseUnit(ch: string): number {
    switch (ch) {
      case '十':
        return 10;
      case '百':
        return 100;
      case '千':
        return 1000;
      default:
        return 0;
    }
  }

  private static detectAccountType(text: string): AccountType {
    const incomeWords: string[] = ['工资', '奖金', '利息', '兼职', '红包', '转账', '借入', '收入', '到账', '赚'];
    for (const word of incomeWords) {
      if (text.includes(word)) {
        return AccountType.INCOME;
      }
    }
    return AccountType.EXPENSES;
  }

  private static extractMerchant(text: string): string {
    let s = text.replace(/\d+(?:\.\d{1,2})?\s*(?:块钱|元|块)/g, '');
    s = s.replace(/[零一二三四五六七八九十两]+\s*(?:块钱|元|块)/g, '');
    s = s.replace(/花了|买了|付了|消费了|用了|记账|记一笔|买|花|付|消费|记/g, '');
    s = s.replace(/[，。、！？：；,.!?:;、\s]+/g, '');
    return s.trim();
  }

  private static matchCategory(text: string, accountType: AccountType): number {
    const rules = accountType === AccountType.EXPENSES ? VoiceBillParser.EXPENSE_RULES : VoiceBillParser.INCOME_RULES;
    for (const rule of rules) {
      if (text.includes(rule.keyword)) {
        const model = CategoryRegistry.getByName(rule.categoryName, accountType);
        if (model) {
          return model.id;
        }
      }
    }
    const names = CategoryRegistry.listNames(accountType);
    for (const name of names) {
      if (text.includes(name)) {
        const model = CategoryRegistry.getByName(name, accountType);
        if (model) {
          return model.id;
        }
      }
    }
    const otherName = accountType === AccountType.EXPENSES ? '其他支出' : '其他收入';
    const otherModel = CategoryRegistry.getByName(otherName, accountType);
    return otherModel ? otherModel.id : 0;
  }
}
