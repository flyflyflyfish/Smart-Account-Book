/**
 * 云端大模型服务商目录：接口地址（OpenAI 兼容）已内置，仅 API Key 需要用户手填。
 * 模型名以各厂商官方文档为准（2026-10 核实），版本迭代较快，接入前可到各厂商控制台确认当前可用模型。
 */

// 可选模型：id 为请求时填写的 model 字段，label 为界面显示名，vision 表示是否支持图片输入
export interface LlmModelOption {
  id: string;
  label: string;
  vision: boolean;
}

// 服务商：baseUrl 已内置（custom 服务商为空，由用户手填）
export interface LlmProvider {
  id: string;
  name: string;
  baseUrl: string;
  models: LlmModelOption[];
  custom: boolean;
}

export const LLM_PROVIDERS: LlmProvider[] = [
  {
    id: 'doubao',
    name: '豆包',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    custom: false,
    models: [
      { id: 'doubao-seed-evolving', label: '豆包 Seed Evolving（快速迭代）', vision: true },
      { id: 'doubao-seed-2-1-pro-260915', label: '豆包 2.1 Pro（旗舰）', vision: true },
      { id: 'doubao-seed-2-1-lite-260915', label: '豆包 2.1 Lite（更快更省）', vision: true },
      { id: 'doubao-seed-2-0-mini-260428', label: '豆包 2.0 Mini', vision: true },
      { id: 'doubao-seed-2-0-code-preview-260215', label: '豆包 2.0 Code（预览）', vision: true }
    ]
  },
  {
    id: 'qwen',
    name: '通义千问',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    custom: false,
    models: [
      { id: 'qwen3.8-max', label: 'Qwen3.8 Max（旗舰·视觉）', vision: true },
      { id: 'qwen3.8-plus', label: 'Qwen3.8 Plus（视觉）', vision: true },
      { id: 'qwen3.8-flash', label: 'Qwen3.8 Flash（视觉·性价比）', vision: true },
      { id: 'qwen3.8-omni-flash', label: 'Qwen3.8 Omni Flash（全模态）', vision: true },
      { id: 'qwen-vl-max', label: 'Qwen-VL Max（视觉）', vision: true },
      { id: 'qwen-max', label: 'Qwen Max（纯文本旗舰）', vision: false },
      { id: 'qwen-plus', label: 'Qwen Plus（纯文本）', vision: false },
      { id: 'qwen-turbo', label: 'Qwen Turbo（纯文本·快）', vision: false },
      { id: 'qwen3-coder-plus', label: 'Qwen3 Coder Plus（纯文本）', vision: false }
    ]
  },
  {
    id: 'glm',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    custom: false,
    models: [
      { id: 'glm-5.3', label: 'GLM-5.3（纯文本旗舰）', vision: false },
      { id: 'glm-5.3-flash', label: 'GLM-5.3 Flash（多模态）', vision: true },
      { id: 'glm-5.3-flashx', label: 'GLM-5.3 FlashX（多模态·高速）', vision: true },
      { id: 'glm-5.2', label: 'GLM-5.2（文本·支持视觉）', vision: true },
      { id: 'glm-4-plus', label: 'GLM-4 Plus（纯文本·旧版）', vision: false },
      { id: 'glm-4-air', label: 'GLM-4 Air（纯文本·旧版）', vision: false },
      { id: 'glm-4-flash', label: 'GLM-4 Flash（纯文本·旧版）', vision: false }
    ]
  },
  {
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    custom: false,
    models: [
      { id: 'deepseek-v4-pro', label: 'DeepSeek-V4 Pro（纯文本）', vision: false },
      { id: 'deepseek-flash', label: 'DeepSeek-V4.1 Flash（支持图片）', vision: true },
      { id: 'deepseek-v3.2', label: 'DeepSeek-V3.2（纯文本·旧版）', vision: false },
      { id: 'deepseek-coder-v2', label: 'DeepSeek Coder V2（纯文本）', vision: false }
    ]
  },
  {
    id: 'kimi',
    name: 'Kimi（月之暗面）',
    baseUrl: 'https://api.moonshot.cn/v1',
    custom: false,
    models: [
      { id: 'kimi-k3', label: 'Kimi K3（旗舰·视觉）', vision: true },
      { id: 'kimi-k2.7-code-highspeed', label: 'Kimi K2.7 Code 高速（视觉）', vision: true },
      { id: 'kimi-k2.7-code', label: 'Kimi K2.7 Code（视觉）', vision: true },
      { id: 'kimi-k2.6', label: 'Kimi K2.6（通用·视觉）', vision: true }
    ]
  },
  {
    id: 'custom',
    name: '自定义',
    baseUrl: '',
    custom: true,
    models: []
  }
];

// 按 id 查服务商，找不到时兜底返回「自定义」
export function findProvider(id: string): LlmProvider {
  for (const p of LLM_PROVIDERS) {
    if (p.id === id) {
      return p;
    }
  }
  return LLM_PROVIDERS[LLM_PROVIDERS.length - 1];
}

// 按模型 id 查显示名，未命中目录时直接返回原模型名
export function findModelLabel(providerId: string, modelId: string): string {
  const provider = findProvider(providerId);
  for (const m of provider.models) {
    if (m.id === modelId) {
      return m.label;
    }
  }
  return modelId;
}
