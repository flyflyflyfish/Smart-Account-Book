import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { BusinessError } from '@ohos.base';
import dayjs from 'dayjs';
import { textRecognition } from '@kit.CoreVisionKit';
import { AccountType } from '../../models/account/account';
import { RecognitionResult } from '../../models/recognition/RecognitionResult';
import { Recognizer } from './Recognizer';
import { Logger } from '../../utils/Logger';

// 端侧文字识别的系统能力
const OCR_SYSCAP: string = 'SystemCapability.AI.OCR.TextRecognition';
// 纯 OCR 无语义理解，置信度给中等值
const OCR_CONFIDENCE: number = 0.6;

/**
 * 端侧 OCR 识别器：Core Vision Kit 通用文字识别
 * 只提取文本，金额/商家/时间用本地规则解析，分类留空交给流水线智能分类
 * 注意：init/release 起始 API 12，本项目 compatibleSdkVersion 为 12，需先 init 加载模型
 */
export class LocalOcrRecognizer implements Recognizer {
  async recognize(imageUri: string): Promise<RecognitionResult[]> {
    if (!canIUse(OCR_SYSCAP)) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.ocr_unsupported')));
    }
    let file: fs.File | undefined = undefined;
    let inited = false;
    try {
      await textRecognition.init();
      inited = true;
      file = fs.openSync(imageUri, fs.OpenMode.READ_ONLY);
      const source = image.createImageSource(file.fd);
      const options: image.DecodingOptions = {
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      };
      const pixelMap = await source.createPixelMap(options);
      try {
        const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
        const result = await textRecognition.recognizeText(visionInfo);
        return this.parse(result.value);
      } finally {
        pixelMap.release();
      }
    } catch (error) {
      const e = error as BusinessError;
      Logger.error('端侧 OCR 识别失败', String(e.code), e.message);
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.ocr_failed')));
    } finally {
      if (file) {
        fs.closeSync(file);
      }
      if (inited) {
        try {
          await textRecognition.release();
        } catch (err) {
          Logger.error('端侧 OCR 释放失败', (err as Error).message);
        }
      }
    }
  }

  // 从纯文本解析单笔账单：金额/商家/时间用正则提取，分类留空交给流水线
  private parse(text: string): RecognitionResult[] {
    const lines = text.split('\n').filter((line: string): boolean => line.trim().length > 0);
    const amount = this.extractAmount(text);
    if (!(amount > 0)) {
      return [];
    }
    const result: RecognitionResult = {
      accountType: AccountType.EXPENSES,
      amount: amount,
      merchant: this.extractMerchant(lines),
      payTime: this.extractPayTime(text),
      categoryName: '',
      confidence: OCR_CONFIDENCE,
      isBill: true
    };
    return [result];
  }

  // 金额：优先合计/总计，其次 ¥/￥ 前缀，再次 X元 后缀
  private extractAmount(text: string): number {
    const patterns: RegExp[] = [
      /(?:合计|总计|总金额)[：:]\s*[¥￥]?\s*(\d+(?:\.\d{1,2})?)/,
      /[¥￥]\s*(\d+(?:\.\d{1,2})?)/,
      /(\d+(?:\.\d{1,2})?)\s*元/
    ];
    for (const pattern of patterns) {
      const match = pattern.exec(text);
      if (match) {
        const value = parseFloat(match[1]);
        if (value > 0) {
          return value;
        }
      }
    }
    return 0;
  }

  // 商家：取首个不含金额/日期、长度合理的行
  private extractMerchant(lines: string[]): string {
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.length > 20) {
        continue;
      }
      if (/[¥￥]/.test(trimmed) || /元/.test(trimmed) || /\d{4}[年\-\/]/.test(trimmed)) {
        continue;
      }
      return trimmed;
    }
    return '';
  }

  // 时间：匹配“YYYY年MM月DD日 HH:mm/HH时mm分”，时分缺失时退回仅日期，均无则用当前时间
  private extractPayTime(text: string): number {
    const pattern = /(\d{4})[年\-\/.](\d{1,2})[月\-\/.](\d{1,2})日?(?:\s*(\d{1,2})[时:：](\d{1,2})分?)?/;
    const match = pattern.exec(text);
    if (match) {
      const dateText = `${match[1]}-${match[2]}-${match[3]}`;
      if (match[4] !== undefined && match[5] !== undefined) {
        const withTime = dayjs(`${dateText} ${match[4]}:${match[5]}`);
        if (withTime.isValid()) {
          return withTime.valueOf();
        }
      }
      const parsed = dayjs(dateText);
      if (parsed.isValid()) {
        return parsed.valueOf();
      }
    }
    return Date.now();
  }
}
