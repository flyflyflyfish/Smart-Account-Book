/**
 * 账本变更监听回调
 */
export type LedgerChangeListener = () => void;

/**
 * 账本变更中心：账本/记录增删改成功后通知订阅方刷新。
 * 账本列表 tab 常驻 Index 页，从详情页返回时依赖此通知重查。
 */
class LedgerStore {
  private listeners: LedgerChangeListener[] = [];

  subscribe(listener: LedgerChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: LedgerChangeListener): void {
    this.listeners = this.listeners.filter((item: LedgerChangeListener): boolean => item !== listener);
  }

  notifyChanged(): void {
    this.listeners.forEach((listener: LedgerChangeListener) => {
      listener();
    });
  }
}

export default new LedgerStore();
