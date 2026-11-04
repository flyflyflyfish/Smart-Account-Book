import router from '@ohos.router';
import dayjs from 'dayjs';
import cameraPicker from '@ohos.multimedia.cameraPicker';
import camera from '@ohos.multimedia.camera';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import AccountNavigator from '../components/Navigator';
import AccountTypeModel from '../models/accountType/AccountTypeModel';
import CategoryRegistry from '../models/accountType/CategoryRegistry';
import { AccountInfo, AccountType } from '../models/account/account';
import { BillDraft } from '../models/recognition/BillDraft';
import { ImageTask, ImageTaskStatus } from '../models/recognition/ImageTask';
import { RecognizerFactory } from '../service/recognition/RecognizerFactory';
import { Recognizer } from '../service/recognition/Recognizer';
import CloudLlmConfigStore from '../service/recognition/CloudLlmConfigStore';
import { RecognitionPipeline } from '../service/recognition/pipeline/RecognitionPipeline';
import learnedClassifier from '../service/recognition/classifier/LearnedClassifier';
import AccountService from '../service/account';
import { PREF_LEDGER_SYNC_BILLS, SOURCE_IMAGE } from '../common/constants';
import PreferenceUtil from '../utils/PreferenceUtil';
import { MAX_PICK_IMAGES, RECOGNIZE_CONCURRENCY, RECOGNIZE_RETRY_MAX_ATTEMPTS, RECOGNIZE_RETRY_BASE_DELAY_MS } from '../common/Config';
import { CloudLlmRecognizer } from '../service/recognition/CloudLlmRecognizer';
import { RetryRecognizer } from '../service/recognition/decorators/RetryRecognizer';
import { isDuplicateBill } from '../common/dedup';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import LedgerRepository from '../data/LedgerRepository';
import LedgerStore from '../common/LedgerStore';
import { LEDGER_RECORD_EXPENSE, LEDGER_RECORD_INCOME } from '../models/ledger/Ledger';
import BreakpointConstants from '../common/breakpoint';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY, SPACE_XLARGE } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';
import { AMOUNT_MAX } from '../utils/AmountGuard';

// 识别流程步骤：选图 -> 识别中 -> 结果确认
const STEP_PICK: number = 0;
const STEP_RECOGNIZING: number = 1;
const STEP_CONFIRM: number = 2;

// 加号菜单跳转来源：camera 直接拍照、gallery 直接选相册；ledgerId 非空表示从账本详情进入（入账时同步进该账本）
interface RecognizeSourceParam {
  source: string;
  ledgerId?: string;
}

@Entry
@Component
struct RecognizeBill {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  @State step: number = STEP_PICK;
  // 批量识别任务（每张图一个）
  @State tasks: ImageTask[] = [];
  // 确认页合并后的账单草稿列表
  @State drafts: BillDraft[] = [];
  // 展开编辑的草稿索引，-1 表示未展开
  @State expandedIndex: number = -1;
  // 展开项的编辑缓冲（响应式）
  @State accountType: AccountType = AccountType.EXPENSES;
  @State amountText: string = '';
  @State merchant: string = '';
  @State selectedDate: number = dayjs().startOf('day').valueOf();
  @State payTime: number = Date.now();
  @State selectType: AccountTypeModel | undefined = undefined;
  @State autoClassified: boolean = false;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;
  // 页面销毁标志：识别中退出页面后，后台协程不再更新状态/写缓存
  private destroyed: boolean = false;
  // 入账执行中标志：防止双击“入账”导致同一批草稿重复入库
  @State importing: boolean = false;
  // 从账本进入时是否同步记入主账单（首页统计）；非账本入口不显示开关、恒为 true
  @State syncToBills: boolean = true;
  // 账本入口：非空时入账的每笔同步复制进该账本
  private ledgerId: string = '';
  private ledgerRepository: LedgerRepository = new LedgerRepository();

  aboutToAppear(): void {
    const params = router.getParams() as RecognizeSourceParam | undefined;
    const source = params && typeof params.source === 'string' ? params.source : '';
    const ledgerId = params?.ledgerId;
    this.ledgerId = params && typeof ledgerId === 'string' ? ledgerId : '';
    // 账本入口：同步开关初值读设置（设置页可配置，默认开）；非账本入口不显示开关、恒为 true
    if (this.ledgerId.length > 0) {
      this.loadSyncDefault();
    }
    if (source === 'camera') {
      this.pickFromCamera();
    } else if (source === 'gallery') {
      this.pickFromGallery();
    }
  }

  // 读取“同步记入主账单”的默认开关；读取失败保持默认 true
  async loadSyncDefault(): Promise<void> {
    try {
      const value = await PreferenceUtil.getPreferenceValue(PREF_LEDGER_SYNC_BILLS, true);
      this.syncToBills = value === true;
    } catch (err) {
      Logger.error('读取账本同步默认设置失败', (err as Error).message);
    }
  }

  aboutToDisappear(): void {
    // 置销毁标志，让仍在后台执行的识别协程放弃后续状态更新
    this.destroyed = true;
  }

