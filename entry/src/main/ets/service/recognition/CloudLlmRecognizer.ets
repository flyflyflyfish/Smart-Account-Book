import { rcp } from '@kit.RemoteCommunicationKit';
import { BusinessError } from '@ohos.base';
import dayjs from 'dayjs';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { AccountType } from '../../models/account/account';
import { RecognitionResult } from '../../models/recognition/RecognitionResult';
import {
  ChatCompletionResponse,
  ChatContent,
  ChatContentImageUrl,
  ChatMessage,
  ChatRequest,
  CloudLlmConfig
} from '../../models/recognition/CloudLlmModels';
import CategoryRegistry from '../../models/accountType/CategoryRegistry';
import { Recognizer } from './Recognizer';
import { NonRetryableError } from './NonRetryableError';
import { CloudResultParser } from './CloudResultParser';
import { Logger } from '../../utils/Logger';

// 图片最长边限制：缩小到 1024 显著减小 base64 体积，加快上传与推理
const MAX_IMAGE_EDGE: number = 1024;
// JPEG 压缩质量：降到 70 进一步减小体积，账单文字仍可辨
const JPEG_QUALITY: number = 70;
// 云端请求超时时间（连接与传输共用）
const HTTP_TIMEOUT_MS: number = 45000;
// curl 透传的超时错误码
const HTTP_ERROR_TIMEOUT: number = 2300028;
// 看门狗超时的错误标记：底层静默卡死时 Promise.race 抛出
const WATCHDOG_TIMEOUT: string = 'cloud_watchdog_timeout';
// 看门狗比底层超时放宽的余量（毫秒）
const WATCHDOG_EXTRA_MS: number = 5000;
// 图片解码超时的错误标记
const DECODE_TIMEOUT_MARK: string = 'image_decode_timeout';
// 单张图片解码（含转码）最长等待
const DECODE_TIMEOUT_MS: number = 40000;
// 排队等待解码锁的最长时间：超时后放行并发，防止持锁卡死拖住整个队列
const DECODE_LOCK_WAIT_MS: number = 30000;

// 图片解码互斥锁：大图全量解码极耗内存，串行执行降低图片服务压力；
// 持锁方由外层超时兜底释放，等待方超时后降级为并发执行，任何情况下不会死锁
class DecodeLock {  private busy: boolean = false;
  private waiters: Array<() => void> = [];

  acquire(waitMs: number): Promise<boolean> {
    if (!this.busy) {
      this.busy = true;
      return Promise.resolve(true);
    }
    return new Promise<boolean>((resolve: (locked: boolean) => void) => {
      let timer: number = -1;
      const notify: () => void = (): void => {
        clearTimeout(timer);
        resolve(true);
      };
      timer = setTimeout((): void => {
        const index = this.waiters.indexOf(notify);
        if (index >= 0) {
          this.waiters.splice(index, 1);
        }
        resolve(false);
      }, waitMs);
      this.waiters.push(notify);
    });
  }

  release(): void {
    const next = this.waiters.shift();
    if (next) {
      next();
      return;
    }
    this.busy = false;
  }
}

const decodeLock: DecodeLock = new DecodeLock();

// 云端 4xx 错误响应体结构：{"error":{"code":"...","message":"..."}}
interface CloudErrorDetail {
  code?: string;
  message?: string;
}

interface CloudErrorResponse {
  error?: CloudErrorDetail;
}

/**
 * 云端识别器：适配器模式封装 OpenAI 兼容的多模态大模型 API
 * 流程：图片压缩转码 -> 组装请求 -> 调云端接口 -> 清理并校验 JSON 数组 -> 映射为多笔识别结果
 */
export class CloudLlmRecognizer implements Recognizer {
  // 会话级熔断：该模型已被云端判定不支持图片输入，同模型后续识别直接短路，
  // 不再发注定 400 的请求（省流量省 token）；换模型或重启应用后自动恢复探测
  private static visionBrokenModel: string = '';
  private static visionBrokenMessage: string = '';

  private config: CloudLlmConfig;
  private parser: CloudResultParser = new CloudResultParser();

  constructor(config: CloudLlmConfig) {
    this.config = config;
  }

