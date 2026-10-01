/**
 * 商家-分类记忆记录：用户确认分类并入账后写入，供下次同商家优先命中
 */
export default class MerchantCategory {
  merchant: string = '';
  categoryId: number = 0;
  accountType: number = 0;
  updatedAt: number = 0;
}
