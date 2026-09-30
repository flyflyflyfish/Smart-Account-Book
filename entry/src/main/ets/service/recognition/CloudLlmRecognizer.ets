import http from '@ohos.net.http';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { BusinessError } from '@ohos.base';
import dayjs from 'dayjs';
import { AccountType } from '../../models/account/account';
import { RecognitionResult } from '../../models/recognition/RecognitionResult';
import {
  ChatCompletionResponse,
  ChatContent,
  ChatContentImageUrl,
  ChatMessage,
  ChatRequest,
  ChatRequestHeader,
  CloudLlmConfig,
  LlmBillRaw
} from '../../models/recognition/CloudLlmModels';
import CategoryRegistry from '../../models/accountType/CategoryRegistry';
import { Recognizer } from './Recognizer';
import { Logger } from '../../utils/Logger';

// 图片最长边限制：兼顾识别精度与请求体积
const MAX_IMAGE_EDGE: number = 1280;
// JPEG 压缩质量
const JPEG_QUALITY: number = 80;
// 云端请求超时时间
const HTTP_TIMEOUT_MS: number = 30000;
// http 模块透传的 curl 超时错误码
const HTTP_ERROR_TIMEOUT: number = 2300028;

/**
 * 云端识别器：适配器模式封装 OpenAI 兼容的多模态大模型 API
 * 流程：图片压缩转码 -> 组装请求 -> 调云端接口 -> 清理并校验 JSON -> 映射为识别结果
 */
export class CloudLlmRecognizer implements Recognizer {
  private config: CloudLlmConfig;

  constructor(config: CloudLlmConfig) {
    this.config = config;
  }

  async recognize(imageUri: string): Promise<RecognitionResult> {
    if (!this.config.baseUrl || !this.config.apiKey || !this.config.model) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_config_incomplete')));
    }
    const base64 = await this.imageToBase64(imageUri);
    const textPart: ChatContent = { type: 'text', text: this.buildPrompt() };
    const imageUrl: ChatContentImageUrl = { url: `data:image/jpeg;base64,${base64}` };
    const imagePart: ChatContent = { type: 'image_url', image_url: imageUrl };
    const message: ChatMessage = { role: 'user', content: [textPart, imagePart] };
    const content = await this.postChat([message]);
    return this.parseResult(content);
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

  // 读取图片 -> 缩放至最长边不超过 1280 -> 打包为 JPEG(质量80) -> Base64
  private async imageToBase64(uri: string): Promise<string> {
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const source = image.createImageSource(file.fd);
      const pixelMap = await source.createPixelMap();
      const info = await pixelMap.getImageInfo();
      const maxEdge = Math.max(info.size.width, info.size.height);
      if (maxEdge > MAX_IMAGE_EDGE) {
        const ratio = MAX_IMAGE_EDGE / maxEdge;
        await pixelMap.scale(ratio, ratio);
      }
      const packer = image.createImagePacker();
      const option: image.PackingOption = { format: 'image/jpeg', quality: JPEG_QUALITY };
      const buffer = await packer.packing(pixelMap, option);
      const base64Helper = new util.Base64Helper();
      const encoded = base64Helper.encodeToStringSync(new Uint8Array(buffer));
      pixelMap.release();
      return encoded;
    } catch (error) {
      Logger.error('图片压缩转码失败', (error as Error).message);
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_image_failed')));
    } finally {
      if (file) {
        fs.closeSync(file);
      }
    }
  }

  // 提示词约束：只输出 JSON，分类名只能取项目已有分类，不确定的字段留空
  private buildPrompt(): string {
    const expenseNames = CategoryRegistry.listNames(AccountType.EXPENSES).join('、');
    const incomeNames = CategoryRegistry.listNames(AccountType.INCOME).join('、');
    return '你是账单识别助手。请判断图片是否为账单、小票或收支截图，并提取关键信息。' +
      '只输出一个 JSON 对象，不要输出任何解释文字或 markdown 代码块。' +
      'JSON 格式：{"isBill": boolean, "accountType": "支出 或 收入", "amount": number, ' +
      '"merchant": string, "payTime": "YYYY-MM-DD HH:mm 或空字符串", "category": string}。' +
      `支出分类只能取：${expenseNames}。收入分类只能取：${incomeNames}。` +
      '非账单图片 isBill 为 false，其余字段用空字符串或 0；无法确定的字段不要猜测，用空字符串或 0。';
  }

  // 调用 OpenAI 兼容的 chat/completions 接口，返回模型输出的文本
  private async postChat(messages: ChatMessage[]): Promise<string> {
    const url = this.config.baseUrl.replace(/\/+$/, '') + '/chat/completions';
    const body: ChatRequest = { model: this.config.model, messages: messages };
    const header: ChatRequestHeader = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${this.config.apiKey}`
    };
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      return this.handleResponse(response);
    } catch (error) {
      const err = error as BusinessError;
      Logger.error('云端识别请求失败', String(err.code), err.message);
      if (err.code === HTTP_ERROR_TIMEOUT) {
        throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_timeout')));
      }
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_network_failed')));
    } finally {
      request.destroy();
    }
  }

  // 状态码分级处理，取 choices[0].message.content 作为模型输出
  private handleResponse(response: http.HttpResponse): string {
    const code = response.responseCode;
    if (code === 401) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_unauthorized')));
    }
    if (code === 429) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_rate_limited')));
    }
    if (code < 200 || code >= 300) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_server_error')));
    }
    const resultText = response.result;
    if (typeof resultText !== 'string') {
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

  // 模型可能包裹 markdown 代码块或在 JSON 前后输出多余文字，先清理再解析
  private parseResult(content: string): RecognitionResult {
    let cleaned = content.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replace(/^```[a-zA-Z]*\s*/, '').replace(/```\s*$/, '').trim();
    }
    const start = cleaned.indexOf('{');
    const end = cleaned.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_bad_result')));
    }
    let raw: LlmBillRaw;
    try {
      raw = JSON.parse(cleaned.substring(start, end + 1)) as LlmBillRaw;
    } catch (error) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_bad_result')));
    }
    if (raw.isBill !== true) {
      return this.notBillResult();
    }
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

  // 分类名不在已有列表时回退为该收支侧的“其他”
  private normalizeCategory(name: string, accountType: AccountType): string {
    const names = CategoryRegistry.listNames(accountType);
    if (names.indexOf(name) >= 0) {
      return name;
    }
    return names[names.length - 1];
  }

  // 时间缺失或格式非法时用当前时间兜底
  private parsePayTime(text: string): number {
    if (text) {
      const parsed = dayjs(text);
      if (parsed.isValid()) {
        return parsed.valueOf();
      }
    }
    return Date.now();
  }

  private notBillResult(): RecognitionResult {
    const result: RecognitionResult = {
      accountType: AccountType.EXPENSES,
      amount: 0,
      merchant: '',
      payTime: Date.now(),
      categoryName: '',
      confidence: 0,
      isBill: false
    };
    return result;
  }
}
