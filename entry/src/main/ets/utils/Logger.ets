import hilog from '@ohos.hilog';

export class Logger {
  private static domain: number = 0xFF00;
  private static prefix: string = '[account-app]';
  private static format: string = '%{private}s';

  private static buildFormat(count: number): string {
    const parts: string[] = [];
    for (let i = 0; i < count; i++) {
      parts.push(Logger.format);
    }
    return parts.join(', ');
  }

  private static stringify(arg: Object): string {
    if (typeof arg === 'string') {
      return arg;
    }
    if (typeof arg === 'number') {
      return arg.toString();
    }
    return JSON.stringify(arg);
  }

  private static formatLogs(args: Object[]): string[] {
    return args.map((arg: Object): string => Logger.stringify(arg));
  }

  static debug(...args: Object[]): void {
    hilog.debug(Logger.domain, Logger.prefix, Logger.buildFormat(args.length), ...Logger.formatLogs(args));
  }

  static info(...args: Object[]): void {
    hilog.info(Logger.domain, Logger.prefix, Logger.buildFormat(args.length), ...Logger.formatLogs(args));
  }

  static warn(...args: Object[]): void {
    hilog.warn(Logger.domain, Logger.prefix, Logger.buildFormat(args.length), ...Logger.formatLogs(args));
  }

  static error(...args: Object[]): void {
    hilog.error(Logger.domain, Logger.prefix, Logger.buildFormat(args.length), ...Logger.formatLogs(args));
  }
}
