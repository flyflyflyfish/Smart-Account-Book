/**
 * 本地账单模型核心（阶段4）：与 Python 训练侧（ml_tools/train_model.py）逐位对齐的推理实现。
 *
 * 约束：
 *   - 纯逻辑文件：不 import 任何 ohos/ArkUI 依赖，可直接在 Node 下做两端比对测试；
 *   - 所有特征只用相对值（位置比例、高度比、文本统计），与训练侧同一份规范；
 *   - 归一化统一用 nfkcLite（全角 ASCII 区 U+FF01~U+FF5E -> 半角、￥ -> ¥），
 *     不依赖 String.normalize，保证两端逐块一致；
 *   - 字符统计一律按 Unicode 码点遍历（for-of），避免 JS UTF-16 与 Python 码点的长度差异；
 *   - 置信度口径：amount 块的 amount 类概率；有商户块则与 merchant 类概率取平均；
 *     无商户块 *0.8；金额来自回退文本（无 amount 预测块）再 *0.5。
 */

// ---------------- 数据模型 ----------------

// 输入：OCR 文本块（以"行"为粒度，坐标为相对比例 0~1）
export interface BillModelBlock {
  text: string;
  left: number;
  top: number;
  right: number;
  bottom: number;
}

// 输出：抽取出的单笔交易
export interface BillTxnPrediction {
  amount: number;       // 金额（元，绝对值）
  merchant: string;     // 商户名（可能为空串）
  isIncome: boolean;    // 金额文本带 '+' 号为收入，否则为支出
  confidence: number;   // 0~1
  payTime: number;      // 支付时间（毫秒时间戳；图上无时间信息时回退 nowMs）
}

// HGB 单节点（扁平数组）：leaf 为 true 时只读 value；否则按 feature/threshold 走 left/right
export interface BillHgbNode {
  leaf: boolean;
  value: number;
  feature: number;
  threshold: number;
  missingLeft: boolean;
  left: number;
  right: number;
}

// HGB 块分类器：trees[迭代][类别][节点]；raw[c] = baseline[c] + Σ 各迭代第 c 棵树的叶子值
export interface BillHgbModel {
  classes: string[];
  baseline: number[];
  trees: BillHgbNode[][][];
}

// 配对决策树节点（递归结构）
export interface BillDtNode {
  leaf: boolean;
  label: string;                    // leaf 时为类别名（"same"/"diff"）
  feature: number;
  threshold: number;
  left: BillDtNode | null;
  right: BillDtNode | null;
}

// 完整模型：HGB 块分类 + DT 配对
export interface BillModel {
  blockHgb: BillHgbModel;
  pairTree: BillDtNode;
}

// 金额抽取结果：sign 为 '+' / '-' / ''（无符号）
interface BillAmountMatch {
  value: number;
  sign: string;
}

// 时间抽取结果：ms 为毫秒时间戳，dated 表示文本里是否含日期（纯时刻为 false）
export interface BillPayTime {
  ms: number;
  dated: boolean;
}

// 儒略日序号 -> (年, 月, 日)
interface BillYmd {
  y: number;
  m: number;
  d: number;
}

// 组时间解析结果：ms + 命中的块下标（-1 表示回退 nowMs）
interface BillTimeResolve {
  ms: number;
  hitIdx: number;
}

// 配对特征输入：块位置 + 块特征里的 digitRatio(feats[1])、textLen(feats[0])
interface BillPairInput {
  left: number;
  top: number;
  right: number;
  bottom: number;
  digitRatio: number;
  textLen: number;
}

// ---------------- JSON 原始结构（JSON.parse 边界，字段可缺省） ----------------

interface BillHgbNodeRaw {
  leaf?: boolean;
  value?: number;
  feature?: number;
  threshold?: number;
  missingLeft?: boolean;
  left?: number;
  right?: number;
}

interface BillHgbRaw {
  classes?: string[];
  baseline?: number[];
  trees?: BillHgbNodeRaw[][][];
}

interface BillDtNodeRaw {
  leaf?: boolean;
  label?: string;
  feature?: number;
  threshold?: number;
  left?: BillDtNodeRaw;
  right?: BillDtNodeRaw;
}

interface BillPairClassifierRaw {
  tree?: BillDtNodeRaw;
}

interface BillModelRaw {
  blockClassifierHgb?: BillHgbRaw;
  pairClassifier?: BillPairClassifierRaw;
}

// ---------------- 正则（与训练侧逐字一致；输入均为 squeeze 后无空白文本） ----------------