  // 从相册多选账单图片：走系统选择器，无需相册权限
  async pickFromGallery(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = MAX_PICK_IMAGES;
      const result = await picker.select(options);
      if (result.photoUris.length > 0) {
        this.startBatchRecognize(result.photoUris);
      }
    } catch (error) {
      Logger.error('选择图片失败', (error as Error).message);
      Toast.error($r('app.string.pick_image_failed'));
    }
  }

  // 拉起系统相机拍照：走系统选择器，无需相机权限
  async pickFromCamera(): Promise<void> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const result = await cameraPicker.pick(getContext(this), [cameraPicker.PickerMediaType.PHOTO], profile);
      if (result.resultCode === 0 && result.resultUri.length > 0) {
        const uris: string[] = [result.resultUri];
        this.startBatchRecognize(uris);
      }
    } catch (error) {
      Logger.error('拍照失败', (error as Error).message);
      Toast.error($r('app.string.camera_failed'));
    }
  }

  // 云端识别前确认用户同意上传图片；端侧识别无需同意
  ensureCloudConsent(): Promise<boolean> {
    return CloudLlmConfigStore.loadCloudEnabled().then((enabled: boolean): Promise<boolean> => {
      if (!enabled) {
        return Promise.resolve(true);
      }
      return CloudLlmConfigStore.loadCloudConsent().then((agreed: boolean): Promise<boolean> => {
        if (agreed) {
          return Promise.resolve(true);
        }
        return new Promise<boolean>((resolve: (v: boolean) => void) => {
          AlertDialog.show({
            title: $r('app.string.cloud_consent_title'),
            message: $r('app.string.cloud_consent_msg'),
            autoCancel: true,
            alignment: DialogAlignment.Center,
            cancel: () => {
              resolve(false);
            },
            primaryButton: {
              value: $r('app.string.cancel'),
              action: () => {
                resolve(false);
              }
            },
            secondaryButton: {
              value: $r('app.string.agree'),
              fontColor: this.tk().primary,
              action: () => {
                CloudLlmConfigStore.saveCloudConsent(true);
                resolve(true);
              }
            }
          });
        });
      });
    });
  }

  // 批量识别入口：先确认云端同意，再建任务列表 -> 并发识别 -> 合并结果
  async startBatchRecognize(uris: string[]): Promise<void> {
    const consented = await this.ensureCloudConsent();
    if (!consented) {
      return;
    }
    this.step = STEP_RECOGNIZING;
    this.expandedIndex = -1;
    const tasks: ImageTask[] = [];
    for (const uri of uris) {
      const task = new ImageTask();
      task.uri = uri;
      tasks.push(task);
    }
    this.tasks = tasks;
    await this.runBatch(tasks);
    if (this.destroyed) {
      return;
    }
    this.mergeDrafts();
    if (this.drafts.length === 0) {
      Toast.error($r('app.string.all_recognize_failed'));
      this.step = STEP_PICK;
      return;
    }
    this.step = STEP_CONFIRM;
  }

  // 并发识别：最多同时 RECOGNIZE_CONCURRENCY 个请求
  async runBatch(tasks: ImageTask[]): Promise<void> {
    let recognizer: Recognizer;
    try {
      recognizer = await RecognizerFactory.create();
    } catch (err) {
      const e = err as Error;
      const message = e.message ? e.message : getContext().resourceManager.getStringSync($r('app.string.recognize_failed'));
      for (const task of tasks) {
        task.status = ImageTaskStatus.FAILED;
        task.error = message;
      }
      this.refreshTasks();
      return;
    }
    const queue = tasks.slice();
    const workerCount = Math.min(RECOGNIZE_CONCURRENCY, queue.length);
    const workers: Promise<void>[] = [];
    for (let i = 0; i < workerCount; i++) {
      workers.push(this.runWorker(queue, recognizer));
    }
    await Promise.all(workers);
  }

  // 单个工作协程：从共享队列取任务直到取空；页面销毁后立即停止
  async runWorker(queue: ImageTask[], recognizer: Recognizer): Promise<void> {
    while (queue.length > 0 && !this.destroyed) {
      const task = queue.shift();
      if (!task) {
        return;
      }
      await this.recognizeOne(task, recognizer);
    }
  }

  // 识别单张图片：走流水线得到草稿，失败只标记该任务不影响其他，返回是否成功
  async recognizeOne(task: ImageTask, recognizer: Recognizer): Promise<boolean> {
    task.status = ImageTaskStatus.RECOGNIZING;
    this.refreshTasks();
    try {
      const raws = await recognizer.recognize(task.uri);
      if (raws.length === 0) {
        task.status = ImageTaskStatus.FAILED;
        task.error = getContext().resourceManager.getStringSync($r('app.string.not_a_bill'));
        this.refreshTasks();
        return false;
      }
      const pipeline = new RecognitionPipeline();
      const drafts: BillDraft[] = [];
      for (const raw of raws) {
        const outcome = await pipeline.run(task.uri, raw);
        if (!outcome.success) {
          task.status = ImageTaskStatus.FAILED;
          task.error = outcome.message;
          this.refreshTasks();
          return false;
        }
        drafts.push(BillDraft.fromResult(outcome.result, task.uri));
      }
      task.drafts = drafts;
      task.status = ImageTaskStatus.SUCCESS;
      this.refreshTasks();
      return true;
    } catch (err) {
      const e = err as Error;
      task.status = ImageTaskStatus.FAILED;
      task.error = e.message ? e.message : getContext().resourceManager.getStringSync($r('app.string.recognize_failed'));
      this.refreshTasks();
      return false;
    }
  }

  // 失败项单独重试，成功后追加新草稿，保留已有编辑
  async retryTask(taskIndex: number): Promise<void> {
    const task = this.tasks[taskIndex];
    if (!task || task.status !== ImageTaskStatus.FAILED) {
      return;
    }
    task.error = '';
    task.status = ImageTaskStatus.PENDING;
    this.refreshTasks();
    let recognizer: Recognizer;
    try {
      recognizer = await RecognizerFactory.create();
    } catch (err) {
      const e = err as Error;
      task.status = ImageTaskStatus.FAILED;
      task.error = e.message ? e.message : getContext().resourceManager.getStringSync($r('app.string.recognize_failed'));
      this.refreshTasks();
      return;
    }
    const ok = await this.recognizeOne(task, recognizer);
    if (this.destroyed) {
      return;
    }
    if (ok) {
      for (const d of task.drafts) {
        this.drafts.push(d);
      }
      this.dedupWithinBatch();
    }
  }

  // 手动回退大模型：端侧结果置信度达标但用户不满意时，改用云端大模型重新识别该图并替换草稿
  async fallbackToCloud(taskIndex: number): Promise<void> {
    const task = this.tasks[taskIndex];
    if (!task || task.status === ImageTaskStatus.RECOGNIZING || task.drafts.length === 0) {
      return;
    }
    const cloudEnabled = await CloudLlmConfigStore.loadCloudEnabled();
    if (!cloudEnabled) {
      Toast.error($r('app.string.cloud_fallback_disabled'));
      return;
    }
    const consented = await this.ensureCloudConsent();
    if (!consented) {
      return;
    }
    task.status = ImageTaskStatus.RECOGNIZING;
    task.error = '';
    this.refreshTasks();
    const recognizer = new RetryRecognizer(
      new CloudLlmRecognizer(await CloudLlmConfigStore.loadConfig()),
      RECOGNIZE_RETRY_MAX_ATTEMPTS, RECOGNIZE_RETRY_BASE_DELAY_MS);
    const ok = await this.recognizeOne(task, recognizer);
    if (this.destroyed) {
      return;
    }
    if (ok) {
      this.replaceTaskDrafts(task);
      return;
    }
    // 云端识别失败：恢复成功态并保留原端侧草稿，用户可继续编辑或再次回退
    task.status = ImageTaskStatus.SUCCESS;
    task.error = '';
    this.refreshTasks();
    Toast.error($r('app.string.cloud_fallback_failed'));
  }

  // 用该图最新识别结果替换确认页草稿：手动补录的保留，展开编辑状态尽量恢复
  replaceTaskDrafts(task: ImageTask): void {
    if (this.expandedIndex >= 0) {
      this.commitExpanded();
    }
    const expandedUid = this.expandedIndex >= 0 && this.expandedIndex < this.drafts.length
      ? this.drafts[this.expandedIndex].uid : -1;
    const merged: BillDraft[] = [];
    for (const d of this.drafts) {
      if (d.imageUri === task.uri && !d.manual) {
        continue;
      }
      merged.push(d);
    }
    for (const d of task.drafts) {
      merged.push(d);
    }
    this.drafts = merged;
    this.expandedIndex = -1;
    for (let i = 0; i < this.drafts.length; i++) {
      if (this.drafts[i].uid === expandedUid) {
        this.expandedIndex = i;
        break;
      }
    }
    if (this.expandedIndex >= 0) {
      this.loadExpanded();
    }
    this.dedupWithinBatch();
  }

  // 该任务使用的识别引擎：同一张图的草稿来自同一次识别，取第一条即可
  taskEngine(task: ImageTask): string {
    if (task.drafts.length === 0) {
      return '';
    }
    return task.drafts[0].engine;
  }

  // 该任务草稿的最小置信度换算成百分比：反映这张图“最差一笔”的识别可靠程度
  taskConfidencePercent(task: ImageTask): number {
    let min = 1;
    for (const d of task.drafts) {
      if (d.confidence < min) {
        min = d.confidence;
      }
    }
    return Math.round(min * 100);
  }

  // 触发任务列表刷新：V1 数组元素字段变更需整体替换
  refreshTasks(): void {
    this.tasks = this.tasks.slice();
  }

  // 合并所有成功任务的草稿
  mergeDrafts(): void {
    const all: BillDraft[] = [];
    for (const task of this.tasks) {
      if (task.status === ImageTaskStatus.SUCCESS) {
        for (const d of task.drafts) {
          all.push(d);
        }
      }
    }
    this.drafts = all;
    this.dedupWithinBatch();
  }

  // 本次识别结果内部去重：与数据库重复的保持不勾选，互相重复的只保留第一条勾选
  dedupWithinBatch(): void {
    const n = this.drafts.length;
    for (let i = 0; i < n; i++) {
      const current = this.drafts[i];
      if (current.duplicated) {
        current.selected = false;
        continue;
      }
      const amount = parseFloat(current.amountText);
      if (!(amount > 0)) {
        continue;
      }
      for (let j = 0; j < i; j++) {
        const prev = this.drafts[j];
        const prevAmount = parseFloat(prev.amountText);
        if (!(prevAmount > 0)) {
          continue;
        }
        if (isDuplicateBill(amount, current.merchant, current.payTime,
          prevAmount, prev.merchant, prev.payTime)) {
          // 批内重复：标记为疑似重复，让用户可见原因，而不是仅静默取消勾选
          current.duplicated = true;
          current.selected = false;
          break;
        }
      }
    }
    this.drafts = this.drafts.slice();
  }

  // 展开/收起编辑面板
  toggleExpand(index: number): void {
    if (this.expandedIndex === index) {
      this.commitExpanded();
      this.expandedIndex = -1;
      return;
    }
    if (this.expandedIndex >= 0) {
      this.commitExpanded();
    }
    this.expandedIndex = index;
    this.loadExpanded();
  }

  // 识别引擎标识 -> 确认页徽标文案
  engineLabel(engine: string): Resource | string {
    if (engine === 'local_model') {
      return $r('app.string.engine_local_model');
    }
    if (engine === 'cloud') {
      return $r('app.string.engine_cloud');
    }
    if (engine === 'ocr_rule') {
      return $r('app.string.engine_ocr_rule');
    }
    return '';
  }

  commitExpanded(): void {
    const index = this.expandedIndex;
    if (index < 0 || index >= this.drafts.length) {
      return;
    }
    const draft = this.drafts[index];
    draft.amountText = this.amountText;
    draft.merchant = this.merchant;
    draft.accountType = this.accountType;
    draft.selectType = this.selectType;
    draft.autoClassified = this.autoClassified;
    draft.selectedDate = this.selectedDate;
    draft.payTime = this.payTime;
  }

  loadExpanded(): void {
    const index = this.expandedIndex;
    if (index < 0 || index >= this.drafts.length) {
      return;
    }
    const draft = this.drafts[index];
    this.amountText = draft.amountText;
    this.merchant = draft.merchant;
    this.accountType = draft.accountType;
    this.selectType = draft.selectType;
    this.autoClassified = draft.autoClassified;
    this.selectedDate = draft.selectedDate;
    this.payTime = draft.payTime;
  }

  toggleSelect(index: number): void {
    const draft = this.drafts[index];
    draft.selected = !draft.selected;
    this.drafts = this.drafts.slice();
  }

  deleteDraft(index: number): void {
    if (this.expandedIndex === index) {
      this.expandedIndex = -1;
    } else if (this.expandedIndex > index) {
      this.expandedIndex--;
    }
    this.drafts.splice(index, 1);
    this.drafts = this.drafts.slice();
  }

  // 切换收支后原分类不再适用，回退到该侧的“其他”
  onAccountTypeChange(accountType: AccountType): void {
    if (accountType === this.accountType) {
      return;
    }
    this.accountType = accountType;
    this.selectType = BillDraft.matchCategory('', accountType);
    this.autoClassified = false;
  }

  showDatePicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-1-1'),
      end: new Date(),
      selected: new Date(this.selectedDate),
      onDateAccept: (value: Date) => {
        this.selectedDate = dayjs(value).startOf('day').valueOf();
        const origin = dayjs(this.payTime);
        this.payTime = dayjs(this.selectedDate)
          .hour(origin.hour())
          .minute(origin.minute())
          .second(0)
          .millisecond(0)
          .valueOf();
      }
    });
  }

  // 时分编辑：24 小时制时间选择弹窗，日期保持不变
  showTimePicker(): void {
    this.getUIContext().showTimePickerDialog({
      selected: new Date(this.payTime),
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        if (value.hour === undefined || value.minute === undefined) {
          return;
        }
        this.payTime = dayjs(this.selectedDate)
          .hour(value.hour)
          .minute(value.minute)
          .second(0)
          .millisecond(0)
          .valueOf();
      }
    });
  }

  // 校验金额：大于 0 且最多两位小数，且不超统一上限
  validateAmount(): boolean {
    const value = this.amountText;
    if (!value) {
      return false;
    }
    const amount = parseFloat(value);
    if (amount <= 0 || amount > AMOUNT_MAX) {
      return false;
    }
    const regex = /^\d+(\.\d{1,2})?$/;
    return regex.test(value);
  }

  // 一键入账：入账只处理勾选项；训练标签则采集图上所有真实交易（含判重复的）
  async onImportSelected(): Promise<void> {
    // 防重入：双击“入账”会把同一批草稿写两遍
    if (this.importing) {
      return;
    }
    this.importing = true;
    try {
      await this.doImportSelected();
    } finally {
      this.importing = false;
    }
  }

  private async doImportSelected(): Promise<void> {
    if (this.expandedIndex >= 0) {
      this.commitExpanded();
    }
    if (this.destroyed) {
      return;
    }
    // 入账：只处理勾选的
    let imported = 0;
    let overLimit = false;
    const toLedger = this.ledgerId.length > 0;
    for (const draft of this.drafts) {
      if (!draft.selected) {
        continue;
      }
      const parsed = parseFloat(draft.amountText);
      if (parsed > AMOUNT_MAX) {
        // 超上限的异常金额（识别错误/手滑输入）不入账，避免统计与显示错乱
        overLimit = true;
        continue;
      }
      const amount = parsed;
      if (!(amount > 0) || !draft.selectType) {
        continue;
      }
      const info: AccountInfo = {
        accountType: draft.accountType,
        type: draft.selectType.id,
        amount: amount,
        time: draft.selectedDate,
        merchant: draft.merchant,
        description: draft.merchant,
        source: SOURCE_IMAGE,
        payTime: draft.payTime
      };
      try {
        // 同步主账单（首页统计）；从账本进入且关闭开关时跳过，只进账本
        let billId = '';
        if (this.syncToBills) {
          billId = await AccountService.insert(info);
        }
        await learnedClassifier.learn(draft.merchant, draft.selectType.id, draft.accountType);
        // 账本入口：每笔同步复制进账本，关联主账单 id 供防重复导入
        if (toLedger) {
          const recordType = draft.accountType === AccountType.INCOME
            ? LEDGER_RECORD_INCOME : LEDGER_RECORD_EXPENSE;
          await this.ledgerRepository.insertRecord(this.ledgerId, recordType, amount,
            draft.merchant, draft.payTime, draft.selectType.id, billId);
        }
        imported++;
      } catch (err) {
        Logger.error('导入账单失败', (err as Error).message);
      }
    }
    if (imported <= 0) {
      Toast.error($r('app.string.require_amount_type'));
      return;
    }
    if (overLimit) {
      Toast.error($r('app.string.amount_too_large'));
    }
    if (this.destroyed) {
      return;
    }
    // 账本入口：通知账本详情/列表刷新
    if (toLedger) {
      LedgerStore.notifyChanged();
    }
    Toast.success($r('app.string.save_success'));
    router.back();
  }

  // 手动补录大模型漏识别的交易：新建一条空草稿并展开编辑，入账后同样进入训练样本（confirmed）
  addManualDraft(): void {
    if (this.expandedIndex >= 0) {
      this.commitExpanded();
    }
    const draft = new BillDraft();
    draft.amountText = '';
    draft.merchant = '';
    draft.accountType = AccountType.EXPENSES;
    draft.selectType = BillDraft.matchCategory('', AccountType.EXPENSES);
    draft.selectedDate = dayjs().startOf('day').valueOf();
    draft.payTime = Date.now();
    draft.selected = true;
    draft.autoClassified = false;
    draft.manual = true;
    draft.imageUri = this.firstSuccessUri();
    this.drafts.push(draft);
    this.drafts = this.drafts.slice();
    this.expandedIndex = this.drafts.length - 1;
    this.loadExpanded();
  }

  // 取当前批次第一个成功任务的图片 uri，作为手动补录交易的关联图（用于训练样本按图分组）
  firstSuccessUri(): string {
    for (const task of this.tasks) {
      if (task.status === ImageTaskStatus.SUCCESS) {
        return task.uri;
      }
    }
    return '';
  }

  // Grid 是滚动容器，必须显式给定高度
  getGridHeight(): number {
    const rows = Math.ceil(CategoryRegistry.list(this.accountType).length / 4);
    if (rows <= 0) {
      return 0;
    }
    return rows * 55 + (rows - 1) * 16;
  }

  @Builder PickPanel() {
    Column({ space: SPACE_MEDIUM }) {
      Text($r('app.string.recognize_entry_title'))
        .fontSize(this.fs(20))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tk().textPrimary)
      Text($r('app.string.pick_tip'))
        .fontSize(this.fs(13))
        .fontColor(this.tk().textSecondary)
        .textAlign(TextAlign.Center)
      Button($r('app.string.pick_from_camera'))
        .width('100%')
        .height(48)
        .fontSize(this.fs(16))
        .backgroundColor(this.tk().primary)
        .fontColor(this.tk().surface)
        .type(ButtonType.Normal)
        .borderRadius(SPACE_SMALL)
        .margin({ top: SPACE_LARGE })
        .onClick(() => {
          this.pickFromCamera();
        })
      Button($r('app.string.pick_from_gallery'))
        .width('100%')
        .height(48)
        .fontSize(this.fs(16))
        .backgroundColor(this.tk().surface)
        .fontColor(this.tk().textPrimary)
        .type(ButtonType.Normal)
        .borderRadius(SPACE_SMALL)
        .onClick(() => {
          this.pickFromGallery();
        })
    }
    .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: SPACE_XLARGE, right: SPACE_XLARGE })
  }

  @Builder TaskItem(task: ImageTask, index: number) {
    Row({ space: SPACE_SMALL }) {
      if (task.status === ImageTaskStatus.RECOGNIZING) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(this.tk().primary)
      } else if (task.status === ImageTaskStatus.SUCCESS) {
        Image($r('app.media.success'))
          .width(16)
          .height(16)
          .fillColor(this.tk().primary)
      } else if (task.status === ImageTaskStatus.FAILED) {
        Image($r('app.media.error'))
          .width(16)
          .height(16)
          .fillColor(this.tk().danger)
      } else {
        Column()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.tk().outline)
      }
      Text($r('app.string.task_index', index + 1))
        .fontSize(this.fs(14))
        .fontColor(this.tk().textPrimary)
        .layoutWeight(1)
      if (task.status === ImageTaskStatus.SUCCESS) {
        Text($r('app.string.task_success_count', task.drafts.length))
          .fontSize(this.fs(12))
          .fontColor(this.tk().primary)
      } else if (task.status === ImageTaskStatus.FAILED) {
        Text($r('app.string.task_failed'))
          .fontSize(this.fs(12))
          .fontColor(this.tk().danger)
      } else if (task.status === ImageTaskStatus.PENDING) {
        Text($r('app.string.task_pending'))
          .fontSize(this.fs(12))
          .fontColor(this.tk().textSecondary)
      }
    }
    .width('100%')
    .height(40)
    .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM })
    .backgroundColor(this.tk().surface)
    .borderRadius(SPACE_SMALL)
  }

  @Builder RecognizingPanel() {
    Column({ space: SPACE_MEDIUM }) {
      Text($r('app.string.recognizing'))
        .fontSize(this.fs(15))
        .fontColor(this.tk().textPrimary)
        .margin({ bottom: SPACE_SMALL })
      List({ space: SPACE_SMALL }) {
        ForEach(this.tasks, (task: ImageTask, index: number) => {
          ListItem() {
            this.TaskItem(task, index)
          }
        }, (task: ImageTask, index: number) => task.uri + index + task.status)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
    .layoutWeight(1)
    .padding({ left: SPACE_XLARGE, right: SPACE_XLARGE, top: SPACE_LARGE })
  }

  @Builder EditPanel(index: number) {
    Column({ space: SPACE_MEDIUM }) {
      Column() {
        Row() {
          Text($r('app.string.amount_label'))
            .width(64)
            .fontSize(this.fs(14))
            .fontColor(this.tk().textPrimary)
          TextInput({ text: this.amountText, placeholder: $r('app.string.amount_placeholder') })
            .type(InputType.NUMBER_DECIMAL)
            .maxLength(10)
            .fontSize(this.fs(16))
            .fontColor(this.tk().textPrimary)
            .textAlign(TextAlign.End)
            .layoutWeight(1)
            .backgroundColor(this.tk().surface)
            .onChange((value: string) => {
              this.amountText = value;
            })
        }.width('100%').height(44)
        Divider().color(this.tk().surfaceVariant)
        Row() {
          Text($r('app.string.merchant_label'))
            .width(64)
            .fontSize(this.fs(14))
            .fontColor(this.tk().textPrimary)
          TextInput({ text: this.merchant, placeholder: $r('app.string.merchant_placeholder') })
            .fontSize(this.fs(16))
            .fontColor(this.tk().textPrimary)
            .textAlign(TextAlign.End)
            .layoutWeight(1)
            .backgroundColor(this.tk().surface)
            .onChange((value: string) => {
              this.merchant = value;
            })
        }.width('100%').height(44)
        Divider().color(this.tk().surfaceVariant)
        Row({ space: SPACE_SMALL }) {
          Image($r('app.media.date'))
            .width(14)
            .objectFit(ImageFit.Contain)
          Text(dayjs(this.selectedDate).format('YYYY-MM-DD'))
            .fontSize(this.fs(14))
            .fontColor(this.tk().textPrimary)
        }.width('100%').height(44)
        .onClick(() => {
          this.showDatePicker();
        })
        Divider().color(this.tk().surfaceVariant)
        Row({ space: SPACE_SMALL }) {
          Image($r('app.media.date'))
            .width(14)
            .objectFit(ImageFit.Contain)
          Text(dayjs(this.payTime).format('HH:mm'))
            .fontSize(this.fs(14))
            .fontColor(this.tk().textPrimary)
        }.width('100%').height(44)
        .onClick(() => {
          this.showTimePicker();
        })
      }
      .width('100%')
      .padding(SPACE_LARGE)
      .backgroundColor(this.tk().surface)
      .borderRadius(RADIUS_CARD)
      .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

      Row({ space: SPACE_MEDIUM }) {
        Button($r('app.string.expenditure'))
          .layoutWeight(1)
          .height(40)
          .fontSize(this.fs(15))
          .fontColor(this.accountType === AccountType.EXPENSES ? this.tk().surface : this.tk().textSecondary)
          .backgroundColor(this.accountType === AccountType.EXPENSES ? this.tk().primary : this.tk().surface)
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .onClick(() => {
            this.onAccountTypeChange(AccountType.EXPENSES);
          })
        Button($r('app.string.income'))
          .layoutWeight(1)
          .height(40)
          .fontSize(this.fs(15))
          .fontColor(this.accountType === AccountType.INCOME ? this.tk().surface : this.tk().textSecondary)
          .backgroundColor(this.accountType === AccountType.INCOME ? this.tk().primary : this.tk().surface)
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .onClick(() => {
            this.onAccountTypeChange(AccountType.INCOME);
          })
      }.width('100%')

      Column() {
        Grid() {
          ForEach(CategoryRegistry.list(this.accountType), (item: AccountTypeModel) => {
            GridItem() {
              Column({ space: 4 }) {
                Stack({ alignContent: Alignment.TopEnd }) {
                  Column() {
                    Image(item.icon)
                      .width(16)
                      .objectFit(ImageFit.Contain)
                      .fillColor(this.selectType?.id === item.id ? this.tk().surface : this.tk().textSecondary)
                  }.width(36)
                  .height(36)
                  .borderRadius(18)
                  .alignItems(HorizontalAlign.Center)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(this.selectType?.id === item.id ? item.activeColor : this.tk().surfaceVariant)
                  if (this.selectType?.id === item.id && this.autoClassified) {
                    Text($r('app.string.auto_classified'))
                      .fontSize(this.fs(8))
                      .fontColor(this.tk().surface)
                      .backgroundColor(this.tk().warning)
                      .borderRadius(4)
                      .padding({ left: 2, right: 2, top: 1, bottom: 1 })
                  }
                }.width(36).height(36)
                Text(item.name).fontSize(this.fs(12))
                  .fontColor(this.selectType?.id === item.id ? this.tk().textPrimary : this.tk().textSecondary)
                  .lineHeight(this.fs(15))
              }.onClick(() => {
                this.selectType = item;
                this.autoClassified = false;
              })
            }.width('100%')
          // key 带上收支侧前缀：两侧分类 id 均从 0 编号，仅用 id 切换收支时会残留旧分类
          }, (item: AccountTypeModel) => this.accountType + '_' + item.id.toString())
        }.columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(16)
        .width('100%')
        .height(this.getGridHeight())
      }
      .width('100%')
      .padding(SPACE_LARGE)
      .backgroundColor(this.tk().surface)
      .borderRadius(RADIUS_CARD)
      .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
    }
    .width('100%')
    .margin({ top: SPACE_MEDIUM })
  }

  @Builder DraftItem(draft: BillDraft, index: number) {
    Column() {
      Row({ space: SPACE_SMALL }) {
        Checkbox()
          .select(draft.selected)
          .onChange((checked: boolean) => {
            draft.selected = checked;
            this.drafts = this.drafts.slice();
          })
        Column({ space: SPACE_TINY }) {
          Row({ space: SPACE_SMALL }) {
            Text(draft.amountText ? '¥' + draft.amountText : $r('app.string.amount_placeholder'))
              .fontSize(this.fs(15))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.tk().textPrimary)
            Text(draft.merchant)
              .fontSize(this.fs(13))
              .fontColor(this.tk().textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Row({ space: SPACE_SMALL }) {
            if (draft.engine !== '') {
              Text(this.engineLabel(draft.engine))
                .fontSize(this.fs(10))
                .fontColor(this.tk().primary)
                .padding({ left: SPACE_TINY, right: SPACE_TINY, top: 2, bottom: 2 })
                .borderRadius(4)
                .backgroundColor(this.tk().primarySoft)
            }
            Text(draft.selectType?.name ?? '')
              .fontSize(this.fs(12))
              .fontColor(this.tk().textSecondary)
            Text(dayjs(draft.payTime).format('YYYY-MM-DD HH:mm'))
              .fontSize(this.fs(12))
              .fontColor(this.tk().textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .onClick(() => {
          this.toggleExpand(index);
        })
        Text($r('app.string.delete'))
          .fontSize(this.fs(13))
          .fontColor(this.tk().danger)
          .onClick(() => {
            this.deleteDraft(index);
          })
      }.width('100%')
      .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM, top: SPACE_SMALL, bottom: SPACE_SMALL })

      if (draft.duplicated) {
        Text($r('app.string.duplicated_tip'))
          .fontSize(this.fs(11))
          .fontColor(this.tk().warning)
          .width('100%')
          .padding({ left: SPACE_MEDIUM, bottom: SPACE_TINY })
      }

      if (this.expandedIndex === index) {
        this.EditPanel(index)
      }
    }
    .width('100%')
    .backgroundColor(draft.duplicated ? this.tk().dangerSoft : this.tk().surface)
    .borderRadius(RADIUS_CARD)
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
  }

  @Builder ConfirmPanel() {
    Column({ space: SPACE_MEDIUM }) {
      Row({ space: SPACE_MEDIUM }) {
        Text($r('app.string.recognize_confirm_title'))
          .fontSize(this.fs(18))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tk().textPrimary)
          .layoutWeight(1)
        // 入账中：等待训练样本采集（OCR串行队列）+ 逐条写库耗时数秒，文案切“正在入账…”并禁用，防止误以为卡死
        Button(this.importing ? $r('app.string.importing_tip') : $r('app.string.import_selected'))
          .height(40)
          .fontSize(this.fs(15))
          .backgroundColor(this.tk().primary)
          .fontColor(this.tk().surface)
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .enabled(!this.importing)
          .opacity(this.importing ? 0.6 : 1)
          .onClick(() => {
            this.onImportSelected();
          })
      }.width('100%')

      // 手动补录大模型漏识别的交易：补录的也会进入训练样本（confirmed）
      Button($r('app.string.add_manual'))
        .width('100%')
        .height(40)
        .fontSize(this.fs(15))
        .fontColor(this.tk().primary)
        .backgroundColor(this.tk().surface)
        .type(ButtonType.Normal)
        .borderRadius(SPACE_SMALL)
        .border({ width: 1, color: this.tk().primary })
        .onClick(() => {
          this.addManualDraft();
        })

      // 从账本进入时：可选是否同步记入主账单（关闭则只进账本）
      if (this.ledgerId.length > 0) {
        Row() {
          Text($r('app.string.ledger_sync_to_bills'))
            .fontSize(this.fs(13))
            .fontColor(this.tk().textPrimary)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.syncToBills })
            .selectedColor(this.tk().primary)
            .onChange((isOn: boolean) => {
              this.syncToBills = isOn;
            })
        }
        .width('100%')
        .padding({ left: SPACE_SMALL, right: SPACE_SMALL })
      }

      // 失败重试行、端侧置信度行与草稿同列一个滚动列表：图片多时不挤占下方草稿空间
      List({ space: SPACE_SMALL }) {
        // 失败项：可单独重试；重试进行中也保留该行并显示识别中，
        // 否则点重试后该行消失且无任何反馈，看起来像“重试没反应”
        ForEach(this.tasks, (task: ImageTask, index: number) => {
          if (task.status === ImageTaskStatus.FAILED ||
            ((task.status === ImageTaskStatus.PENDING || task.status === ImageTaskStatus.RECOGNIZING) &&
              task.drafts.length === 0)) {
            ListItem() {
              Row({ space: SPACE_SMALL }) {
                if (task.status === ImageTaskStatus.FAILED) {
                  Image($r('app.media.error'))
                    .width(14)
                    .height(14)
                    .fillColor(this.tk().danger)
                } else {
                  LoadingProgress()
                    .width(14)
                    .height(14)
                    .color(this.tk().primary)
                }
                if (task.status === ImageTaskStatus.FAILED) {
                  Text(task.error)
                    .fontSize(this.fs(12))
                    .fontColor(this.tk().danger)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text($r('app.string.retry'))
                    .fontSize(this.fs(13))
                    .fontColor(this.tk().primary)
                    .onClick(() => {
                      this.retryTask(index);
                    })
                } else {
                  Text($r('app.string.task_index', index + 1))
                    .fontSize(this.fs(12))
                    .fontColor(this.tk().textSecondary)
                    .layoutWeight(1)
                  Text($r('app.string.recognizing'))
                    .fontSize(this.fs(12))
                    .fontColor(this.tk().primary)
                }
              }.width('100%')
              .height(40)
              .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM })
              .backgroundColor(this.tk().surface)
              .borderRadius(SPACE_SMALL)
            }
          }
        }, (task: ImageTask, index: number) => 'failed_' + index + task.status)

        // 端侧置信度展示与手动回退：非云端结果可随时改用大模型重新识别该图
        ForEach(this.tasks, (task: ImageTask, index: number) => {
          if (task.drafts.length > 0 && this.taskEngine(task) !== 'cloud') {
            ListItem() {
              Row({ space: SPACE_SMALL }) {
                if (task.status === ImageTaskStatus.RECOGNIZING) {
                  LoadingProgress()
                    .width(14)
                    .height(14)
                    .color(this.tk().primary)
                }
                Text($r('app.string.task_index', index + 1))
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().textPrimary)
                Text($r('app.string.confidence_percent', this.taskConfidencePercent(task)))
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().textSecondary)
                  .layoutWeight(1)
                if (task.status === ImageTaskStatus.RECOGNIZING) {
                  Text($r('app.string.recognizing'))
                    .fontSize(this.fs(12))
                    .fontColor(this.tk().primary)
                } else {
                  Text($r('app.string.fallback_cloud'))
                    .fontSize(this.fs(13))
                    .fontColor(this.tk().primary)
                    .onClick(() => {
                      this.fallbackToCloud(index);
                    })
                }
              }
              .width('100%')
              .height(40)
              .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM })
              .backgroundColor(this.tk().surface)
              .borderRadius(SPACE_SMALL)
            }
          }
        }, (task: ImageTask, index: number) => 'fallback_' + index + task.status + this.taskEngine(task) +
          this.taskConfidencePercent(task))

        ForEach(this.drafts, (draft: BillDraft, index: number) => {
          ListItem() {
            this.DraftItem(draft, index)
          }
        }, (draft: BillDraft, index: number) => 'draft_' + draft.uid + draft.selected + draft.duplicated +
          draft.amountText + draft.merchant + draft.payTime + (draft.selectType ? draft.selectType.name : ''))
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
    .layoutWeight(1)
    .padding({ left: SPACE_XLARGE, right: SPACE_XLARGE, top: SPACE_MEDIUM })
  }

  build() {
    Column() {
      AccountNavigator()
      if (this.step === STEP_PICK) {
        this.PickPanel()
      } else if (this.step === STEP_RECOGNIZING) {
        this.RecognizingPanel()
      } else {
        this.ConfirmPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }
}
