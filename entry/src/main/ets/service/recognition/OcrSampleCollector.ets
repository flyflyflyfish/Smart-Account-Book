import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import { AccountType } from '../../models/account/account';
import { RecognitionResult } from '../../models/recognition/RecognitionResult';
import { OcrVisionResult, SampleSummary, SampleTransaction, TrainingSample } from '../../models/recognition/OcrSample';
import { LocalOcrRecognizer } from './LocalOcrRecognizer';
import CloudLlmConfigStore from './CloudLlmConfigStore';
import { Logger } from '../../utils/Logger';

// 训练样本本地存储文件名：一行一个 JSON 对象（JSON Lines），便于增量追加
const SAMPLES_FILE_NAME: string = 'ocr_samples.jsonl';

// 识别阶段缓存的待确认样本：OCR 结果 + 大模型原始输出（入账时取用）
interface PendingSample {
  ocr: OcrVisionResult;
  raws: RecognitionResult[];
}

/**
 * 训练数据采集器（阶段1）：
 * 识别时并行跑端侧 OCR 并缓存（OCR 块 + 大模型原始输出），
 * 用户在确认页入账后，把 {图片宽高, OCR 文本块, 大模型原始输出, 用户确认结果} 落盘到本机沙箱。
 * 任何采集失败都不影响识别主流程，只记日志，绝不抛出。
 */
class OcrSampleCollector {
  // 识别阶段缓存：uri -> {ocr, raws}，入账时取用；未入账的残留由 clearPending 清理
  private pending: Map<string, PendingSample> = new Map();

  // 是否开启采集（设置页开关，默认关闭）
  async isEnabled(): Promise<boolean> {
    return CloudLlmConfigStore.loadTrainCollectEnabled();
  }

  private samplesPath(context: common.Context): string {
    return `${context.filesDir}/${SAMPLES_FILE_NAME}`;
  }

  // 并行本地 OCR：关闭时立即返回 null；OCR 失败也返回 null，绝不抛给主流程
  async collectOcr(imageUri: string): Promise<OcrVisionResult | null> {
    if (!(await this.isEnabled())) {
      return null;
    }
    try {
      return await new LocalOcrRecognizer().recognizeBlocks(imageUri);
    } catch (error) {
      Logger.error('采集训练数据：端侧 OCR 失败', (error as Error).message);
      return null;
    }
  }

  // 识别阶段：缓存 OCR 块 + 大模型原始输出（不落盘，等用户入账确认后由 appendConfirmed 落盘）
  cache(uri: string, ocr: OcrVisionResult, raws: RecognitionResult[]): void {
    this.pending.set(uri, { ocr: ocr, raws: raws });
  }

  // 入账阶段：把「OCR 块 + 大模型原始输出 + 用户确认结果」落盘。
  // confirmed 为用户在确认页最终入账的字段（人工真值，训练用它当标签）。无缓存则忽略
  appendConfirmed(context: common.Context, uri: string, confirmed: SampleTransaction[]): void {
    const cached = this.pending.get(uri);
    if (!cached) {
      return;
    }
    this.pending.delete(uri);
    try {
      const sample: TrainingSample = {
        width: cached.ocr.width,
        height: cached.ocr.height,
        ocrBlocks: cached.ocr.blocks,
        transactions: cached.raws.map((t: RecognitionResult): SampleTransaction => this.toTransaction(t)),
        confirmed: confirmed,
        capturedAt: Date.now()
      };
      const line = JSON.stringify(sample) + '\n';
      const file = fs.openSync(this.samplesPath(context),
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.APPEND);
      try {
        fs.writeSync(file.fd, line);
      } finally {
        fs.closeSync(file);
      }
    } catch (error) {
      Logger.error('采集训练数据：写入失败', (error as Error).message);
    }
  }

  // 清理未入账的残留缓存（识别页退出时调用，避免内存残留）
  clearPending(): void {
    this.pending.clear();
  }

  private toTransaction(result: RecognitionResult): SampleTransaction {
    return {
      accountType: result.accountType === AccountType.INCOME ? '收入' : '支出',
      amount: result.amount,
      merchant: result.merchant,
      payTime: result.payTime,
      categoryName: result.categoryName,
      confidence: result.confidence
    };
  }

