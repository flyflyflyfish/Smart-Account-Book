/**
 * 数据库操作异常
 */
export class DbError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'DbError';
  }
}
