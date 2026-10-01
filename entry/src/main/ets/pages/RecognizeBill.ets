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
import { RecognitionPipeline } from '../service/recognition/pipeline/RecognitionPipeline';
import learnedClassifier from '../service/recognition/classifier/LearnedClassifier';
import AccountService from '../service/account';
import { SOURCE_IMAGE } from '../common/constants';
import { MAX_PICK_IMAGES, RECOGNIZE_CONCURRENCY } from '../common/Config';
import { isDuplicateBill } from '../common/dedup';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import BreakpointConstants from '../common/breakpoint';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY, SPACE_XLARGE } from '../common/dimens';

// 识别流程步骤：选图 -> 识别中 -> 结果确认
const STEP_PICK: number = 0;
const STEP_RECOGNIZING: number = 1;
const STEP_CONFIRM: number = 2;

@Entry
@Component
struct RecognizeBill {
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

  // 批量识别入口：建任务列表 -> 并发识别 -> 合并结果
  async startBatchRecognize(uris: string[]): Promise<void> {
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

  // 单个工作协程：从共享队列取任务直到取空
  async runWorker(queue: ImageTask[], recognizer: Recognizer): Promise<void> {
    while (queue.length > 0) {
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
    if (ok) {
      for (const d of task.drafts) {
        this.drafts.push(d);
      }
      this.dedupWithinBatch();
    }
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

  // 校验金额：大于 0 且最多两位小数
  validateAmount(): boolean {
    const value = this.amountText;
    if (!value) {
      return false;
    }
    const amount = parseFloat(value);
    if (amount <= 0) {
      return false;
    }
    const regex = /^\d+(\.\d{1,2})?$/;
    return regex.test(value);
  }

  // 一键入账：遍历勾选项逐条插入
  async onImportSelected(): Promise<void> {
    if (this.expandedIndex >= 0) {
      this.commitExpanded();
    }
    let imported = 0;
    for (const draft of this.drafts) {
      if (!draft.selected) {
        continue;
      }
      const amount = parseFloat(draft.amountText);
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
        await AccountService.insert(info);
        await learnedClassifier.learn(draft.merchant, draft.selectType.id, draft.accountType);
        imported++;
      } catch (err) {
        Logger.error('导入账单失败', (err as Error).message);
      }
    }
    if (imported <= 0) {
      Toast.error($r('app.string.require_amount_type'));
      return;
    }
    Toast.success($r('app.string.save_success'));
    router.back();
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
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.font_1'))
      Text($r('app.string.pick_tip'))
        .fontSize(13)
        .fontColor($r('app.color.font_2'))
        .textAlign(TextAlign.Center)
      Button($r('app.string.pick_from_camera'))
        .width('100%')
        .height(48)
        .fontSize(16)
        .backgroundColor($r('app.color.green'))
        .fontColor($r('app.color.white'))
        .type(ButtonType.Normal)
        .borderRadius(SPACE_SMALL)
        .margin({ top: SPACE_LARGE })
        .onClick(() => {
          this.pickFromCamera();
        })
      Button($r('app.string.pick_from_gallery'))
        .width('100%')
        .height(48)
        .fontSize(16)
        .backgroundColor($r('app.color.white'))
        .fontColor($r('app.color.font_3'))
        .type(ButtonType.Normal)
        .borderRadius(SPACE_SMALL)
        .onClick(() => {
          this.pickFromGallery();
        })
      Text($r('app.string.settings_entry'))
        .fontSize(14)
        .fontColor($r('app.color.green'))
        .margin({ top: SPACE_SMALL })
        .onClick(() => {
          router.pushUrl({ url: 'pages/Settings' }).catch((err: Error): void => {
            Logger.error('跳转设置页失败', err.message);
          });
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
          .color($r('app.color.green'))
      } else if (task.status === ImageTaskStatus.SUCCESS) {
        Image($r('app.media.success'))
          .width(16)
          .height(16)
          .fillColor($r('app.color.green'))
      } else if (task.status === ImageTaskStatus.FAILED) {
        Image($r('app.media.error'))
          .width(16)
          .height(16)
          .fillColor($r('app.color.red'))
      } else {
        Column()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor($r('app.color.grey_2'))
      }
      Text($r('app.string.task_index', index + 1))
        .fontSize(14)
        .fontColor($r('app.color.font_1'))
        .layoutWeight(1)
      if (task.status === ImageTaskStatus.SUCCESS) {
        Text($r('app.string.task_success_count', task.drafts.length))
          .fontSize(12)
          .fontColor($r('app.color.green'))
      } else if (task.status === ImageTaskStatus.FAILED) {
        Text($r('app.string.task_failed'))
          .fontSize(12)
          .fontColor($r('app.color.red'))
      }
    }
    .width('100%')
    .height(40)
    .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM })
    .backgroundColor($r('app.color.white'))
    .borderRadius(SPACE_SMALL)
  }

