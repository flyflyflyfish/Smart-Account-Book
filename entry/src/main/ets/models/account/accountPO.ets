/**
 * 记录的数据库持久化对象
 */
export default class AccountPO {
  /**
   * 记录id（UUID 文本主键）
   */
  id: string = '';
  /**
   * 记录类型
   */
  type: number = 0;
  /**
   * 收支类型
   */
  accountType: number = 0;
  /**
   * 记录描述
   */
  description: string = '';
  /**
   * 记录的创建时间
   */
  createTime: number = 0;
  /**
   * 金额
   */
  amount: number = 0;
  /**
   * 记录日期
   */
  time: number = 0;
  /**
   * 商家名，手动记账可为空
   */
  merchant: string = '';
  /**
   * 来源：0 手动，1 图片识别
   */
  source: number = 0;
  /**
   * 精确到分钟的支付时间戳，0 表示未知（兼容旧数据）
   */
  payTime: number = 0;
}
