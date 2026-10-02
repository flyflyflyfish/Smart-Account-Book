import router from '@ohos.router';
import dayjs from 'dayjs';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { CloudLlmRecognizer } from '../service/recognition/CloudLlmRecognizer';
import CloudLlmConfigStore from '../service/recognition/CloudLlmConfigStore';
import {
  ChatContent,
  ChatMessage,
  CloudLlmConfig
} from '../models/recognition/CloudLlmModels';
import { AccountInfo, AccountType, StatsResultByType } from '../models/account/account';
import AccountTypeModel from '../models/accountType/AccountTypeModel';
import CategoryRegistry from '../models/accountType/CategoryRegistry';
import AccountService from '../service/account';
import StatsService from '../service/stats';
import { VoiceBillParser, ParsedVoiceBill } from '../service/recognition/VoiceBillParser';
import { SOURCE_MANUAL } from '../common/constants';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

const AI_GREETING: string = '你好，我是你的记账助手，可以帮你记一笔，也能分析消费、生成小结。';

interface ChatBubble {
  role: string;
  content: string;
}

interface BillDraft {
  amount: number;
  amountText: string;
  accountType: AccountType;
  category: AccountTypeModel;
  merchant: string;
  time: number;
}

interface RecognizerOption {
  enablePartialResult: boolean;
}

interface AiBillItem {
  accountType: string;
  amount: number;
  category: string;
  merchant: string;
  date: string;
}

interface AiBookResponse {
  action: string;
  bills: AiBillItem[];
}

/**
 * AI 助手：文本/语音本地解析记账；解析不了的走云端大模型，AI 也可输出结构化账单入账
 */