const AMOUNT_WORD_RE = /合计|总计|金额|支出|收入|收款|付款|转账|红包|退款|支付|账单/;
const TIME_RE = /[0-9]{1,2}\s*[:：时]\s*[0-9]{2}/;
const DATE_RE = /[0-9]{1,4}\s*[年/.\-]\s*[0-9]{1,2}\s*[月/.\-]?\s*[0-9]{0,2}\s*日?|[0-9]{1,2}\s*月\s*[0-9]{1,2}\s*日|今天|昨天|前天|星期[一二三四五六日]|周[一二三四五六日]/;
const DECIMAL_RE = /[0-9]+\.[0-9]{1,2}/;
const SIGN_RE = /[+\-]\s*[¥￥]?\s*[0-9]|[0-9][0-9,，.]*\s*元?\s*[+\-]$/;
const PURE_NUM_RE = /^[+\-¥￥0-9.,，:：/年月日时分秒%]+$/;
const NUM_SEQ_RE = /[0-9]+(?:\.[0-9]{1,4})?/g;
const NUM_IN_TEXT_RE = /[+\-][¥￥]?\s*[0-9][0-9,，]*(?:\.[0-9]{1,2})?|[¥￥]\s*[+\-]?[0-9][0-9,，]*(?:\.[0-9]{1,2})?|[0-9][0-9,，]*(?:\.[0-9]{1,2})/g;
const STRIP_AMOUNT_RE = /[¥￥,，+\-\s]/g;
const STRONG_AMOUNT_RE = /[+\-]\s*[¥￥]?\s*[0-9]+\.[0-9]{1,2}/;

// ---------------- 时间抽取正则（与训练侧逐字一致；输入为 nfkcLite 后保留空格的文本） ----------------

// 星期几 -> 0=周一 … 6=周日
const WEEKDAY_IDX: Record<string, number> = { '一': 0, '二': 1, '三': 2, '四': 3, '五': 4, '六': 5, '日': 6, '天': 6 };
// 绝对日期：YYYY年M月D日 / YYYY-M-D / YYYY.M.D / YYYY/M/D
const ABS_DATE_RE = /([0-9]{4})\s*[年/.\-]\s*([0-9]{1,2})\s*[月/.\-]\s*([0-9]{1,2})\s*日?/;
// 相对日期：今天 / 昨天 / 前天
const REL_DATE_RE = /今天|昨天|前天/;
// 星期X / 周X
const WEEKDAY_RE = /[星期周]([一二三四五六日天])/;
// M月D日
const MD_MONTH_RE = /([0-9]{1,2})\s*月\s*([0-9]{1,2})/;
// M-D / M.D / M/D（迭代用，需手动重置 lastIndex）
const MD_SEP_ALL_RE = /([0-9]{1,2})\s*[-/.]\s*([0-9]{1,2})/g;
// 粘连的"月-日+时钟"（OCR 丢空格/冒号读成点）：09-2909:50 / 09-28.16.00 / 09-22 09:45
const GLUED_RE = /([0-9]{1,2})\s*[-/.]\s*([0-9]{1,2})\s*([0-9]{1,2})\s*[.:：时]\s*([0-9]{2})/;
// 时刻：12 小时制前缀 + HH:MM / HH时MM（迭代用，需手动重置 lastIndex）
const CLOCK_ALL_RE = /(上午|下午|中午|凌晨|早上|晚上)?\s*([0-9]{1,2})\s*[:：时]\s*([0-9]{1,2})/g;

// ---------------- 基础工具：归一化 / 码点统计 ----------------

// NFKC 精简版：全角 ASCII 区 U+FF01~U+FF5E -> 半角，￥(U+FFE5) -> ¥；其余原样保留
export function nfkcLite(text: string): string {
  let out = '';
  for (const ch of text) {
    const cp = ch.codePointAt(0) ?? 0;
    if (cp >= 0xFF01 && cp <= 0xFF5E) {
      out += String.fromCharCode(cp - 0xFEE0);
    } else if (cp === 0xFFE5) {
      out += '¥';
    } else {
      out += ch;
    }
  }
  return out;
}

// Python str.isspace() 的等价码点集合（含 \x1c-\x1f、\x85、全角空格等）
function isSpaceCp(cp: number): boolean {
  if (cp === 0x20 || (cp >= 0x09 && cp <= 0x0d)) {
    return true;
  }
  if (cp >= 0x1c && cp <= 0x1f) {
    return true;
  }
  if (cp === 0x85 || cp === 0xa0 || cp === 0x1680) {
    return true;
  }
  if (cp >= 0x2000 && cp <= 0x200a) {
    return true;
  }
  return cp === 0x2028 || cp === 0x2029 || cp === 0x202f || cp === 0x205f || cp === 0x3000;
}

// nfkcLite + 去全部空白（码点遍历，与训练侧 squeeze 一致）
export function squeezeText(text: string): string {
  if (text.length === 0) {
    return '';
  }
  let out = '';
  for (const ch of nfkcLite(text)) {
    const cp = ch.codePointAt(0) ?? 0;
    if (!isSpaceCp(cp)) {
      out += ch;
    }
  }
  return out;
}

// 码点长度（等价 Python len()）
function codePointLen(s: string): number {
  let n = 0;
  for (const ch of s) {
    n++;
  }
  return n;
}

// CJK 字符数（按码点）
function cjkCount(text: string): number {
  let n = 0;
  for (const ch of text) {
    const cp = ch.codePointAt(0) ?? 0;
    if (cp >= 0x4e00 && cp <= 0x9fff) {
      n++;
    }
  }
  return n;
}

