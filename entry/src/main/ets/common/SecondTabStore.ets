import PreferenceUtil from '../utils/PreferenceUtil';
import { Logger } from '../utils/Logger';
import { PREF_SECOND_TAB_STYLE, SECOND_TAB_STYLE_AI, SECOND_TAB_STYLE_LEDGER } from './constants';

/**
 * 第二页签样式变更监听回调
 */
export type SecondTabChangeListener = () => void;

/**
 * 底部第二页签样式（AI 助手 / 账本）的全局内存单例。
 * Index 订阅变更通知即时刷新底部页签，同时每次回到前台（onPageShow）重读内存值兜底。
 */
class SecondTabStore {
  private style: string = SECOND_TAB_STYLE_AI;
  private listeners: SecondTabChangeListener[] = [];

  /** 启动时由 EntryAbility 恢复磁盘保存的样式 */
  init(style: string): void {
    this.style = style === SECOND_TAB_STYLE_LEDGER ? style : SECOND_TAB_STYLE_AI;
  }

  current(): string {
    return this.style;
  }

  isLedger(): boolean {
    return this.style === SECOND_TAB_STYLE_LEDGER;
  }

  subscribe(listener: SecondTabChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unsubscribe(listener: SecondTabChangeListener): void {
    this.listeners = this.listeners.filter((item: SecondTabChangeListener): boolean => item !== listener);
  }

  /** 外观页切换时更新内存值、通知订阅方并异步落盘 */
  set(style: string): void {
    this.style = style === SECOND_TAB_STYLE_LEDGER ? style : SECOND_TAB_STYLE_AI;
    this.listeners.forEach((listener: SecondTabChangeListener) => {
      listener();
    });
    PreferenceUtil.putPreferenceValue(PREF_SECOND_TAB_STYLE, this.style)
      .catch((err: Error): void => {
        Logger.error('保存第二页签样式失败', err.message);
      });
  }
}

export default new SecondTabStore();