@Component
export default struct AiAssistant {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }
  @State chatList: ChatBubble[] = [];
  @State inputText: string = '';
  @State loading: boolean = false;
  @State configMissing: boolean = false;
  @State config: CloudLlmConfig = { baseUrl: '', apiKey: '', model: '' };
  // 语音识别状态
  @State listening: boolean = false;
  @State partialText: string = '';
  @State billDrafts: BillDraft[] = [];
  @State editingIndex: number = -1;
  @State editAmountText: string = '';
  @State editMerchant: string = '';
  @State editAccountType: AccountType = AccountType.EXPENSES;
  @State editCategory: AccountTypeModel | undefined = undefined;
  @State editTime: number = 0;
  private scroller: Scroller = new Scroller();
  private asrEngine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  private sessionId: string = '';
  private finalText: string = '';

  async aboutToAppear(): Promise<void> {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.config = await CloudLlmConfigStore.loadConfig();
    this.configMissing = !this.config.baseUrl || !this.config.apiKey || !this.config.model;
    const greeting: ChatBubble = { role: 'assistant', content: AI_GREETING };
    this.chatList = [greeting];
    await this.initAsrEngine();
  }

  aboutToDisappear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);
    if (this.asrEngine) {
      try {
        this.asrEngine.shutdown();
      } catch (err) {
        Logger.error('关闭语音引擎失败', (err as Error).message);
      }
      this.asrEngine = undefined;
    }
  }

  async initAsrEngine(): Promise<void> {
    try {
      const extraParams: Record<string, Object> = { 'locate': 'CN', 'recognizerMode': 'short' };
      const params: speechRecognizer.CreateEngineParams = {
        language: 'zh-CN',
        online: 1,
        extraParams: extraParams
      };
      this.asrEngine = await speechRecognizer.createEngine(params);
      this.asrEngine.setListener(this.buildListener());
    } catch (err) {
      Logger.error('初始化语音识别失败', (err as Error).message);
    }
  }

  buildListener(): speechRecognizer.RecognitionListener {
    const listener: speechRecognizer.RecognitionListener = {
      onStart: (sessionId: string, eventMessage: string): void => {
      },
      onEvent: (sessionId: string, eventCode: number, eventMessage: string): void => {
      },
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult): void => {
        if (result.isFinal) {
          this.finalText = result.result;
        } else {
          this.partialText = result.result;
        }
      },
      onComplete: (sessionId: string, eventMessage: string): void => {
        this.listening = false;
        this.partialText = '';
        this.handleFinalText(this.finalText);
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string): void => {
        this.listening = false;
        this.partialText = '';
        Logger.error('语音识别错误', String(errorCode), errorMessage);
        Toast.error($r('app.string.voice_failed'));
      }
    };
    return listener;
  }

  async ensureMicPermission(): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const result = await atManager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
      return result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (err) {
      Logger.error('申请麦克风权限失败', (err as Error).message);
      return false;
    }
  }

  async startVoice(): Promise<void> {
    if (!this.asrEngine) {
      Toast.error($r('app.string.voice_unavailable'));
      return;
    }
    const granted = await this.ensureMicPermission();
    if (!granted) {
      Toast.error($r('app.string.mic_permission_denied'));
      return;
    }
    this.sessionId = 'voice_' + Date.now();
    this.finalText = '';
    this.partialText = '';
    const recognizerOption: RecognizerOption = { enablePartialResult: true };
    const extraParams: Record<string, Object> = {
      'recognitionMode': 0,
      'vadBegin': 2000,
      'vadEnd': 800,
      'maxAudioDuration': 20000,
      'recognizerOption': recognizerOption
    };
    const params: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 },
      extraParams: extraParams
    };
    try {
      this.asrEngine.startListening(params);
      this.listening = true;
    } catch (err) {
      Logger.error('启动语音识别失败', (err as Error).message);
      Toast.error($r('app.string.voice_failed'));
    }
  }

  stopVoice(): void {
    if (this.asrEngine && this.listening) {
      try {
        this.asrEngine.finish(this.sessionId);
      } catch (err) {
        Logger.error('结束语音识别失败', (err as Error).message);
      }
    }
  }

  handleFinalText(text: string): void {
    this.processUserInput(text);
  }

  // 本地解析（支持一句话多笔），成功则弹确认卡片
  tryParseAsBills(text: string): boolean {
    const parsedList = VoiceBillParser.parseMultiple(text);
    if (parsedList.length === 0) {
      return false;
    }
    this.showBillDrafts(parsedList);
    return true;
  }

  // 把解析结果转成草稿并展示
  showBillDrafts(parsedList: ParsedVoiceBill[]): void {
    const drafts: BillDraft[] = [];
    for (const parsed of parsedList) {
      const category = CategoryRegistry.getById(parsed.categoryId, parsed.accountType);
      if (!category) {
        continue;
      }
      const draft: BillDraft = {
        amount: parsed.amount,
        amountText: parsed.amount.toFixed(2),
        accountType: parsed.accountType,
        category: category,
        merchant: parsed.merchant,
        time: parsed.time
      };
      drafts.push(draft);
    }
    if (drafts.length > 0) {
      this.billDrafts = drafts;
    }
  }

  async confirmBillDrafts(): Promise<void> {
    const drafts = this.billDrafts;
    if (drafts.length === 0) {
      return;
    }
    let okCount = 0;
    let total = 0;
    for (const draft of drafts) {
      const info: AccountInfo = {
        accountType: draft.accountType,
        type: draft.category.id,
        amount: draft.amount,
        time: dayjs(draft.time).startOf('day').valueOf(),
        merchant: draft.merchant,
        description: draft.merchant,
        source: SOURCE_MANUAL,
        payTime: draft.time
      };
      try {
        await AccountService.insert(info);
        okCount++;
        total += draft.amount;
      } catch (err) {
        Logger.error('记账失败', (err as Error).message);
      }
    }
    this.billDrafts = [];
    if (okCount <= 0) {
      Toast.error($r('app.string.save_failed'));
      return;
    }
    Toast.success($r('app.string.save_success'));
    let tip = '';
    if (drafts.length === 1) {
      const typeLabel = drafts[0].accountType === AccountType.EXPENSES ? '支出' : '收入';
      const merchantText = drafts[0].merchant.length > 0 ? drafts[0].merchant + ' ' : '';
      tip = '已记一笔' + typeLabel + '：' + merchantText + '¥' + drafts[0].amount.toFixed(2);
    } else {
      tip = '已记' + drafts.length + '笔，共 ¥' + total.toFixed(2);
    }
    this.chatList.push({ role: 'assistant', content: tip });
    this.chatList = this.chatList.slice();
    this.scrollToBottom();
  }

  cancelBillDrafts(): void {
    this.billDrafts = [];
  }

  removeBillDraft(index: number): void {
    if (index < 0 || index >= this.billDrafts.length) {
      return;
    }
    this.billDrafts.splice(index, 1);
    this.billDrafts = this.billDrafts.slice();
  }

  startEdit(index: number): void {
    if (index < 0 || index >= this.billDrafts.length) {
      return;
    }
    const draft = this.billDrafts[index];
    this.editingIndex = index;
    this.editAmountText = draft.amountText;
    this.editMerchant = draft.merchant;
    this.editAccountType = draft.accountType;
    this.editCategory = draft.category;
    this.editTime = draft.time;
  }

  saveEdit(): void {
    const index = this.editingIndex;
    if (index < 0 || index >= this.billDrafts.length) {
      return;
    }
    const amount = parseFloat(this.editAmountText);
    const category = this.editCategory;
    if (!(amount > 0) || !category) {
      Toast.error($r('app.string.require_amount_type'));
      return;
    }
    const draft: BillDraft = {
      amount: amount,
      amountText: amount.toFixed(2),
      accountType: this.editAccountType,
      category: category,
      merchant: this.editMerchant,
      time: this.editTime
    };
    this.billDrafts.splice(index, 1, draft);
    this.billDrafts = this.billDrafts.slice();
    this.editingIndex = -1;
  }

  cancelEdit(): void {
    this.editingIndex = -1;
  }

  showEditDatePicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-1-1'),
      end: new Date(),
      selected: new Date(this.editTime),
      onDateAccept: (value: Date) => {
        const origin = dayjs(this.editTime);
        this.editTime = dayjs(value).hour(origin.hour()).minute(origin.minute()).valueOf();
      }
    });
  }

  getEditGridHeight(): number {
    const count = CategoryRegistry.list(this.editAccountType).length;
    const rows = Math.ceil(count / 4);
    if (rows <= 0) {
      return 0;
    }
    return rows * 48 + (rows - 1) * SPACE_SMALL;
  }

  resolveName(name: ResourceStr): string {
    if (typeof name === 'string') {
      return name;
    }
    return getContext(this).resourceManager.getStringSync(name);
  }

  // 把全部历史账单 + 当月账单汇总成纯文本，作为上下文喂给大模型
  async buildBillContext(): Promise<string> {
    try {
      const now = dayjs();
      const allRes = await AccountService.queryByDateRange(dayjs('2020-01-01').valueOf(), now.valueOf());
      const allType = StatsService.statsConsumeByType(allRes);
      let ctx = '以下是用户的记账数据（供你分析参考，不要编造）：\n';
      ctx += '全部累计：支出 ¥' + allType.expenses.toFixed(2) + '，收入 ¥' + allType.income.toFixed(2);
      ctx = this.appendTypeSummary(ctx, allType, '全部支出分类', '全部收入分类');

      const monthRes = await AccountService.getAccountByMonth(now.valueOf());
      const monthType = StatsService.statsConsumeByType(monthRes);
      ctx += '\n本月：支出 ¥' + monthType.expenses.toFixed(2) + '，收入 ¥' + monthType.income.toFixed(2);
      ctx = this.appendTypeSummary(ctx, monthType, '本月支出分类', '本月收入分类');
      return ctx;
    } catch (err) {
      Logger.error('构建账单上下文失败', (err as Error).message);
      return '';
    }
  }

  // 把分类汇总追加到上下文文本
  appendTypeSummary(ctx: string, typeStats: StatsResultByType, expenseLabel: string, incomeLabel: string): string {
    let result = ctx;
    if (typeStats.data.expenses.length > 0) {
      result += '\n' + expenseLabel + '：';
      for (const item of typeStats.data.expenses) {
        result += this.resolveName(item.info.name) + '¥' + item.amount.toFixed(2) + '(' + item.count + '笔)、';
      }
    }
    if (typeStats.data.income.length > 0) {
      result += '\n' + incomeLabel + '：';
      for (const item of typeStats.data.income) {
        result += this.resolveName(item.info.name) + '¥' + item.amount.toFixed(2) + '(' + item.count + '笔)、';
      }
    }
    return result;
  }

  // 动态 system prompt：带上分类列表，引导 AI 在记账意图时输出结构化 JSON
  buildSystemPrompt(): string {
    const expenseNames = CategoryRegistry.listNames(AccountType.EXPENSES).join('、');
    const incomeNames = CategoryRegistry.listNames(AccountType.INCOME).join('、');
    return '你是记账助手。用户描述消费时，你负责理解意图并把金额、分类、商家整理成结构化数据。' +
      '支出分类只能是：' + expenseNames + '。收入分类只能是：' + incomeNames + '。' +
      '当用户明确要记账时，只回复一个 JSON 对象（不要任何其他文字、不要 markdown 代码块）：' +
      '{"action":"book","bills":[{"accountType":"支出或收入","amount":数字,"category":"分类名","merchant":"商家名","date":"日期描述"}]}。' +
      'date 用中文日期描述，例如：今天、昨天、前天、3月5日、3月5日8点；不确定就写"今天"。' +
      '一句话可能有多笔账单时，bills 数组放多个元素。' +
      '其他问题请用纯文本回复，不要使用 markdown 格式。';
  }

  async buildMessages(bubbles: ChatBubble[]): Promise<ChatMessage[]> {
    const messages: ChatMessage[] = [];
    const sysContent: ChatContent = { type: 'text', text: this.buildSystemPrompt() };
    messages.push({ role: 'system', content: [sysContent] });
    const billContext = await this.buildBillContext();
    if (billContext.length > 0) {
      const ctxContent: ChatContent = { type: 'text', text: billContext };
      messages.push({ role: 'system', content: [ctxContent] });
    }
    for (const b of bubbles) {
      const c: ChatContent = { type: 'text', text: b.content };
      messages.push({ role: b.role, content: [c] });
    }
    return messages;
  }

  // 解析 AI 返回的记账 JSON，返回多笔账单（解析失败返回空数组）
  parseAiBookBills(reply: string): ParsedVoiceBill[] {
    let jsonStr = reply.trim();
    const fence = jsonStr.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (fence && fence.length > 1) {
      jsonStr = fence[1].trim();
    } else {
      const start = jsonStr.indexOf('{');
      const end = jsonStr.lastIndexOf('}');
      if (start < 0 || end <= start) {
        return [];
      }
      jsonStr = jsonStr.substring(start, end + 1);
    }
    try {
      const parsed = JSON.parse(jsonStr) as AiBookResponse;
      if (parsed.action !== 'book' || !parsed.bills) {
        return [];
      }
      const result: ParsedVoiceBill[] = [];
      for (const item of parsed.bills) {
        const amount = typeof item.amount === 'number' ? item.amount : parseFloat(String(item.amount));
        if (!(amount > 0)) {
          continue;
        }
        const accountType = item.accountType === '收入' ? AccountType.INCOME : AccountType.EXPENSES;
        const category = CategoryRegistry.getByName(item.category, accountType);
        if (!category) {
          continue;
        }
        const bill: ParsedVoiceBill = {
          amount: amount,
          accountType: accountType,
          categoryId: category.id,
          merchant: typeof item.merchant === 'string' ? item.merchant : '',
          time: VoiceBillParser.resolveTime(typeof item.date === 'string' ? item.date : '')
        };
        result.push(bill);
      }
      return result;
    } catch (err) {
      return [];
    }
  }

  // 简单清洗 markdown 标记，让 AI 回复在纯文本组件里可读
  stripMarkdown(text: string): string {
    let s = text;
    s = s.replace(/\*\*/g, '');
    s = s.replace(/`/g, '');
    s = s.replace(/^#{1,6}\s*/gm, '');
    s = s.replace(/^\s*[-*+]\s+/gm, '· ');
    s = s.replace(/^\s*\d+[.)]\s+/gm, '');
    s = s.replace(/\[(.+?)\]\(.+?\)/g, '$1');
    return s;
  }

  scrollToBottom(): void {
    this.scroller.scrollEdge(Edge.Bottom);
  }

  // 统一处理用户输入（文本或语音识别结果）：先本地解析记账，失败再走云端 AI
  async processUserInput(text: string): Promise<void> {
    const trimmed = text.trim();
    if (!trimmed || this.loading) {
      return;
    }
    this.inputText = '';
    this.chatList.push({ role: 'user', content: trimmed });
    this.chatList = this.chatList.slice();
    this.scrollToBottom();
    if (this.tryParseAsBills(trimmed)) {
      return;
    }
    if (this.configMissing) {
      return;
    }
    this.loading = true;
    try {
      const recognizer = new CloudLlmRecognizer(this.config);
      const reply = await recognizer.chat(await this.buildMessages(this.chatList));
      const aiBills = this.parseAiBookBills(reply);
      if (aiBills.length > 0) {
        this.showBillDrafts(aiBills);
      } else {
        this.chatList.push({ role: 'assistant', content: reply });
      }
    } catch (err) {
      const e = err as Error;
      this.chatList.push({ role: 'assistant', content: e.message });
    } finally {
      this.loading = false;
      this.chatList = this.chatList.slice();
      this.scrollToBottom();
    }
  }

  async send(): Promise<void> {
    await this.processUserInput(this.inputText);
  }

  @Builder Bubble(bubble: ChatBubble) {
    Row() {
      if (bubble.role === 'user') {
        Blank()
        Text(bubble.content)
          .fontSize(this.fs(15))
          .fontColor(this.tk().surface)
          .textAlign(TextAlign.Start)
          .backgroundColor(this.tk().primary)
          .borderRadius({ topLeft: 14, topRight: 14, bottomLeft: 14, bottomRight: 4 })
          .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM, top: SPACE_SMALL, bottom: SPACE_SMALL })
          .constraintSize({ maxWidth: '80%' })
      } else {
        Text(this.stripMarkdown(bubble.content))
          .fontSize(this.fs(15))
          .fontColor(this.tk().textPrimary)
          .textAlign(TextAlign.Start)
          .backgroundColor(this.tk().surface)
          .borderRadius({ topLeft: 14, topRight: 14, bottomLeft: 4, bottomRight: 14 })
          .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM, top: SPACE_SMALL, bottom: SPACE_SMALL })
          .constraintSize({ maxWidth: '80%' })
        Blank()
      }
    }
    .width('100%')
  }

  @Builder EditPanel() {
    Column({ space: SPACE_SMALL }) {
      Row({ space: SPACE_SMALL }) {
        Text($r('app.string.amount_label'))
          .width(56)
          .fontSize(this.fs(14))
          .fontColor(this.tk().textSecondary)
        TextInput({ text: this.editAmountText, placeholder: $r('app.string.amount_placeholder') })
          .type(InputType.NUMBER_DECIMAL)
          .fontSize(this.fs(15))
          .fontColor(this.tk().textPrimary)
          .textAlign(TextAlign.End)
          .layoutWeight(1)
          .backgroundColor(this.tk().surface)
          .onChange((value: string) => {
            this.editAmountText = value;
          })
      }.width('100%').height(40)

      Row({ space: SPACE_SMALL }) {
        Text($r('app.string.merchant_label'))
          .width(56)
          .fontSize(this.fs(14))
          .fontColor(this.tk().textSecondary)
        TextInput({ text: this.editMerchant, placeholder: $r('app.string.merchant_placeholder') })
          .fontSize(this.fs(15))
          .fontColor(this.tk().textPrimary)
          .textAlign(TextAlign.End)
          .layoutWeight(1)
          .backgroundColor(this.tk().surface)
          .onChange((value: string) => {
            this.editMerchant = value;
          })
      }.width('100%').height(40)

      Row({ space: SPACE_SMALL }) {
        Button($r('app.string.expenditure'))
          .layoutWeight(1)
          .height(36)
          .fontSize(this.fs(14))
          .fontColor(this.editAccountType === AccountType.EXPENSES ? this.tk().surface : this.tk().textSecondary)
          .backgroundColor(this.editAccountType === AccountType.EXPENSES ? this.tk().primary : this.tk().surfaceVariant)
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .onClick(() => {
            this.editAccountType = AccountType.EXPENSES;
            this.editCategory = undefined;
          })
        Button($r('app.string.income'))
          .layoutWeight(1)
          .height(36)
          .fontSize(this.fs(14))
          .fontColor(this.editAccountType === AccountType.INCOME ? this.tk().surface : this.tk().textSecondary)
          .backgroundColor(this.editAccountType === AccountType.INCOME ? this.tk().primary : this.tk().surfaceVariant)
          .type(ButtonType.Normal)
          .borderRadius(SPACE_SMALL)
          .onClick(() => {
            this.editAccountType = AccountType.INCOME;
            this.editCategory = undefined;
          })
      }.width('100%')

      Grid() {
        ForEach(CategoryRegistry.list(this.editAccountType), (item: AccountTypeModel) => {
          GridItem() {
            Column({ space: 2 }) {
              Column() {
                Image(item.icon)
                  .width(16)
                  .height(16)
                  .fillColor(this.editCategory?.id === item.id ? this.tk().surface : this.tk().textSecondary)
              }
              .width(32)
              .height(32)
              .borderRadius(16)
              .backgroundColor(this.editCategory?.id === item.id ? item.activeColor : this.tk().surfaceVariant)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              Text(item.name)
                .fontSize(this.fs(11))
                .fontColor(this.editCategory?.id === item.id ? this.tk().textPrimary : this.tk().textSecondary)
            }
            .onClick(() => {
              this.editCategory = item;
            })
          }
        }, (item: AccountTypeModel) => item.id.toString())
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsGap(SPACE_SMALL)
      .columnsGap(SPACE_SMALL)
      .width('100%')
      .height(this.getEditGridHeight())

      Row({ space: SPACE_SMALL }) {
        Text(dayjs(this.editTime).format('YYYY-MM-DD HH:mm'))
          .fontSize(this.fs(13))
          .fontColor(this.tk().textPrimary)
          .onClick(() => {
            this.showEditDatePicker();
          })
        Blank()
        Text($r('app.string.cancel'))
          .fontSize(this.fs(13))
          .fontColor(this.tk().textSecondary)
          .onClick(() => {
            this.cancelEdit();
          })
        Text($r('app.string.finish'))
          .fontSize(this.fs(13))
          .fontColor(this.tk().primary)
          .onClick(() => {
            this.saveEdit();
          })
      }.width('100%').height(32)
    }
    .width('100%')
    .padding(SPACE_MEDIUM)
    .backgroundColor(this.tk().surfaceVariant)
    .borderRadius(SPACE_SMALL)
    .margin({ top: SPACE_SMALL })
  }

  @Builder BillDraftCard() {
    Column({ space: SPACE_SMALL }) {
      Row() {
        Text($r('app.string.voice_result_title'))
          .fontSize(this.fs(14))
          .fontColor(this.tk().textSecondary)
        Blank()
        Text($r('app.string.cancel'))
          .fontSize(this.fs(13))
          .fontColor(this.tk().textSecondary)
          .onClick(() => {
            this.cancelBillDrafts();
          })
      }.width('100%')

      ForEach(this.billDrafts, (draft: BillDraft, index: number) => {
        Column() {
          Row({ space: SPACE_MEDIUM }) {
            Column() {
              Image(draft.category.icon)
                .width(20)
                .height(20)
                .fillColor(this.tk().surface)
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(draft.category.activeColor)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)

            Column({ space: 2 }) {
              Text(draft.category.name)
                .fontSize(this.fs(15))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.tk().textPrimary)
              if (draft.merchant.length > 0) {
                Text(draft.merchant)
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().textSecondary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text((draft.accountType === AccountType.EXPENSES ? '-' : '+') + '¥' + draft.amountText)
              .fontSize(this.fs(16))
              .fontWeight(FontWeight.Medium)
              .fontColor(draft.accountType === AccountType.EXPENSES ? this.tk().textPrimary : this.tk().primary)

            Text($r('app.string.edit'))
              .fontSize(this.fs(12))
              .fontColor(this.tk().primary)
              .onClick(() => {
                this.startEdit(index);
              })

            Text($r('app.string.delete'))
              .fontSize(this.fs(12))
              .fontColor(this.tk().danger)
              .onClick(() => {
                this.removeBillDraft(index);
              })
          }.width('100%')

          if (this.editingIndex === index) {
            this.EditPanel()
          }
        }.width('100%')
      }, (draft: BillDraft, index: number) => index.toString() + draft.amountText + draft.merchant)

      Button($r('app.string.confirm_save'))
        .width('100%')
        .height(40)
        .fontSize(this.fs(15))
        .fontColor(this.tk().surface)
        .backgroundColor(this.tk().primary)
        .type(ButtonType.Normal)
        .borderRadius(SPACE_SMALL)
        .margin({ top: SPACE_TINY })
        .onClick(() => {
          this.confirmBillDrafts();
        })
    }
    .width('100%')
    .padding(SPACE_MEDIUM)
    .backgroundColor(this.tk().surface)
    .borderRadius(RADIUS_CARD)
    .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
    .margin({ left: SPACE_LARGE, right: SPACE_LARGE, bottom: SPACE_SMALL })
  }

  build() {
    Column() {
      Text($r('app.string.ai_assistant'))
        .width('100%')
        .fontSize(this.fs(24))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tk().textPrimary)
        .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_LARGE })

      if (this.configMissing) {
        Row({ space: SPACE_SMALL }) {
          Text($r('app.string.ai_config_missing'))
            .fontSize(this.fs(13))
            .fontColor(this.tk().textSecondary)
            .layoutWeight(1)
          Button($r('app.string.ai_configure_model'))
            .height(30)
            .fontSize(this.fs(13))
            .fontColor(this.tk().surface)
            .backgroundColor(this.tk().primary)
            .type(ButtonType.Normal)
            .borderRadius(SPACE_SMALL)
            .onClick(() => {
              router.pushUrl({ url: 'pages/ModelSettings' });
            })
        }
        .width('100%')
        .padding(SPACE_MEDIUM)
        .backgroundColor(this.tk().surface)
        .margin({ left: SPACE_LARGE, right: SPACE_LARGE, bottom: SPACE_SMALL })
        .borderRadius(RADIUS_CARD)
        .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
      }

      List({ space: SPACE_SMALL, scroller: this.scroller }) {
        ForEach(this.chatList, (bubble: ChatBubble) => {
          ListItem() {
            this.Bubble(bubble)
          }
        }, (bubble: ChatBubble, index: number) => index.toString() + bubble.role)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_MEDIUM })

      if (this.billDrafts.length > 0) {
        this.BillDraftCard()
      }

      Row({ space: SPACE_SMALL }) {
        Column() {
          Image($r('app.media.mic'))
            .width(20)
            .height(20)
            .fillColor(this.listening ? this.tk().surface : this.tk().primary)
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(this.listening ? this.tk().danger : this.tk().primarySoft)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.startVoice();
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.stopVoice();
          }
        })
        TextInput({
          placeholder: this.listening ? $r('app.string.voice_listening') : $r('app.string.ai_input_hint'),
          text: this.listening ? this.partialText : this.inputText
        })
          .fontSize(this.fs(15))
          .fontColor(this.tk().textPrimary)
          .layoutWeight(1)
          .backgroundColor(this.tk().surface)
          .borderRadius(20)
          .onChange((value: string) => {
            this.inputText = value;
          })
        Button(this.loading ? $r('app.string.ai_thinking') : $r('app.string.ai_send'))
          .height(40)
          .fontSize(this.fs(14))
          .fontColor(this.tk().surface)
          .backgroundColor(this.configMissing || this.loading ? this.tk().outline : this.tk().primary)
          .type(ButtonType.Normal)
          .borderRadius(20)
          .padding({ left: SPACE_MEDIUM, right: SPACE_MEDIUM })
          .onClick(() => {
            this.send();
          })
      }
      .width('100%')
      .padding({ left: SPACE_LARGE, right: SPACE_LARGE, top: SPACE_SMALL, bottom: SPACE_LARGE })
      .backgroundColor(this.tk().surface)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }
}