// 中位数（偶数个取中间两值平均，与 np.median 一致）
export function medianHeight(heights: number[]): number {
  const sorted = heights.slice().sort((a: number, b: number): number => a - b);
  const n = sorted.length;
  if (n === 0) {
    return 0;
  }
  if (n % 2 === 1) {
    return sorted[(n - 1) / 2];
  }
  return (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
}

// 阅读序：按 (top, left, 原始下标) 排序（显式 idx 决胜，两端一致）
export function readingOrder(blocks: BillModelBlock[]): number[] {
  const idx: number[] = [];
  for (let i = 0; i < blocks.length; i++) {
    idx.push(i);
  }
  idx.sort((p: number, q: number): number => {
    if (blocks[p].top !== blocks[q].top) {
      return blocks[p].top - blocks[q].top;
    }
    if (blocks[p].left !== blocks[q].left) {
      return blocks[p].left - blocks[q].left;
    }
    return p - q;
  });
  return idx;
}

// ---------------- 特征 ----------------

// 块特征（23 维，顺序与训练侧 BLOCK_FEATURES 完全一致）
export function blockFeatures(block: BillModelBlock, medH: number, orderPos: number): number[] {
  const sq = squeezeText(block.text);
  const cpLen = codePointLen(sq);
  const n = Math.max(1, cpLen);
  let digit = 0;
  let cjk = 0;
  for (const ch of sq) {
    const cp = ch.codePointAt(0) ?? 0;
    if (cp >= 0x30 && cp <= 0x39) {
      digit++;
    }
    if (cp >= 0x4e00 && cp <= 0x9fff) {
      cjk++;
    }
  }
  const nums = sq.match(NUM_SEQ_RE);
  const numCount = nums === null ? 0 : nums.length;
  const h = Math.max(1e-6, block.bottom - block.top);
  const cx = (block.left + block.right) / 2;
  return [
    Math.min(cpLen, 80) / 80.0,
    digit / n,
    cjk / n,
    (sq.includes('¥') || sq.includes('￥')) ? 1.0 : 0.0,
    SIGN_RE.test(sq) ? 1.0 : 0.0,
    DECIMAL_RE.test(sq) ? 1.0 : 0.0,
    Math.min(numCount, 5) / 5.0,
    TIME_RE.test(sq) ? 1.0 : 0.0,
    DATE_RE.test(sq) ? 1.0 : 0.0,
    AMOUNT_WORD_RE.test(sq) ? 1.0 : 0.0,
    cx,
    (block.top + block.bottom) / 2,
    block.right - block.left,
    h,
    Math.min(h / Math.max(1e-6, medH), 5.0),
    orderPos,
    block.left,
    1.0 - block.right,
    Math.abs(cx - 0.5) < 0.08 ? 1.0 : 0.0,
    (1.0 - block.right) < 0.08 ? 1.0 : 0.0,
    Math.min(cjk, 20) / 20.0,
    (cpLen > 0 && PURE_NUM_RE.test(sq) && !TIME_RE.test(sq) && !DATE_RE.test(sq)) ? 1.0 : 0.0,
    sq.includes('+') ? 1.0 : 0.0,
  ];
}

function toPairInput(block: BillModelBlock, feats: number[]): BillPairInput {
  return {
    left: block.left,
    top: block.top,
    right: block.right,
    bottom: block.bottom,
    digitRatio: feats[1],
    textLen: feats[0],
  };
}

// 配对特征（9 维，顺序与训练侧 PAIR_FEATURES 完全一致）
export function pairFeatures(a: BillPairInput, b: BillPairInput, medH: number): number[] {
  const vGap = b.top - a.bottom;
  const ha = Math.max(1e-6, a.bottom - a.top);
  const hb = Math.max(1e-6, b.bottom - b.top);
  const cya = (a.top + a.bottom) / 2;
  const cyb = (b.top + b.bottom) / 2;
  return [
    Math.max(-5.0, Math.min(5.0, vGap / Math.max(1e-6, medH))),
    Math.min(hb / ha, 5.0),
    Math.abs(cyb - cya),
    Math.abs(cyb - cya) < 0.5 * Math.min(ha, hb) ? 1.0 : 0.0,
    Math.abs((b.left + b.right) / 2 - (a.left + a.right) / 2),
    Math.abs(b.left - a.left) < 0.02 ? 1.0 : 0.0,
    Math.abs(b.digitRatio - a.digitRatio),
    Math.min(b.textLen / Math.max(1.0, a.textLen), 3.0),
    Math.max(-3.0, Math.min(3.0, vGap / ha)),
  ];
}

// ---------------- 模型推理 ----------------

// HGB 单棵树：从根走到叶，返回叶子值
function hgbTreeValue(nodes: BillHgbNode[], feats: number[]): number {
  let i = 0;
  let guard = 0;
  while (guard < 100000) {
    guard++;
    const nd = nodes[i];
    if (nd === undefined) {
      return 0;
    }
    if (nd.leaf) {
      return nd.value;
    }
    const x = feats[nd.feature] ?? 0;
    i = x <= nd.threshold ? nd.left : nd.right;
  }
  return 0;
}

// HGB 概率：raw = baseline + Σ 各迭代各类别树的叶子值，再 softmax
export function hgbPredictProba(model: BillHgbModel, feats: number[]): number[] {
  const nC = model.classes.length;
  const raw: number[] = [];
  for (let c = 0; c < nC; c++) {
    raw.push(model.baseline[c] ?? 0);
  }
  for (const iterTrees of model.trees) {
    for (let c = 0; c < nC; c++) {
      const nodes = iterTrees[c];
      if (nodes === undefined) {
        continue;
      }
      raw[c] += hgbTreeValue(nodes, feats);
    }
  }
  let mx = raw.length > 0 ? raw[0] : 0;
  for (let c = 1; c < raw.length; c++) {
    if (raw[c] > mx) {
      mx = raw[c];
    }
  }
  let sum = 0;
  const probs: number[] = [];
  for (let c = 0; c < raw.length; c++) {
    const e = Math.exp(raw[c] - mx);
    probs.push(e);
    sum += e;
  }
  for (let c = 0; c < probs.length; c++) {
    probs[c] = probs[c] / sum;
  }
  return probs;
}

// 概率数组取 argmax 对应类别名（并列取最前，与 numpy argmax 一致）
export function argmaxLabel(classes: string[], probs: number[]): string {
  let best = 0;
  for (let c = 1; c < probs.length; c++) {
    if (probs[c] > probs[best]) {
      best = c;
    }
  }
  return classes[best];
}

// 配对决策树：返回 "same" / "diff"
export function dtPredictLabel(root: BillDtNode, feats: number[]): string {
  let cur: BillDtNode | null = root;
  let guard = 0;
  while (cur !== null && !cur.leaf && guard < 10000) {
    guard++;
    const node: BillDtNode = cur;
    const fi = node.feature;
    const x: number = fi >= 0 && fi < feats.length ? feats[fi] : 0;
    cur = x <= node.threshold ? node.left : node.right;
  }
  if (cur === null) {
    return 'diff';
  }
  return cur.label;
}

// ---------------- 金额抽取 ----------------

// 从文本抽取金额：取"带符号/带¥/带小数"加权得分最高的匹配；返回 null 表示无金额
export function extractAmount(text: string): BillAmountMatch | null {
  const sq = squeezeText(text);
  const matches = sq.match(NUM_IN_TEXT_RE);
  if (matches === null) {
    return null;
  }
  let found = false;
  let bestScore = 0;
  let bestValue = 0;
  let bestSign = '';
  for (const raw of matches) {
    const cleaned = raw.replace(STRIP_AMOUNT_RE, '');
    const val = parseFloat(cleaned);
    const hasSign = raw.charAt(0) === '+' || raw.charAt(0) === '-';
    const hasYuan = raw.includes('¥') || raw.includes('￥');
    const score = (hasSign ? 2 : 0) + (hasYuan ? 1 : 0) + (raw.includes('.') ? 1 : 0);
    if (!found || score > bestScore) {
      found = true;
      bestScore = score;
      bestValue = val;
      bestSign = hasSign ? raw.charAt(0) : '';
    }
  }
  if (!found) {
    return null;
  }
  return { value: bestValue, sign: bestSign };
}

// ---------------- 时间抽取（与训练侧逐位一致） ----------------

// 儒略日序号：y-m-d 距 1970-01-01 的天数（纯整数运算）
export function daysFromCivil(y: number, m: number, d: number): number {
  const y2 = m <= 2 ? y - 1 : y;
  const era = Math.floor((y2 >= 0 ? y2 : y2 - 399) / 400);
  const yoe = y2 - era * 400;
  const doy = Math.floor((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1;
  const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
  return era * 146097 + doe - 719468;
}

// daysFromCivil 的逆运算
export function civilFromDays(z: number): BillYmd {
  const zz = z + 719468;
  const era = Math.floor((zz >= 0 ? zz : zz - 146096) / 146097);
  const doe = zz - era * 146097;
  const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
  const y = yoe + era * 400;
  const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
  const mp = Math.floor((5 * doy + 2) / 153);
  const d = doy - Math.floor((153 * mp + 2) / 5) + 1;
  const m = mp < 10 ? mp + 3 : mp - 9;
  return { y: y + (m <= 2 ? 1 : 0), m: m, d: d };
}

// 本地时区的 (y,m,d,hh,mm) -> 毫秒时间戳
function localMs(y: number, m: number, d: number, hh: number, mm: number): number {
  return new Date(y, m - 1, d, hh, mm, 0, 0).getTime();
}

// 字符是否为数字（用于匹配边界检查）
function isDigitCh(ch: string): boolean {
  return ch >= '0' && ch <= '9';
}

// 字符是否为日期匹配的禁邻字符（分隔符/货币符）
function isSepCh(ch: string): boolean {
  return '-/.¥￥'.indexOf(ch) >= 0;
}

/**
 * 从文本抽取支付时间。返回 (毫秒时间戳, 是否含日期)；无法解析返回 null。
 * 优先级：绝对日期 > 今天/昨天/前天 > 星期X > 粘连月日+时钟 > M月D日 > M-D/M.D/M/D。
 * 年份规则：月日形式取当前年，晚于 now 一天以上视为去年；星期X 取过去 7 天内。
 * 只有时刻：取今天，若在未来（超 now 一分钟）视为昨天；只有日期：时刻取 00:00。
 * 在 nfkcLite 后（保留空格）的文本上匹配，避免 squeeze 把"10-01 14:30"粘连。
 */
export function extractPayTime(text: string, nowMs: number): BillPayTime | null {
  const t = nfkcLite(text);
  if (t.length === 0) {
    return null;
  }
  const nowDate = new Date(nowMs);
  const ny = nowDate.getFullYear();
  const nm = nowDate.getMonth() + 1;
  const ndd = nowDate.getDate();
  const nowDays = daysFromCivil(ny, nm, ndd);

  // ---- 日期部分 ----
  let dateDays: number | null = null;
  let gluedHh: number | null = null;
  let gluedMm: number | null = null;
  const m3 = ABS_DATE_RE.exec(t);
  if (m3 !== null) {
    const y = parseInt(m3[1], 10);
    const mo = parseInt(m3[2], 10);
    const d = parseInt(m3[3], 10);
    if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
      dateDays = daysFromCivil(y, mo, d);
    }
  }
  if (dateDays === null) {
    const m2 = REL_DATE_RE.exec(t);
    if (m2 !== null) {
      const w = m2[0];
      dateDays = nowDays + (w === '今天' ? 0 : (w === '昨天' ? -1 : -2));
    }
  }
  if (dateDays === null) {
    const m2 = WEEKDAY_RE.exec(t);
    if (m2 !== null) {
      const target = WEEKDAY_IDX[m2[1]] ?? -1;
      if (target >= 0) {
        const todayWd = (nowDays + 3) % 7;   // 1970-01-01 是周四：0=周一
        dateDays = nowDays - (((todayWd - target) % 7 + 7) % 7);
      }
    }
  }
  if (dateDays === null) {
    // 粘连的"月-日+时钟"：前后不能紧邻数字/分隔符/货币符（排除 ¥12-20 类金额）
    const m4 = GLUED_RE.exec(t);
    if (m4 !== null) {
      const s = m4.index;
      const e = s + m4[0].length;
      let ok = true;
      if (s > 0 && (isDigitCh(t.charAt(s - 1)) || isSepCh(t.charAt(s - 1)))) {
        ok = false;
      }
      if (e < t.length && isDigitCh(t.charAt(e))) {
        ok = false;
      }
      if (ok) {
        const mo = parseInt(m4[1], 10);
        const d = parseInt(m4[2], 10);
        const hh2 = parseInt(m4[3], 10);
        const mi2 = parseInt(m4[4], 10);
        if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31 && hh2 <= 23 && mi2 <= 59) {
          const year = daysFromCivil(ny, mo, d) <= nowDays + 1 ? ny : ny - 1;
          dateDays = daysFromCivil(year, mo, d);
          gluedHh = hh2;
          gluedMm = mi2;
        }
      }
    }
  }
  if (dateDays === null) {
    // M月D日：块首不能紧邻数字（排除 202410月01 之类的残片）
    const m2 = MD_MONTH_RE.exec(t);
    let mdOk = false;
    let moM = 0;
    let dM = 0;
    if (m2 !== null && !(m2.index > 0 && isDigitCh(t.charAt(m2.index - 1)))) {
      const mo = parseInt(m2[1], 10);
      const d = parseInt(m2[2], 10);
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        mdOk = true;
        moM = mo;
        dM = d;
      }
    }
    if (mdOk) {
      const year = daysFromCivil(ny, moM, dM) <= nowDays + 1 ? ny : ny - 1;
      dateDays = daysFromCivil(year, moM, dM);
    } else {
      // M-D / M.D / M/D：前后不能紧邻数字/分隔符/货币符
      // （数字=残片，分隔符=数值区间/版本号如 4.7/5/6，¥=金额如 ¥5.20）
      MD_SEP_ALL_RE.lastIndex = 0;
      let msep: RegExpExecArray | null = MD_SEP_ALL_RE.exec(t);
      while (dateDays === null && msep !== null) {
        const s = msep.index;
        const e = s + msep[0].length;
        if (s > 0 && (isDigitCh(t.charAt(s - 1)) || isSepCh(t.charAt(s - 1)))) {
          msep = MD_SEP_ALL_RE.exec(t);
          continue;
        }
        if (e < t.length && (isDigitCh(t.charAt(e)) || '-/.'.indexOf(t.charAt(e)) >= 0)) {
          msep = MD_SEP_ALL_RE.exec(t);
          continue;
        }
        const mo = parseInt(msep[1], 10);
        const d = parseInt(msep[2], 10);
        if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
          const year = daysFromCivil(ny, mo, d) <= nowDays + 1 ? ny : ny - 1;
          dateDays = daysFromCivil(year, mo, d);
        }
        msep = MD_SEP_ALL_RE.exec(t);
      }
    }
  }

  // ---- 时刻部分 ----
  let hh: number | null = null;
  let mm: number | null = null;
  if (gluedHh !== null) {
    hh = gluedHh;
    mm = gluedMm;
  } else {
    CLOCK_ALL_RE.lastIndex = 0;
    let mc: RegExpExecArray | null = CLOCK_ALL_RE.exec(t);
    while (hh === null && mc !== null) {
      const prefix = mc[1] ?? '';
      const h12 = parseInt(mc[2], 10);
      const mi = parseInt(mc[3], 10);
      if (mi <= 59) {
        if (prefix.length > 0) {
          if (h12 <= 12) {
            if (prefix === '下午' || prefix === '晚上' || prefix === '中午') {
              hh = h12 === 12 ? 12 : h12 + 12;
            } else if (prefix === '凌晨') {
              hh = h12 === 12 ? 0 : h12;
            } else {  // 上午 / 早上
              hh = h12 === 12 ? 0 : h12;
            }
            mm = mi;
          }
        } else {
          if (h12 <= 23) {
            hh = h12;
            mm = mi;
          }
        }
      }
      mc = CLOCK_ALL_RE.exec(t);
    }
  }

  if (dateDays === null && hh === null) {
    return null;
  }
  if (dateDays === null) {
    // 只有时刻：默认今天；超 now 一分钟视为昨天
    const ymdA = civilFromDays(nowDays);
    let ts = localMs(ymdA.y, ymdA.m, ymdA.d, hh as number, mm as number);
    if (ts > nowMs + 60000) {
      const ymdB = civilFromDays(nowDays - 1);
      ts = localMs(ymdB.y, ymdB.m, ymdB.d, hh as number, mm as number);
    }
    return { ms: ts, dated: false };
  }
  const ymd = civilFromDays(dateDays);
  const ms = localMs(ymd.y, ymd.m, ymd.d, hh === null ? 0 : hh, mm === null ? 0 : mm);
  return { ms: ms, dated: true };
}

