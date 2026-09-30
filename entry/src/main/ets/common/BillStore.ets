/**
 * 账单变更监听回调
 */
export type BillChangeListener = () => void;

/**
 * 账单变更中心：账单增删成功后通知订阅方刷新，替代 isPageShow + @Watch 的刷新方式
 */
class BillStore {
  private listeners: BillChangeListener[] = [];

  subscribe(listener: BillChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: BillChangeListener): void {
    this.listeners = this.listeners.filter((item: BillChangeListener): boolean => item !== listener);
  }

  notifyChanged(): void {
    this.listeners.forEach((listener: BillChangeListener) => {
      listener();
    });
  }
}

export default new BillStore();