  async recognize(imageUri: string): Promise<RecognitionResult[]> {
    if (!this.config.baseUrl || !this.config.apiKey || !this.config.model) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_config_incomplete')));
    }
    if (CloudLlmRecognizer.visionBrokenModel !== '' &&
      CloudLlmRecognizer.visionBrokenModel === this.config.model) {
      Logger.warn('云端模型已熔断（不支持图片输入），跳过请求直接回退: ', this.config.model);
      throw new NonRetryableError(CloudLlmRecognizer.visionBrokenMessage);
    }
    const base64 = await this.decodeWithGuard(imageUri);
    const textPart: ChatContent = { type: 'text', text: this.buildPrompt() };
    const imageUrl: ChatContentImageUrl = { url: `data:image/jpeg;base64,${base64}` };
    const imagePart: ChatContent = { type: 'image_url', image_url: imageUrl };
    const message: ChatMessage = { role: 'user', content: [textPart, imagePart] };
    const content = await this.postChat([message]);
    try {
      return this.parser.parseResult(content);
    } catch (error) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_bad_result')));
    }
  }

  // 连通性测试：发一条纯文本消息，验证地址、Key 与模型可用，返回模型回复文本
  async testConnection(): Promise<string> {
    if (!this.config.baseUrl || !this.config.apiKey || !this.config.model) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_config_incomplete')));
    }
    const textPart: ChatContent = { type: 'text', text: '你好，这是一次连通性测试，请回复 ok' };
    const message: ChatMessage = { role: 'user', content: [textPart] };
    return this.postChat([message]);
  }

  // 文本对话：复用同一 OpenAI 兼容接口，供 AI 助手聊天使用
  async chat(messages: ChatMessage[]): Promise<string> {
    if (!this.config.baseUrl || !this.config.apiKey || !this.config.model) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_config_incomplete')));
    }
    return this.postChat(messages);
  }

  // 解码总入口：串行排队 + 超时兜底，图片服务卡死时任务会失败而不是永久挂起
  private async decodeWithGuard(uri: string): Promise<string> {
    const locked = await decodeLock.acquire(DECODE_LOCK_WAIT_MS);
    if (!locked) {
      Logger.warn('图片解码排队超时，降级为并发执行');
    }
    try {
      return await this.withTimeout(this.imageToBase64(uri), DECODE_TIMEOUT_MS);
    } catch (error) {
      const err = error as Error;
      if (err.message === DECODE_TIMEOUT_MARK) {
        Logger.error('图片解码超时(ms): ', DECODE_TIMEOUT_MS);
        throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_image_failed')));
      }
      throw new Error(err.message);
    } finally {
      if (locked) {
        decodeLock.release();
      }
    }
  }

  // 给异步工作包一层超时：底层若永不返回，也保证 Promise 在限定时间内结算
  private withTimeout(work: Promise<string>, timeoutMs: number): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void, reject: (reason: Error) => void) => {
      const timer: number = setTimeout((): void => {
        reject(new Error(DECODE_TIMEOUT_MARK));
      }, timeoutMs);
      work.then((value: string): void => {
        clearTimeout(timer);
        resolve(value);
      }, (error: Error): void => {
        clearTimeout(timer);
        reject(error);
      });
    });
  }

  // 读取图片 -> 按目标尺寸直接解码（大图避免全量解码撑爆内存）-> 打包为 JPEG -> Base64
  private async imageToBase64(uri: string): Promise<string> {
    const started = Date.now();
    let file: fs.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const srcInfo = await source.getImageInfo();
      const width = srcInfo.size.width;
      const height = srcInfo.size.height;
      const maxEdge = Math.max(width, height);
      if (maxEdge > MAX_IMAGE_EDGE) {
        const ratio = MAX_IMAGE_EDGE / maxEdge;
        const options: image.DecodingOptions = {
          desiredSize: { width: Math.round(width * ratio), height: Math.round(height * ratio) }
        };
        try {
          pixelMap = await source.createPixelMap(options);
        } catch (error) {
          Logger.warn('按目标尺寸解码失败，回退全量解码', (error as Error).message);
          pixelMap = await source.createPixelMap();
          await pixelMap.scale(ratio, ratio);
        }
      } else {
        pixelMap = await source.createPixelMap();
      }
      Logger.debug('解码步骤: 像素解码完成, 原图最长边: ', maxEdge, ', 耗时(ms): ', Date.now() - started);
      packer = image.createImagePacker();
      const option: image.PackingOption = { format: 'image/jpeg', quality: JPEG_QUALITY };
      const buffer = await packer.packing(pixelMap, option);
      Logger.debug('解码步骤: JPEG打包完成, 字节数: ', buffer.byteLength, ', 耗时(ms): ', Date.now() - started);
      const base64Helper = new util.Base64Helper();
      const base64 = base64Helper.encodeToStringSync(new Uint8Array(buffer));
      Logger.debug('解码步骤: base64完成, 耗时(ms): ', Date.now() - started);
      return base64;
    } catch (error) {
      Logger.error('图片压缩转码失败', (error as Error).message);
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_image_failed')));
    } finally {
      if (pixelMap) {
        try {
          pixelMap.release();
        } catch (e) {
          Logger.warn('pixelMap释放失败', (e as Error).message);
        }
      }
      if (packer) {
        try {
          await packer.release();
        } catch (e) {
          Logger.warn('ImagePacker释放失败', (e as Error).message);
        }
      }
      if (source) {
        try {
          await source.release();
        } catch (e) {
          Logger.warn('ImageSource释放失败', (e as Error).message);
        }
      }
      if (file) {
        fs.closeSync(file);
      }
    }
  }

  // 提示词约束：只输出 JSON 数组，一张图多笔交易时输出多个元素，分类名只能取项目已有分类
  private buildPrompt(): string {
    const expenseNames = CategoryRegistry.listNames(AccountType.EXPENSES).join('、');
    const incomeNames = CategoryRegistry.listNames(AccountType.INCOME).join('、');
    const today = dayjs().format('YYYY-MM-DD');
    const yesterday = dayjs().subtract(1, 'day').format('YYYY-MM-DD');
    return '你是账单识别助手。请判断图片是否为账单、小票或收支截图，并提取其中的全部交易记录。' +
      '只输出一个 JSON 数组，不要输出任何解释文字或 markdown 代码块。' +
      '数组每个元素的格式：{"accountType": "支出 或 收入", "amount": number, ' +
      '"merchant": string, "payTime": "YYYY-MM-DD HH:mm 或空字符串", "category": string}。' +
      `今天是 ${today}。payTime 必须尽量精确到分钟，日期按如下规则换算：` +
      `图片印有"今天"时写 ${today}；印有"昨天"时写 ${yesterday}；` +
      `只印有时分（如 14:32、09:05:11）而看不到日期时，日期按今天补全为 "${today} HH:mm"；` +
      '完全看不到任何时间信息才用空字符串，禁止用当前时间或拍照时间胡乱猜测。' +
      `支出分类只能取：${expenseNames}。收入分类只能取：${incomeNames}。` +
      '非账单图片输出空数组 []；一张图包含多笔交易时输出多个元素；除 payTime 外无法确定的字段不要猜测，用空字符串或 0。';
  }

  // 调用 OpenAI 兼容的 chat/completions 接口，返回模型输出的文本
  // 传输层用 rcp（Remote Communication Kit）而非 @ohos.net.http：本机实测 netstack 存在
  // 1) h2 连接复用时请求静默卡死（无响应无报错、超时不触发）；
  // 2) 响应到达底层后 JS 回调丢失。
  // rcp 每笔请求独立 session、用完即 close，连接不跨请求复用；另保留看门狗兜底，
  // 底层再静默卡死时按超时抛错，交给上层重试/降级。
  private async postChat(messages: ChatMessage[]): Promise<string> {
    const url = this.config.baseUrl.replace(/\/+$/, '') + '/chat/completions';
    const body: ChatRequest = { model: this.config.model, messages: messages };
    const headers: rcp.RequestHeaders = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${this.config.apiKey}`
    };
    const configuration: rcp.Configuration = {
      transfer: {
        timeout: {
          connectMs: HTTP_TIMEOUT_MS,
          transferMs: HTTP_TIMEOUT_MS
        }
      }
    };
    const request = new rcp.Request(url, 'POST', headers, JSON.stringify(body), undefined, undefined, configuration);
    const session = rcp.createSession();
    Logger.info('云端诊断: 准备发起请求', url, 'model=' + this.config.model);
    let watchdogId: number = -1;
    try {
      const pending: Promise<rcp.Response> = session.fetch(request);
      // 看门狗超时比底层超时放宽 5s：只在底层静默卡死（无响应也无报错）时触发
      const watchdog: Promise<rcp.Response> = new Promise<rcp.Response>(
        (resolve: (value: rcp.Response) => void, reject: (reason: Error) => void) => {
          watchdogId = setTimeout((): void => {
            reject(new Error(WATCHDOG_TIMEOUT));
          }, HTTP_TIMEOUT_MS + WATCHDOG_EXTRA_MS);
        });
      const response = await Promise.race<rcp.Response>([pending, watchdog]);
      Logger.info('云端诊断: 请求已返回', 'responseCode=' + response.statusCode);
      const resultText = response.toString();
      if (resultText !== null && resultText.length > 0) {
        Logger.info('云端诊断: 响应体前200字符', resultText.substring(0, 200));
      }
      return this.handleResponse(response.statusCode, resultText);
    } catch (error) {
      const err = error as BusinessError;
      Logger.error('云端识别请求失败', String(err.code), err.message);
      if (err.message === WATCHDOG_TIMEOUT || err.code === HTTP_ERROR_TIMEOUT ||
        (err.message !== undefined && err.message.toLowerCase().indexOf('timeout') >= 0)) {
        throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_timeout')));
      }
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_network_failed')));
    } finally {
      if (watchdogId >= 0) {
        clearTimeout(watchdogId);
      }
      Logger.info('云端诊断: postChat结束, 关闭session');
      session.close();
    }
  }

  // 状态码分级处理，取 choices[0].message.content 作为模型输出
  // 4xx 客户端错误（除 429 限流）重试必然同结果，标记为不可重试
  private handleResponse(statusCode: number, resultText: string | null): string {
    if (statusCode === 401) {
      throw new NonRetryableError(getContext().resourceManager.getStringSync($r('app.string.cloud_unauthorized')));
    }
    if (statusCode === 429) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_rate_limited')));
    }
    if (statusCode === 400) {
      throw new NonRetryableError(this.badRequestMessage(resultText));
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_server_error')));
    }
    if (resultText === null || resultText.length === 0) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_bad_response')));
    }
    let parsed: ChatCompletionResponse;
    try {
      parsed = JSON.parse(resultText) as ChatCompletionResponse;
    } catch (error) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_bad_response')));
    }
    if (!parsed.choices || parsed.choices.length === 0 ||
      !parsed.choices[0].message || typeof parsed.choices[0].message.content !== 'string') {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_bad_response')));
    }
    return parsed.choices[0].message.content;
  }

  // 400 细分：多模态参数被拒（如纯文本模型收到图片）提示更换模型，其余为通用请求被拒
  private badRequestMessage(resultText: string | null): string {
    let message = '';
    if (resultText !== null && resultText.length > 0) {
      try {
        const parsed = JSON.parse(resultText) as CloudErrorResponse;
        if (parsed.error && typeof parsed.error.message === 'string') {
          message = parsed.error.message;
        }
      } catch (error) {
        // 响应体不是 JSON 时走通用文案
      }
    }
    Logger.error('云端诊断: 请求被拒绝(400)', message);
    if (/参数非法|不支持|image|multimodal|vision/i.test(message)) {
      const noVision = getContext().resourceManager.getStringSync($r('app.string.cloud_model_no_vision'));
      // 记录熔断：本会话内该模型不再重试图片识别
      CloudLlmRecognizer.visionBrokenModel = this.config.model;
      CloudLlmRecognizer.visionBrokenMessage = noVision;
      return noVision;
    }
    return getContext().resourceManager.getStringSync($r('app.string.cloud_bad_request'));
  }
}