// ---------------- 主流程 ----------------

// 块分类 -> 去 noise -> 相邻块分组 -> 合并启发式 -> 抽取金额/商户/置信度/时间
// nowMs：相对日期（今天/昨天/星期X）与无时间回退的基准时间戳（毫秒）
export function predictBillTransactions(model: BillModel, blocks: BillModelBlock[], nowMs: number): BillTxnPrediction[] {
  // 过滤空文本块（与训练侧 load_dataset 一致）
  const valid: BillModelBlock[] = [];
  for (const b of blocks) {
    if (b.text.length > 0 && b.text.trim().length > 0) {
      valid.push(b);
    }
  }
  if (valid.length === 0) {
    return [];
  }
  // 块高中位数（0 时回退 1e-6）
  const heights: number[] = [];
  for (const b of valid) {
    heights.push(b.bottom - b.top);
  }
  const medRaw = medianHeight(heights);
  const medH = medRaw === 0 ? 1e-6 : medRaw;
  // 阅读序 + 每块的序位置 0~1
  const order = readingOrder(valid);
  const orderPos: number[] = [];
  for (let i = 0; i < valid.length; i++) {
    orderPos.push(0);
  }
  const denom = Math.max(1, order.length - 1);
  for (let k = 0; k < order.length; k++) {
    orderPos[order[k]] = k / denom;
  }
  // 逐块特征 + 概率 + 预测类别
  const feats: number[][] = [];
  const probsArr: number[][] = [];
  const labels: string[] = [];
  for (let i = 0; i < valid.length; i++) {
    const f = blockFeatures(valid[i], medH, orderPos[i]);
    feats.push(f);
    const p = hgbPredictProba(model.blockHgb, f);
    probsArr.push(p);
    labels.push(argmaxLabel(model.blockHgb.classes, p));
  }
  const amtK = model.blockHgb.classes.indexOf('amount');
  const merK = model.blockHgb.classes.indexOf('merchant');
  // 去 noise 后按阅读序做相邻块分组
  const seq: number[] = [];
  for (const i of order) {
    if (labels[i] !== 'noise') {
      seq.push(i);
    }
  }
  const groups: number[][] = [];
  if (seq.length > 0) {
    let cur: number[] = [seq[0]];
    for (let k = 0; k + 1 < seq.length; k++) {
      const u = seq[k];
      const v = seq[k + 1];
      const pa = pairFeatures(toPairInput(valid[u], feats[u]), toPairInput(valid[v], feats[v]), medH);
      if (dtPredictLabel(model.pairTree, pa) === 'same') {
        cur.push(v);
      } else {
        groups.push(cur);
        cur = [v];
      }
    }
    groups.push(cur);
  }
  // 合并启发式：相邻组"有金额无商户"+"有商户无金额"多为同一笔被拆开
  const hasAmt = (g: number[]): boolean => g.some((i: number): boolean => labels[i] === 'amount');
  const hasMer = (g: number[]): boolean => g.some((i: number): boolean => labels[i] === 'merchant');
  const merged: number[][] = [];
  for (const g of groups) {
    if (merged.length > 0) {
      const pv = merged[merged.length - 1];
      const pvA = hasAmt(pv);
      const pvM = hasMer(pv);
      const cuA = hasAmt(g);
      const cuM = hasMer(g);
      if ((pvA && !pvM && cuM && !cuA) || (pvM && !pvA && cuA && !cuM)) {
        merged[merged.length - 1] = pv.concat(g);
        continue;
      }
    }
    merged.push(g);
  }
  // 每组抽取交易
  // ---- 时间解析（只对产出交易的组做；全局去重，阅读序先到先得）----
  // 候选顺序：组内块（time 预测优先，再其他非 amount 的时间/日期命中块，允许纯时刻）
  //   -> 组跨度内的洞（noise 块，必须带日期）-> 外圈逐距离（同距先上后下，必须带日期）
  const opos: number[] = [];
  for (let i = 0; i < valid.length; i++) {
    opos.push(0);
  }
  for (let k = 0; k < order.length; k++) {
    opos[order[k]] = k;
  }
  const usedTimeBlocks = new Set<number>();
  const isTimeText = (i: number): boolean => {
    const sq = squeezeText(valid[i].text);
    return TIME_RE.test(sq) || DATE_RE.test(sq);
  };
  const tryExtractTime = (i: number, needDate: boolean): BillPayTime | null => {
    if (usedTimeBlocks.has(i)) {
      return null;
    }
    const r = extractPayTime(valid[i].text, nowMs);
    if (r === null) {
      return null;
    }
    if (needDate && !r.dated) {
      return null;
    }
    return r;
  };
  const resolveGroupTime = (g: number[]): BillTimeResolve | null => {
    if (g.length === 0) {
      return null;
    }
    const inGroup = g.slice().sort((a: number, b: number): number => opos[a] - opos[b]);
    const cands: number[] = [];
    for (const i of inGroup) {
      if (labels[i] === 'time') {
        cands.push(i);
      }
    }
    for (const i of inGroup) {
      if (labels[i] !== 'time' && labels[i] !== 'amount' && isTimeText(i)) {
        cands.push(i);
      }
    }
    for (const i of cands) {
      const r = tryExtractTime(i, false);
      if (r !== null) {
        return { ms: r.ms, hitIdx: i };
      }
    }
    let lo = opos[g[0]];
    let hi = opos[g[0]];
    for (const i of g) {
      if (opos[i] < lo) {
        lo = opos[i];
      }
      if (opos[i] > hi) {
        hi = opos[i];
      }
    }
    const gset = new Set<number>(g);
    // 组内洞：跨度内不属于本组的块（noise），需带日期
    for (let p = lo; p <= hi; p++) {
      const j = order[p];
      if (gset.has(j) || labels[j] === 'amount') {
        continue;
      }
      if (isTimeText(j)) {
        const r = tryExtractTime(j, true);
        if (r !== null) {
          return { ms: r.ms, hitIdx: j };
        }
      }
    }
    // 外圈：按距离扩展，同距先上后下，需带日期
    for (let dist = 1; dist <= 8; dist++) {
      const ring: number[] = [];
      if (lo - dist >= 0) {
        ring.push(order[lo - dist]);
      }
      if (hi + dist < order.length) {
        ring.push(order[hi + dist]);
      }
      for (const j of ring) {
        if (labels[j] === 'amount') {
          continue;
        }
        if (labels[j] === 'time' || isTimeText(j)) {
          const r = tryExtractTime(j, true);
          if (r !== null) {
            return { ms: r.ms, hitIdx: j };
          }
        }
      }
    }
    return null;
  };
  const out: BillTxnPrediction[] = [];
  for (const g of merged) {
    let amtVal: number | null = null;
    let sign = '';
    let merText: string | null = null;
    let amtIdx = -1;
    let merIdx = -1;
    let hasAmountPred = false;
    for (const i of g) {
      if (labels[i] === 'amount') {
        hasAmountPred = true;
        if (amtVal === null) {
          const m = extractAmount(valid[i].text);
          amtVal = m === null ? null : m.value;
          sign = m === null ? '' : m.sign;
          amtIdx = i;
        }
      }
      if (labels[i] === 'merchant' && merText === null) {
        merText = valid[i].text;
        merIdx = i;
      }
    }
    // 回退：组内无 amount 预测块时，找含 ¥ / 带符号小数的强金额文本
    let amountFromFallback = false;
    if (amtVal === null) {
      for (const i of g) {
        const sq = squeezeText(valid[i].text);
        if (sq.includes('¥') || sq.includes('￥') || STRONG_AMOUNT_RE.test(sq)) {
          const m = extractAmount(valid[i].text);
          if (m !== null) {
            amtVal = m.value;
            sign = m.sign;
            amtIdx = i;
            amountFromFallback = true;
            break;
          }
        }
      }
    }
    // 商户回退：组内非金额/时间/分类块中取 CJK 最多的（并列取最前）
    if (merText === null) {
      const cands: number[] = [];
      for (const i of g) {
        if (labels[i] !== 'amount' && labels[i] !== 'time' && labels[i] !== 'category') {
          cands.push(i);
        }
      }
      if (cands.length > 0) {
        let bestI = cands[0];
        let bestCjk = cjkCount(valid[bestI].text);
        for (let k = 1; k < cands.length; k++) {
          const c = cjkCount(valid[cands[k]].text);
          if (c > bestCjk) {
            bestCjk = c;
            bestI = cands[k];
          }
        }
        merIdx = bestI;
        merText = valid[merIdx].text;
      }
    }
    // 出账条件：抽到金额，且（有 amount 预测块 或 有商户文本）
    if (amtVal !== null && (hasAmountPred || merText !== null)) {
      let conf = amtIdx >= 0 && amtIdx < probsArr.length ? probsArr[amtIdx][amtK] : 0;
      if (merText !== null && merIdx >= 0) {
        conf = (conf + probsArr[merIdx][merK]) / 2.0;
      } else {
        conf *= 0.8;
      }
      if (amountFromFallback) {
        conf *= 0.5;
      }
      // 时间解析：仅对产出交易的组做（组内候选 + 洞 + 外圈，全局去重）
      const resolved = resolveGroupTime(g);
      let payMs = nowMs;
      if (resolved !== null) {
        usedTimeBlocks.add(resolved.hitIdx);
        payMs = resolved.ms;
      }
      const amountAbs = Math.abs(amtVal);
      const merchant = (merText ?? '').trim();
      const dup = out.some((o: BillTxnPrediction): boolean => o.amount === amountAbs && o.merchant === merchant);
      if (!dup) {
        out.push({ amount: amountAbs, merchant: merchant, isIncome: sign === '+', confidence: conf, payTime: payMs });
      }
    }
  }
  return out;
}

