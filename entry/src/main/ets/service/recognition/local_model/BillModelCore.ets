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

// ---------------- 主流程 ----------------

// 块分类 -> 去 noise -> 相邻块分组 -> 合并启发式 -> 抽取金额/商户/置信度
export function predictBillTransactions(model: BillModel, blocks: BillModelBlock[]): BillTxnPrediction[] {
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
      const amountAbs = Math.abs(amtVal);
      const merchant = (merText ?? '').trim();
      const dup = out.some((o: BillTxnPrediction): boolean => o.amount === amountAbs && o.merchant === merchant);
      if (!dup) {
        out.push({ amount: amountAbs, merchant: merchant, isIncome: sign === '+', confidence: conf });
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
