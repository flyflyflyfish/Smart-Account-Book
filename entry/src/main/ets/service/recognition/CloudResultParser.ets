import dayjs from 'dayjs';
import { AccountType } from '../../models/account/account';
import { RecognitionResult } from '../../models/recognition/RecognitionResult';
import { LlmBillRaw } from '../../models/recognition/CloudLlmModels';
import CategoryStore from '../../models/accountType/CategoryStore';

// 云端返回内容无法解析为账单数组时的错误标记，由调用方转成资源字符串
const BAD_RESULT_ERROR: string = 'cloud_bad_result';

/**
 * 云端识别结果解析器：把模型输出的文本解析为结构化识别结果
 * 纯逻辑，不依赖资源上下文与系统 Kit，便于单元测试
 */
export class CloudResultParser {
  // 模型可能包裹 markdown 代码块或在 JSON 前后输出多余文字，先清理再解析为数组
  parseResult(content: string): RecognitionResult[] {
    let cleaned = content.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replace(/^```[a-zA-Z]*\s*/, '').replace(/```\s*$/, '').trim();
    }
    const start = cleaned.indexOf('[');
    const end = cleaned.lastIndexOf(']');
    if (start < 0 || end <= start) {
      throw new Error(BAD_RESULT_ERROR);
    }
    let rawList: LlmBillRaw[];
    try {
      rawList = JSON.parse(cleaned.substring(start, end + 1)) as LlmBillRaw[];
    } catch (error) {
      throw new Error(BAD_RESULT_ERROR);
    }
    if (!Array.isArray(rawList)) {
      throw new Error(BAD_RESULT_ERROR);
    }
    const results: RecognitionResult[] = [];
    for (const raw of rawList) {
      results.push(this.parseItem(raw));
    }
    return results;
  }

  // 单笔映射：金额与时间非法时回退默认值，交确认页兜底
  parseItem(raw: LlmBillRaw): RecognitionResult {
    const accountType = raw.accountType === '收入' ? AccountType.INCOME : AccountType.EXPENSES;
    const amount = typeof raw.amount === 'number' && raw.amount > 0 ? raw.amount : 0;
    const merchant = typeof raw.merchant === 'string' ? raw.merchant : '';
    const categoryName = this.normalizeCategory(typeof raw.category === 'string' ? raw.category : '', accountType);
    const payTime = this.parsePayTime(typeof raw.payTime === 'string' ? raw.payTime : '');
    const result: RecognitionResult = {
      accountType: accountType,
      amount: amount,
      merchant: merchant,
      payTime: payTime,
      categoryName: categoryName,
      confidence: 1,
      isBill: true
    };
    return result;
  }

  // 分类名不在当前可选列表时回退为该收支侧的“其他”
  normalizeCategory(name: string, accountType: AccountType): string {
    const names = CategoryStore.listNames(accountType);
    if (names.indexOf(name) >= 0) {
      return name;
    }
    return CategoryStore.otherName(accountType);
  }

  // 时间缺失或格式非法时用当前时间兜底
  parsePayTime(text: string): number {
    if (text) {
      const parsed = dayjs(text);
      if (parsed.isValid()) {
        return parsed.valueOf();
      }
    }
    return Date.now();
  }
}
