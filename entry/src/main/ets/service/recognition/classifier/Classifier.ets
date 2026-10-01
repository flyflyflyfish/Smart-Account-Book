/**
 * 分类器接口：根据商家名与识别原文推断分类 id（CategoryRegistry 中的分类 id）
 * 返回 null 表示无法判断，由上层回退处理
 */
export interface Classifier {
  classify(merchant: string, rawText: string): Promise<number | null>;
}