  @Builder RecognizingPanel() {
    Column({ space: SPACE_MEDIUM }) {
      Text($r('app.string.recognizing'))
        .fontSize(15)
        .fontColor($r('app.color.font_1'))
        .margin({ bottom: SPACE_SMALL })
      List({ space: SPACE_SMALL }) {
        ForEach(this.tasks, (task: ImageTask, index: number) => {
          ListItem() {
            this.TaskItem(task, index)
          }
        }, (task: ImageTask, index: number) => task.uri + index)
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
            .fontSize(14)
            .fontColor($r('app.color.font_3'))
          TextInput({ text: this.amountText, placeholder: $r('app.string.amount_placeholder') })
            .type(InputType.NUMBER_DECIMAL)
            .fontSize(16)
            .fontColor($r('app.color.font_3'))
            .textAlign(TextAlign.End)
            .layoutWeight(1)
            .backgroundColor($r('app.color.white'))
            .onChange((value: string) => {
              this.amountText = value;
            })
        }.width('100%').height(44)
        Divider().color($r('app.color.grey_1'))
        Row() {
          Text($r('app.string.merchant_label'))
            .width(64)
            .fontSize(14)
            .fontColor($r('app.color.font_3'))
          TextInput({ text: this.merchant, placeholder: $r('app.string.merchant_placeholder') })
            .fontSize(16)
            .fontColor($r('app.color.font_3'))
            .textAlign(TextAlign.End)
            .layoutWeight(1)
            .backgroundColor($r('app.color.white'))
            .onChange((value: string) => {
              this.merchant = value;
            })
        }.width('100%').height(44)
        Divider().color($r('app.color.grey_1'))
        Row({ space: SPACE_SMALL }) {
          Image($r('app.media.date'))
            .width(14)
            .objectFit(ImageFit.Contain)
          Text(dayjs(this.selectedDate).format('YYYY-MM-DD'))
            .fontSize(14)
            .fontColor($r('app.color.font_3'))
        }.width('100%').height(44)
        .onClick(() => {
          this.showDatePicker();
        })
      }
      .width('100%')
      .padding(SPACE_LARGE)
      .backgroundColor($r('app.color.white'))
      .borderRadius(RADIUS_CARD)

      Row({ space: SPACE_MEDIUM }) {
        Button($r('app.string.expenditure'))
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .fontColor(this.accountType === AccountType.EXPENSES ? $r('app.color.white') : $r('app.color.font_2'))
          .backgroundColor(this.accountType === AccountType.EXPENSES ? $r('app.color.green') : $r('app.color.white'))
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .onClick(() => {
            this.onAccountTypeChange(AccountType.EXPENSES);
          })
        Button($r('app.string.income'))
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .fontColor(this.accountType === AccountType.INCOME ? $r('app.color.white') : $r('app.color.font_2'))
          .backgroundColor(this.accountType === AccountType.INCOME ? $r('app.color.green') : $r('app.color.white'))
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
                      .fillColor(this.selectType?.id === item.id ? $r('app.color.white') : $r('app.color.font_2'))
                  }.width(36)
                  .height(36)
                  .borderRadius(18)
                  .alignItems(HorizontalAlign.Center)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(this.selectType?.id === item.id ? item.activeColor : $r('app.color.grey_1'))
                  if (this.selectType?.id === item.id && this.autoClassified) {
                    Text($r('app.string.auto_classified'))
                      .fontSize(8)
                      .fontColor($r('app.color.white'))
                      .backgroundColor($r('app.color.orange'))
                      .borderRadius(4)
                      .padding({ left: 2, right: 2, top: 1, bottom: 1 })
                  }
                }.width(36).height(36)
                Text(item.name).fontSize(12)
                  .fontColor(this.selectType?.id === item.id ? $r('app.color.font_3') : $r('app.color.font_2'))
                  .lineHeight(15)
              }.onClick(() => {
                this.selectType = item;
                this.autoClassified = false;
              })
            }.width('100%')
          }, (item: AccountTypeModel) => item.id.toString())
        }.columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(16)
        .width('100%')
        .height(this.getGridHeight())
      }
      .width('100%')
      .padding(SPACE_LARGE)
      .backgroundColor($r('app.color.white'))
      .borderRadius(RADIUS_CARD)
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
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.font_3'))
            Text(draft.merchant)
              .fontSize(13)
              .fontColor($r('app.color.font_2'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Row({ space: SPACE_SMALL }) {
            Text(draft.selectType?.name ?? '')
              .fontSize(12)
              .fontColor($r('app.color.font_2'))
            Text(dayjs(draft.payTime).format('YYYY-MM-DD HH:mm'))
              .fontSize(12)
              .fontColor($r('app.color.font_2'))
          }
        }.alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .onClick(() => {
          this.toggleExpand(index);
        })
        Text($r('app.string.delete'))
          .fontSize(13)
          .fontColor($r('app.color.red'))
          .onClick(() => {
            this.deleteDraft(index);
          })
      }.width('100%')
      .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM, top: SPACE_SMALL, bottom: SPACE_SMALL })

      if (draft.duplicated) {
        Text($r('app.string.duplicated_tip'))
          .fontSize(11)
          .fontColor($r('app.color.orange'))
          .width('100%')
          .padding({ left: SPACE_MEDIUM, bottom: SPACE_TINY })
      }

      if (this.expandedIndex === index) {
        this.EditPanel(index)
      }
    }
    .width('100%')
    .backgroundColor(draft.duplicated ? $r('app.color.red_alpha') : $r('app.color.white'))
    .borderRadius(RADIUS_CARD)
  }

  @Builder ConfirmPanel() {
    Column({ space: SPACE_MEDIUM }) {
      Row({ space: SPACE_MEDIUM }) {
        Text($r('app.string.recognize_confirm_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.font_1'))
          .layoutWeight(1)
        Button($r('app.string.import_selected'))
          .height(40)
          .fontSize(15)
          .backgroundColor($r('app.color.green'))
          .fontColor($r('app.color.white'))
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .onClick(() => {
            this.onImportSelected();
          })
      }.width('100%')

      // 失败项：可单独重试
      ForEach(this.tasks, (task: ImageTask, index: number) => {
        if (task.status === ImageTaskStatus.FAILED) {
          Row({ space: SPACE_SMALL }) {
            Image($r('app.media.error'))
              .width(14)
              .height(14)
              .fillColor($r('app.color.red'))
            Text(task.error)
              .fontSize(12)
              .fontColor($r('app.color.red'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text($r('app.string.retry'))
              .fontSize(13)
              .fontColor($r('app.color.green'))
              .onClick(() => {
                this.retryTask(index);
              })
          }.width('100%')
          .height(40)
          .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM })
          .backgroundColor($r('app.color.white'))
          .borderRadius(SPACE_SMALL)
        }
      }, (task: ImageTask, index: number) => 'failed_' + index)

      List({ space: SPACE_SMALL }) {
        ForEach(this.drafts, (draft: BillDraft, index: number) => {
          ListItem() {
            this.DraftItem(draft, index)
          }
        }, (draft: BillDraft, index: number) => draft.imageUri + '_' + index)
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
    .backgroundColor($r('app.color.bg'))
  }
}
