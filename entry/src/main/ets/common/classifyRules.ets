import { AccountExpensesType } from '../models/account/account';

/**
 * 关键词分类规则：商家名（或识别原文）命中关键词即归类，数组顺序即优先级
 */
export interface ClassifyRule {
  categoryId: number;
  keywords: string[];
}

/**
 * 支出侧关键词规则：集中配置，便于调整，不写死在分类逻辑里
 */
export const EXPENSE_CLASSIFY_RULES: ClassifyRule[] = [
  {
    categoryId: AccountExpensesType.MEALS,
    keywords: ['美团', '饿了么', '外卖', '餐厅', '饭店', '小吃', '早餐', '午餐', '晚餐',
      '咖啡', '奶茶', '星巴克', '肯德基', '麦当劳', '火锅', '烧烤', '食堂', '餐']
  },
  {
    categoryId: AccountExpensesType.MEDICAL,
    keywords: ['医院', '药店', '诊所', '挂号', '门诊', '体检', '医疗', '药房', '药']
  },
  {
    categoryId: AccountExpensesType.TRANSPORT,
    keywords: ['滴滴', '地铁', '公交', '出租', '打车', '高铁', '火车', '机票', '航空',
      '加油', '停车', '高速', '单车', '出行', '交通']
  },
  {
    categoryId: AccountExpensesType.HOUSE,
    keywords: ['房租', '物业', '水费', '电费', '燃气', '房贷', '家居', '家具', '维修', '住房']
  },
  {
    categoryId: AccountExpensesType.TOBACCO,
    keywords: ['烟', '酒', '零食', '槟榔']
  },
  {
    categoryId: AccountExpensesType.STUDY,
    keywords: ['学费', '培训', '课程', '书店', '文具', '考试', '报名', '学习', '书费']
  },
  {
    categoryId: AccountExpensesType.COMMUNICATE,
    keywords: ['话费', '流量', '宽带', '充值', '通讯', '电话费', '运营商']
  },
  {
    categoryId: AccountExpensesType.SOCIAL,
    keywords: ['红包', '随礼', '聚会', '请客', '礼物', '份子', '社交']
  },
  {
    categoryId: AccountExpensesType.INVEST,
    keywords: ['股票', '基金', '理财', '投资']
  },
  {
    categoryId: AccountExpensesType.SHOPPING,
    keywords: ['淘宝', '京东', '拼多多', '商场', '超市', '购物', '衣服', '鞋', '化妆品', '日用品', '快递']
  },
  {
    categoryId: AccountExpensesType.ENTERTAINMENT,
    keywords: ['电影', '游戏', 'KTV', '演唱会', '门票', '旅游', '景点', '娱乐', '网吧']
  },
  {
    categoryId: AccountExpensesType.LOAN,
    keywords: ['借出', '外借', '借款', '借给']
  }
];