// ---------------- 模型加载 ----------------

function copyDtNode(rawNode: BillDtNodeRaw): BillDtNode {
  const leftRaw = rawNode.left;
  const rightRaw = rawNode.right;
  const leftCopy = leftRaw === undefined ? null : copyDtNode(leftRaw);
  const rightCopy = rightRaw === undefined ? null : copyDtNode(rightRaw);
  return {
    leaf: rawNode.leaf === true,
    label: rawNode.label ?? '',
    feature: rawNode.feature ?? -1,
    threshold: rawNode.threshold ?? 0,
    left: leftCopy,
    right: rightCopy,
  };
}

// 解析 model.json：JSON.parse 边界做一次 as，随后深拷贝为严格模型；失败返回 null
export function parseBillModel(jsonText: string): BillModel | null {
  try {
    const raw = JSON.parse(jsonText) as BillModelRaw;
    const hgbRaw = raw.blockClassifierHgb;
    const pairRaw = raw.pairClassifier;
    if (hgbRaw === undefined || pairRaw === undefined) {
      return null;
    }
    const classes = hgbRaw.classes;
    const baseline = hgbRaw.baseline;
    const treesRaw = hgbRaw.trees;
    const pairTreeRaw = pairRaw.tree;
    if (classes === undefined || baseline === undefined || treesRaw === undefined || pairTreeRaw === undefined) {
      return null;
    }
    if (classes.indexOf('amount') < 0 || classes.indexOf('merchant') < 0 || classes.indexOf('noise') < 0) {
      return null;
    }
    const classesCopy: string[] = [];
    for (const c of classes) {
      classesCopy.push(c);
    }
    const baselineCopy: number[] = [];
    for (const v of baseline) {
      baselineCopy.push(v ?? 0);
    }
    const trees: BillHgbNode[][][] = [];
    for (const iterTrees of treesRaw) {
      const byClass: BillHgbNode[][] = [];
      for (const nodesRaw of iterTrees) {
        const nodes: BillHgbNode[] = [];
        for (const ndRaw of nodesRaw) {
          nodes.push({
            leaf: ndRaw.leaf === true,
            value: ndRaw.value ?? 0,
            feature: ndRaw.feature ?? -1,
            threshold: ndRaw.threshold ?? 0,
            missingLeft: ndRaw.missingLeft === true,
            left: ndRaw.left ?? 0,
            right: ndRaw.right ?? 0,
          });
        }
        byClass.push(nodes);
      }
      trees.push(byClass);
    }
    return {
      blockHgb: { classes: classesCopy, baseline: baselineCopy, trees: trees },
      pairTree: copyDtNode(pairTreeRaw),
    };
  } catch (err) {
    return null;
  }
}
