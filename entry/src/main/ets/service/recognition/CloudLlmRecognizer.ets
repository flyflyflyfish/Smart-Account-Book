import http from '@ohos.net.http';
import dayjs from 'dayjs';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { BusinessError } from '@ohos.base';
import { AccountType } from '../../models/account/account';
import { RecognitionResult } from '../../models/recognition/RecognitionResult';
import {
  ChatCompletionResponse,
  ChatContent,
  ChatContentImageUrl,
  ChatMessage,
  ChatRequest,
  ChatRequestHeader,
  CloudLlmConfig
} from '../../models/recognition/CloudLlmModels';
import CategoryRegistry from '../../models/accountType/CategoryRegistry';
import { Recognizer } from './Recognizer';
import { CloudResultParser } from './CloudResultParser';
import { Logger } from '../../utils/Logger';

// 图片最长边限制：缩小到 1024 显著减小 base64 体积，加快上传与推理
const MAX_IMAGE_EDGE: number = 1024;
// JPEG 压缩质量：降到 70 进一步减小体积，账单文字仍可辨
const JPEG_QUALITY: number = 70;
// 云端请求超时时间：多笔账单图片较大、模型推理慢，放宽到 120s 避免误超时
const HTTP_TIMEOUT_MS: number = 120000;
// http 模块透传的 curl 超时错误码
const HTTP_ERROR_TIMEOUT: number = 2300028;

/**
 * 云端识别器：适配器模式封装 OpenAI 兼容的多模态大模型 API
 * 流程：图片压缩转码 -> 组装请求 -> 调云端接口 -> 清理并校验 JSON 数组 -> 映射为多笔识别结果
 */
export class CloudLlmRecognizer implements Recognizer {
  private config: CloudLlmConfig;
  private parser: CloudResultParser = new CloudResultParser();

  constructor(config: CloudLlmConfig) {
    this.config = config;
  }

  async recognize(imageUri: string): Promise<RecognitionResult[]> {
    if (!this.config.baseUrl || !this.config.apiKey || !this.config.model) {
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_config_incomplete')));
    }
    const base64 = await this.imageToBase64(imageUri);
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

  // 读取图片 -> 缩放至最长边不超过 1280 -> 打包为 JPEG(质量80) -> Base64
  private async imageToBase64(uri: string): Promise<string> {
    let file: fs.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      pixelMap = await source.createPixelMap();
      const info = await pixelMap.getImageInfo();
      const maxEdge = Math.max(info.size.width, info.size.height);
      if (maxEdge > MAX_IMAGE_EDGE) {
        const ratio = MAX_IMAGE_EDGE / maxEdge;
        await pixelMap.scale(ratio, ratio);
      }
      packer = image.createImagePacker();
      const option: image.PackingOption = { format: 'image/jpeg', quality: JPEG_QUALITY };
      const buffer = await packer.packing(pixelMap, option);
      const base64Helper = new util.Base64Helper();
      return base64Helper.encodeToStringSync(new Uint8Array(buffer));
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
  private async postChat(messages: ChatMessage[]): Promise<string> {
    const url = this.config.baseUrl.replace(/\/+$/, '') + '/chat/completions';
    const body: ChatRequest = { model: this.config.model, messages: messages };
    const header: ChatRequestHeader = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${this.config.apiKey}`
    };
    const request = http.createHttp();
    Logger.info('云端诊断: 准备发起请求', url, 'model=' + this.config.model);
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      Logger.info('云端诊断: 请求已返回', 'responseCode=' + response.responseCode,
        'resultType=' + typeof response.result);
      if (typeof response.result === 'string') {
        Logger.info('云端诊断: 响应体前200字符', response.result.substring(0, 200));
      }
      return this.handleResponse(response);
    } catch (error) {
      const err = error as BusinessError;
      Logger.error('云端识别请求失败', String(err.code), err.message);
      if (err.code === HTTP_ERROR_TIMEOUT) {
        throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_timeout')));
      }
      throw new Error(getContext().resourceManager.getStringSync($r('app.string.cloud_network_failed')));
    } finally {
      Logger.info('云端诊断: postChat结束, 销毁request');
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
}
