/**
 * 识别过程非致命警告收集器：service 层（识别器装饰器）不能直接弹 UI，
 * 先在这里暂存去重，由识别页面在批次结束后取走并展示
 */
export class RecognitionWarnings {
  private static items: string[] = [];

  // 记录警告：同一条只记一次
  static add(message: string): void {
    if (message === '') {
      return;
    }
    if (RecognitionWarnings.items.indexOf(message) < 0) {
      RecognitionWarnings.items.push(message);
    }
  }

  // 取走全部警告并清空
  static drain(): string[] {
    const result = RecognitionWarnings.items;
    RecognitionWarnings.items = [];
    return result;
  }
}
