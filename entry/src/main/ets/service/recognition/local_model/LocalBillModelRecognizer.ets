import util from '@ohos.util';
import { AccountType } from '../../../models/account/account';
import { RecognitionResult } from '../../../models/recognition/RecognitionResult';
import { Recognizer } from '../Recognizer';
import { LocalOcrRecognizer } from '../LocalOcrRecognizer';
import {
  BillModel,
  BillModelBlock,
  BillTxnPrediction,
  parseBillModel,
  predictBillTransactions
} from './BillModelCore';
import { Logger } from '../../../utils/Logger';

// 模型文件：打包在 rawfile 里的自训小模型（ml_tools/train_model.py 导出）
const MODEL_FILE: string = 'bill_model.json';
// 模型加载缓存：rawfile 只读，解析一次全局复用（undefined=未加载，null=加载失败）
let cachedModel: BillModel | null | undefined = undefined;

/**
 * 本地账单识别器（阶段5）：端侧 OCR 文本块 + 自训练小模型抽取交易。
 * 流程：recognizeBlocks（相对坐标文本块）-> predictBillTransactions（块分类/分组/抽取）。
 * 模型文件缺失或解析失败时抛错，交给 FallbackRecognizer 降级（云端大模型或纯 OCR 规则）。
 * 时间不由模型抽取：图上时间块仅参与分组，payTime 先取当前时间，由用户在确认页调整。
 */
export class LocalBillModelRecognizer implements Recognizer {
  async recognize(imageUri: string): Promise<RecognitionResult[]> {
    const model = this.loadModel();
    if (model === null) {
      throw new Error('local bill model unavailable');
    }
    const vision = await new LocalOcrRecognizer().recognizeBlocks(imageUri);
    const blocks: BillModelBlock[] = vision.blocks;
    const txns: BillTxnPrediction[] = predictBillTransactions(model, blocks);
    const out: RecognitionResult[] = [];
    for (const t of txns) {
      out.push({
        accountType: t.isIncome ? AccountType.INCOME : AccountType.EXPENSES,
        amount: t.amount,
        merchant: t.merchant,
        payTime: Date.now(),
        categoryName: '',
        confidence: t.confidence,
        isBill: true
      });
    }
    if (out.length === 0) {
      Logger.warn('本地模型未从图中抽取到交易', `blocks=${blocks.length}`);
    }
    return out;
  }

  // 惰性加载并缓存模型（rawfile 同步读取 + 一次 JSON 解析）
  private loadModel(): BillModel | null {
    if (cachedModel !== undefined) {
      return cachedModel;
    }
    try {
      const content: Uint8Array = getContext().resourceManager.getRawFileContentSync(MODEL_FILE);
      const decoder = util.TextDecoder.create('utf-8');
      cachedModel = parseBillModel(decoder.decodeToString(content));
      if (cachedModel === null) {
        Logger.error('本地账单模型解析失败', MODEL_FILE);
      }
    } catch (err) {
      Logger.error('本地账单模型读取失败', (err as Error).message);
      cachedModel = null;
    }
    return cachedModel;
  }
}
