/**
 * 云端多模态大模型识别的数据模型：OpenAI 兼容 chat/completions 的请求、响应与配置结构
 */

// 云端识别服务配置：由设置页填写，保存在本机 Preferences
export interface CloudLlmConfig {
  baseUrl: string;
  apiKey: string;
  model: string;
}

// content 中的图片地址：data:image/jpeg;base64,xxx
export interface ChatContentImageUrl {
  url: string;
}

// 消息 content 数组元素：文本或图片二选一，可选字段区分
export interface ChatContent {
  type: string;
  text?: string;
  image_url?: ChatContentImageUrl;
}

export interface ChatMessage {
  role: string;
  content: ChatContent[];
}

export interface ChatRequest {
  model: string;
  messages: ChatMessage[];
}

// 请求头单独建模，避免对象字面量缺少类型上下文
export interface ChatRequestHeader {
  'Content-Type': string;
  'Authorization': string;
}

export interface ChatCompletionMessage {
  role: string;
  content: string;
}

export interface ChatCompletionChoice {
  index: number;
  message: ChatCompletionMessage;
}

export interface ChatCompletionResponse {
  choices: ChatCompletionChoice[];
}

// 模型按提示词约束应输出的 JSON 结构：字段可能缺失或类型不符，解析时逐个校验
export interface LlmBillRaw {
  isBill?: boolean;
  accountType?: string;
  amount?: number;
  merchant?: string;
  payTime?: string;
  category?: string;
}