  // 当前已采集样本数
  async sampleCount(context: common.Context): Promise<number> {
    try {
      const path = this.samplesPath(context);
      if (!fs.accessSync(path)) {
        return 0;
      }
      const content = fs.readTextSync(path);
      return content.split('\n').filter((line: string): boolean => line.trim().length > 0).length;
    } catch (error) {
      Logger.error('统计训练样本失败', (error as Error).message);
      return 0;
    }
  }

  // 导出全部样本为 JSON 数组，写入指定 uri（系统保存选择器返回），返回导出条数
  async exportTo(context: common.Context, uri: string): Promise<number> {
    const samples: TrainingSample[] = [];
    try {
      const path = this.samplesPath(context);
      if (fs.accessSync(path)) {
        const content = fs.readTextSync(path);
        const lines = content.split('\n').filter((line: string): boolean => line.trim().length > 0);
        for (const line of lines) {
          try {
            samples.push(JSON.parse(line) as TrainingSample);
          } catch (error) {
            Logger.error('采集训练数据：解析一行失败，已跳过', (error as Error).message);
          }
        }
      }
    } catch (error) {
      Logger.error('读取训练样本失败', (error as Error).message);
    }
    const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, JSON.stringify(samples));
    } finally {
      fs.closeSync(file);
    }
    return samples.length;
  }

  // 列出全部样本摘要（供设置页逐条查看/删除），不加载全量内容
  async listSamples(context: common.Context): Promise<SampleSummary[]> {
    const result: SampleSummary[] = [];
    try {
      const path = this.samplesPath(context);
      if (!fs.accessSync(path)) {
        return result;
      }
      const content = fs.readTextSync(path);
      const lines = content.split('\n').filter((line: string): boolean => line.trim().length > 0);
      let idx = 0;
      for (const line of lines) {
        idx++;
        try {
          const sample = JSON.parse(line) as TrainingSample;
          result.push(this.toSummary(idx, sample));
        } catch (error) {
          Logger.error('采集训练数据：解析一行失败，已跳过', (error as Error).message);
        }
      }
    } catch (error) {
      Logger.error('读取训练样本列表失败', (error as Error).message);
    }
    return result;
  }

  private toSummary(index: number, sample: TrainingSample): SampleSummary {
    // 优先用人工确认结果（confirmed）做摘要，缺失则回退到大模型原始输出（transactions）
    const confirmed = sample.confirmed ?? [];
    const source = confirmed.length > 0 ? confirmed : sample.transactions;
    let preview = '';
    if (source.length > 0) {
      const first = source[0];
      if (first.amount > 0) {
        preview = '¥' + first.amount.toFixed(2);
      }
      if (first.merchant.length > 0) {
        preview = preview.length > 0 ? `${preview} ${first.merchant}` : first.merchant;
      }
    }
    if (preview.length === 0) {
      preview = '无交易';
    }
    return {
      index: index,
      capturedAt: sample.capturedAt,
      lineCount: sample.ocrBlocks.length,
      txnCount: source.length,
      txnPreview: preview
    };
  }

  // 删除第 index 条（1-based，与 listSamples 的 index 一致）；越界或文件不存在则忽略
  async deleteSample(context: common.Context, index: number): Promise<void> {
    try {
      const path = this.samplesPath(context);
      if (!fs.accessSync(path)) {
        return;
      }
      const content = fs.readTextSync(path);
      const lines = content.split('\n').filter((line: string): boolean => line.trim().length > 0);
      if (index < 1 || index > lines.length) {
        return;
      }
      lines.splice(index - 1, 1);
      if (lines.length === 0) {
        fs.unlinkSync(path);
        return;
      }
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, lines.join('\n') + '\n');
      } finally {
        fs.closeSync(file);
      }
    } catch (error) {
      Logger.error('删除训练样本失败', (error as Error).message);
    }
  }

  // 清空全部样本（删除本地文件）
  async clearAll(context: common.Context): Promise<void> {
    try {
      const path = this.samplesPath(context);
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      Logger.error('清空训练样本失败', (error as Error).message);
    }
  }
}

export default new OcrSampleCollector();
