import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import { BusinessError } from '@ohos.base';
import dayjs from 'dayjs';
import { textRecognition } from '@kit.CoreVisionKit';
import { AccountType } from '../../models/account/account';
import { RecognitionResult } from '../../models/recognition/RecognitionResult';
import { OcrTextBlock, OcrVisionResult } from '../../models/recognition/OcrSample';
import { Recognizer } from './Recognizer';
import { Logger } from '../../utils/Logger';

// 端侧文字识别的系统能力
const OCR_SYSCAP: string = 'SystemCapability.AI.OCR.TextRecognition';
// 纯 OCR 无语义理解，置信度给中等值
const OCR_CONFIDENCE: number = 0.6;
// 单次 OCR 任务看门狗超时（毫秒）：底层 OCR/图片服务静默挂起时按超时失败，
// 避免当前任务永久卡死、全局串行队列被堵死导致后续任务（含重试）全部无响应
const OCR_TIMEOUT_MS: number = 30000;

// OCR 原始结果 + 图片像素尺寸（供相对坐标换算）
interface OcrRaw {
  width: number;
  height: number;
  result: textRecognition.TextRecognitionResult;
}

// OCR 引擎串行队列：textRecognition 的 init/release 是全局操作，
// 并发识别时必须排队，避免一个协程 release 掉另一个还在用的引擎
let ocrQueue: Promise<void> = Promise.resolve();

/**
 * 端侧 OCR 识别器：Core Vision Kit 通用文字识别
 * 只提取文本，金额/商家/时间用本地规则解析，分类留空交给流水线智能分类
 * 注意：init/release 起始 API 12，本项目 compatibleSdkVersion 为 12，需先 init 加载模型
 */
export class LocalOcrRecognizer implements Recognizer {
  async recognize(imageUri: string): Promise<RecognitionResult[]> {
    const raw = await this.runOcr(imageUri);
    return this.parse(raw.result.value);
  }

  // 阶段1：返回带相对坐标的文本块 + 图片尺寸，供训练数据采集使用
  async recognizeBlocks(imageUri: string): Promise<OcrVisionResult> {
    const raw = await this.runOcr(imageUri);
    return this.toVisionResult(raw);
  }

  // OCR 核心：init -> 解码 -> recognizeText，返回 {宽,高,原始结果}，统一负责 release。
  // 外层包看门狗：底层静默卡死时按超时抛错，当前任务可见失败、ocrQueue 继续消化
  // 后续任务（其他图片、重试、训练样本采集），而不是整个识别流程永久挂起。
  // 注：超时后底层任务可能仍在后台持引擎，后续任务的 init/release 与其交错属降级路径，
  // 相比整条队列永久死锁是更小的代价
  private runOcr(imageUri: string): Promise<OcrRaw> {
    const job: Promise<OcrRaw> = ocrQueue.then((): Promise<OcrRaw> => this.doRunOcrWithWatchdog(imageUri));
    ocrQueue = job.then((): void => {
    }, (): void => {
    });
    return job;
  }

  // 看门狗包装：限定单次 OCR 任务的最长执行时间，超时抛与 OCR 失败相同的可读错误
  private doRunOcrWithWatchdog(imageUri: string): Promise<OcrRaw> {
    return new Promise<OcrRaw>((resolve: (value: OcrRaw) => void, reject: (reason: Error) => void) => {
      const timer: number = setTimeout((): void => {
        Logger.error('端侧 OCR 看门狗超时(ms): ', OCR_TIMEOUT_MS);
        reject(new Error(getContext().resourceManager.getStringSync($r('app.string.ocr_failed'))));
      }, OCR_TIMEOUT_MS);
      this.doRunOcr(imageUri).then((value: OcrRaw): void => {
        clearTimeout(timer);
        resolve(value);
      }, (error: Error): void => {
        clearTimeout(timer);
        reject(error);
      });
    });
  }

  private async doRunOcr(imageUri: string): Promise<OcrRaw> {
    if (!canIUse(OCR_SYSCAP)) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.ocr_unsupported')));
    }
    let file: fs.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let inited = false;
    try {
      await textRecognition.init();
      inited = true;
      file = fs.openSync(imageUri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const options: image.DecodingOptions = {
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      };
      const pixelMap = await source.createPixelMap(options);
      try {
        const info = await pixelMap.getImageInfo();
        const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
        const result = await textRecognition.recognizeText(visionInfo);
        return { width: info.size.width, height: info.size.height, result: result };
      } finally {
        pixelMap.release();
      }
    } catch (error) {
      const e = error as BusinessError;
      Logger.error('端侧 OCR 识别失败', String(e.code), e.message);
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.ocr_failed')));
    } finally {
      if (source) {
        try {
          await source.release();
        } catch (err) {
          Logger.warn('ImageSource释放失败', (err as Error).message);
        }
      }
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

  // 把原始结果映射为「文本行 -> 相对坐标块」；行外框四点取 min/max 得矩形，再除以宽高
  private toVisionResult(raw: OcrRaw): OcrVisionResult {
    const blocks: OcrTextBlock[] = [];
    for (const block of raw.result.blocks) {
      for (const line of block.lines) {
        const lineText = line.value;
        if (!lineText || lineText.trim().length === 0) {
          continue;
        }
        const pts = line.cornerPoints;
        if (!pts || pts.length === 0) {
          continue;
        }
        let left = pts[0].x;
        let top = pts[0].y;
        let right = pts[0].x;
        let bottom = pts[0].y;
        for (const p of pts) {
          if (p.x < left) {
            left = p.x;
          }
          if (p.y < top) {
            top = p.y;
          }
          if (p.x > right) {
            right = p.x;
          }
          if (p.y > bottom) {
            bottom = p.y;
          }
        }
        blocks.push({
          text: lineText,
          left: this.clamp01(left / raw.width),
          top: this.clamp01(top / raw.height),
          right: this.clamp01(right / raw.width),
          bottom: this.clamp01(bottom / raw.height)
        });
      }
    }
    return { width: raw.width, height: raw.height, blocks: blocks };
  }

  // 相对坐标 clamp 到 [0,1]：OCR 检测框紧贴边缘时 cornerPoints 可能略越界
  private clamp01(value: number): number {
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
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
      isBill: true,
      engine: 'ocr_rule'
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
