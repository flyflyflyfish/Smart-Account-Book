/**
 * 端侧 OCR 的视觉数据模型：图片尺寸与 OCR 文本块。
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
