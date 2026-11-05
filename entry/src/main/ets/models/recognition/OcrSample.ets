/**
 * 训练数据采集（阶段1）的数据模型：图片尺寸、OCR 文本块、多模态交易列表。
 * 位置与大小一律使用相对值（占图片宽高的比例 0~1），不写死像素。
 */

// 单个 OCR 文本块（以“行”为粒度）：text 为文本内容，坐标为相对比例
export interface OcrTextBlock {
  text: string;
  left: number;
  top: number;
  right: number;
  bottom: number;
}

// 一次端侧 OCR 的视觉结果：图片像素宽高（作为比例分母）+ 文本块列表
export interface OcrVisionResult {
  width: number;
  height: number;
  blocks: OcrTextBlock[];
}

// 多模态模型给出的单笔交易（训练样本的“标签”来源，原样记录多模态输出）
export interface SampleTransaction {
  accountType: string;   // '支出' | '收入'
  amount: number;        // 金额（元）；图上没有时为 0
  merchant: string;      // 商家；图上没有时为空串
  payTime: number;       // 支付时间戳（毫秒）；沿用多模态解析器的回退值
  categoryName: string;  // 分类名；图上没有时为多模态回退的“其他”
  confidence: number;    // 0~1
}

// 一条训练样本：{图片宽高, OCR 文本块列表, 大模型原始输出, 用户确认结果, 采集时间}
// 仅存本机，不上传、不保存图片本身。
export interface TrainingSample {
  width: number;
  height: number;
  ocrBlocks: OcrTextBlock[];
  transactions: SampleTransaction[];  // 大模型原始输出（预标注，仅作参考/对比）
  confirmed?: SampleTransaction[];     // 用户在确认页最终入账的字段（人工真值，训练用它当标签）；旧数据可能缺失
  capturedAt: number;
}

// 样本管理页/列表用的一条样本摘要（不加载全量内容）
export interface SampleSummary {
  index: number;       // 文件内 1-based 序号
  capturedAt: number;  // 采集时间戳（毫秒）
  lineCount: number;   // OCR 文本行数
  txnCount: number;    // 交易笔数
  txnPreview: string;  // 首笔交易摘要（如 "¥35.00 汉堡王"），无交易为 "无交易"
}
