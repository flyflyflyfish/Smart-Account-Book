import { BillDraft } from './BillDraft';

/**
 * 单张图片的识别任务状态
 */
export enum ImageTaskStatus {
  PENDING,
  RECOGNIZING,
  SUCCESS,
  FAILED
}

/**
 * 批量识别中单张图片的任务：承载进度状态与识别出的账单草稿
 */
export class ImageTask {
  uri: string = '';
  status: ImageTaskStatus = ImageTaskStatus.PENDING;
  // 失败时的可读错误信息
  error: string = '';
  // 识别出的账单草稿（成功时填充）
  drafts: BillDraft[] = [];
}
