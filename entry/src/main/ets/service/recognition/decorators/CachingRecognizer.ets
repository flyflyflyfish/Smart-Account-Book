import fs from '@ohos.file.fs';
import { RecognitionResult, copyRecognitionResult } from '../../../models/recognition/RecognitionResult';
import { Recognizer } from '../Recognizer';

// FNV-1a 哈希初始值（32 位）
const FNV_OFFSET_BASIS: number = 2166136261;
// FNV-1a 哈希质数
const FNV_PRIME: number = 16777619;

/**
 * 缓存识别器：按图片内容哈希缓存识别结果，命中则跳过底层识别
 */
export class CachingRecognizer implements Recognizer {
  private inner: Recognizer;
  private cache: Map<string, RecognitionResult[]> = new Map();
  private maxSize: number;
  private hashFn: (uri: string) => Promise<string>;

  constructor(inner: Recognizer, maxSize: number, hashFn?: (uri: string) => Promise<string>) {
    this.inner = inner;
    this.maxSize = maxSize;
    // 默认按图片文件内容哈希，测试可注入固定哈希
    this.hashFn = hashFn ? hashFn : (uri: string): Promise<string> => this.hashFile(uri);
  }

  async recognize(imageUri: string): Promise<RecognitionResult[]> {
    const key = await this.hashFn(imageUri);
    const cached = this.cache.get(key);
    if (cached) {
      // 返回副本：调用方（识别流水线）会就地修改结果，不能污染缓存
      return this.copyResults(cached);
    }
    const results = await this.inner.recognize(imageUri);
    this.put(key, this.copyResults(results));
    return results;
  }

  private copyResults(results: RecognitionResult[]): RecognitionResult[] {
    const copies: RecognitionResult[] = [];
    for (const r of results) {
      copies.push(copyRecognitionResult(r));
    }
    return copies;
  }

  // 读文件字节做 FNV-1a 哈希，作为缓存键（内容相同则键相同）
  private async hashFile(uri: string): Promise<string> {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      const read = fs.readSync(file.fd, buffer);
      const bytes = new Uint8Array(buffer, 0, read);
      let hash = FNV_OFFSET_BASIS;
      for (let i = 0; i < bytes.length; i++) {
        hash ^= bytes[i];
        hash = (hash * FNV_PRIME) >>> 0;
      }
      return 'fnv1a_' + hash.toString();
    } finally {
      fs.closeSync(file);
    }
  }

  // 超过上限时淘汰最早插入的条目
  private put(key: string, results: RecognitionResult[]): void {
    if (this.cache.size >= this.maxSize) {
      const firstKey = Array.from(this.cache.keys())[0];
      this.cache.delete(firstKey);
    }
    this.cache.set(key, results);
  }
}
