import AccountNavigator from '../components/Navigator';
import dayjs from 'dayjs';
import { picker } from '@kit.CoreFileKit';
import common from '@ohos.app.ability.common';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import { CloudLlmConfig, SavedProviderConfig } from '../models/recognition/CloudLlmModels';
import { LLM_PROVIDERS, LlmProvider, findProvider, findModelLabel } from '../models/recognition/LlmProviders';
import { SampleSummary } from '../models/recognition/OcrSample';
import CloudLlmConfigStore from '../service/recognition/CloudLlmConfigStore';
import { CloudLlmRecognizer } from '../service/recognition/CloudLlmRecognizer';
import { LocalOcrRecognizer } from '../service/recognition/LocalOcrRecognizer';
import OcrSampleCollector from '../service/recognition/OcrSampleCollector';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import BreakpointConstants from '../common/breakpoint';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY, SPACE_XLARGE } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

const REPLY_DISPLAY_MAX: number = 50;

@Entry
@Component
struct ModelSettings {

  @StorageProp('themeSeq') themeSeq: number = 0;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  @State providerIndex: number = 0;
  @State apiKey: string = '';
  @State model: string = '';
  @State modelIndex: number = 0;
  @State customBaseUrl: string = '';
  @State ocrEnabled: boolean = true;
  @State cloudEnabled: boolean = false;
  @State savedProviders: SavedProviderConfig[] = [];
  @State activeProviderId: string = '';
  @State testing: boolean = false;
  @State testResult: string = '';
  @State testSuccess: boolean = false;
  @State trainCollectEnabled: boolean = false;
  @State trainSampleCount: number = 0;
  @State ocrSupported: boolean = false;
  @State ocrTesting: boolean = false;
  @State ocrTestResult: string = '';
  @State ocrTestFullText: string = '';
  @State samples: SampleSummary[] = [];
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  async aboutToAppear(): Promise<void> {
    try {
      this.savedProviders = await CloudLlmConfigStore.loadProviders();
      this.activeProviderId = await CloudLlmConfigStore.loadActiveProvider();
      let initId = this.activeProviderId;
      if (!initId) {
        initId = this.savedProviders.length > 0 ? this.savedProviders[0].id : LLM_PROVIDERS[0].id;
      }
      this.selectProviderById(initId);
      this.ocrEnabled = await CloudLlmConfigStore.loadOcrEnabled();
      this.cloudEnabled = await CloudLlmConfigStore.loadCloudEnabled();
      this.trainCollectEnabled = await CloudLlmConfigStore.loadTrainCollectEnabled();
      this.trainSampleCount = await OcrSampleCollector.sampleCount(getContext(this) as common.Context);
      this.samples = await OcrSampleCollector.listSamples(getContext(this) as common.Context);
      this.ocrSupported = canIUse('SystemCapability.AI.OCR.TextRecognition');
    } catch (error) {
      Logger.error('加载设置失败', (error as Error).message);
    }
  }

  maskApiKey(key: string): string {
    if (key.length <= 7) {
      return key.length > 0 ? '****' : '';
    }
    return key.substring(0, 3) + '****' + key.substring(key.length - 4);
  }

  providerIndexOf(id: string): number {
    for (let i = 0; i < LLM_PROVIDERS.length; i++) {
      if (LLM_PROVIDERS[i].id === id) {
        return i;
      }
    }
    return 0;
  }

  modelIndexOf(provider: LlmProvider, modelId: string): number {
    for (let i = 0; i < provider.models.length; i++) {
      if (provider.models[i].id === modelId) {
        return i;
      }
    }
    return 0;
  }

  // 切换编辑目标服务商：有保存记录则回填，否则用该服务商第一个模型
  selectProviderById(id: string): void {
    this.providerIndex = this.providerIndexOf(id);
    const provider = LLM_PROVIDERS[this.providerIndex];
    const saved = this.savedProviders.find((p: SavedProviderConfig) => p.id === id);
    if (saved) {
      this.apiKey = saved.apiKey;
      this.customBaseUrl = saved.baseUrl;
      const idx = this.modelIndexOf(provider, saved.model);
      if (provider.custom) {
        // 自定义服务商：模型名完全由用户输入
        this.model = saved.model;
        this.modelIndex = idx;
      } else {
        // 固定服务商：保存的模型不在列表中（列表更新/数据异常）时回退到第一个模型，
        // 避免 Select 显示与实际 model 值不一致
        this.model = provider.models.length > 0 ? provider.models[idx].id : '';
        this.modelIndex = idx;
      }
    } else {
      this.apiKey = '';
      this.model = provider.models.length > 0 ? provider.models[0].id : '';
      this.modelIndex = 0;
      this.customBaseUrl = '';
    }
  }

  providerSelectOptions(): SelectOption[] {
    const arr: SelectOption[] = [];
    for (const p of LLM_PROVIDERS) {
      arr.push({ value: p.name });
    }
    return arr;
  }

  modelSelectOptions(): SelectOption[] {
    const arr: SelectOption[] = [];
    const provider = LLM_PROVIDERS[this.providerIndex];
    for (const m of provider.models) {
      arr.push({ value: m.label });
    }
    return arr;
  }

  // 保存当前编辑中的服务商（新增或覆盖）并设为当前使用
  async saveCurrentProvider(): Promise<void> {
    const provider = LLM_PROVIDERS[this.providerIndex];
    const baseUrl = provider.custom ? this.customBaseUrl.trim() : provider.baseUrl;
    const apiKey = this.apiKey.trim();
    const model = provider.custom ? this.model.trim() : this.model;
    if (!apiKey) {
      Toast.error($r('app.string.api_key_required'));
      return;
    }
    if (!baseUrl) {
      Toast.error($r('app.string.base_url_required'));
      return;
    }
    if (!model) {
      Toast.error($r('app.string.model_required'));
      return;
    }
    const entry: SavedProviderConfig = { id: provider.id, baseUrl: baseUrl, apiKey: apiKey, model: model };
    const updated = this.savedProviders.slice();
    const idx = updated.findIndex((p: SavedProviderConfig) => p.id === provider.id);
    if (idx >= 0) {
      updated[idx] = entry;
    } else {
      updated.push(entry);
    }
    // 先写盘成功再更新页面状态，避免持久化失败时 UI 与实际配置不一致
    try {
      await CloudLlmConfigStore.saveProviders(updated);
      this.savedProviders = updated;
      this.activeProviderId = provider.id;
      await CloudLlmConfigStore.setActiveProvider(this.activeProviderId);
      Toast.success($r('app.string.provider_saved'));
    } catch (error) {
      Logger.error('保存服务商失败', (error as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  async useProvider(id: string): Promise<void> {
    try {
      await CloudLlmConfigStore.setActiveProvider(id);
      this.activeProviderId = id;
      this.selectProviderById(id);
      Toast.success($r('app.string.provider_activated'));
    } catch (error) {
      Logger.error('切换服务商失败', (error as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  async deleteProvider(id: string): Promise<void> {
    const updated = this.savedProviders.filter((p: SavedProviderConfig) => p.id !== id);
    // 删除后新的当前服务商：删的是当前的则回退到列表第一个，没有则置空
    const nextActive = this.activeProviderId === id ?
      (updated.length > 0 ? updated[0].id : '') : this.activeProviderId;
    try {
      await CloudLlmConfigStore.saveProviders(updated);
      await CloudLlmConfigStore.setActiveProvider(nextActive);
      this.savedProviders = updated;
      this.activeProviderId = nextActive;
      // 重置表单：当前编辑的就是被删服务商时，避免表单残留已删除的 apiKey/模型
      this.selectProviderById(nextActive);
      Toast.success($r('app.string.provider_deleted'));
    } catch (error) {
      Logger.error('删除服务商失败', (error as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  confirmClearProviders(): void {
    AlertDialog.show({
      title: $r('app.string.delete_confirm_title'),
      message: $r('app.string.provider_clear_confirm_msg'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.confirm'),
        fontColor: this.tk().danger,
        action: () => {
          this.clearAllProviders();
        }
      }
    });
  }

  async clearAllProviders(): Promise<void> {
    try {
      await CloudLlmConfigStore.saveProviders([]);
      await CloudLlmConfigStore.setActiveProvider('');
      this.savedProviders = [];
      this.activeProviderId = '';
      // 重置表单，避免残留已清空的 apiKey/模型
      this.selectProviderById('');
      Toast.success($r('app.string.provider_clear_success'));
    } catch (error) {
      Logger.error('清空服务商失败', (error as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  async onSave(): Promise<void> {
    try {
      await CloudLlmConfigStore.saveOcrEnabled(this.ocrEnabled);
      await CloudLlmConfigStore.saveCloudEnabled(this.cloudEnabled);
      Toast.success($r('app.string.settings_saved'));
    } catch (error) {
      Logger.error('保存设置失败', (error as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  async onTestConnection(): Promise<void> {
    const provider = LLM_PROVIDERS[this.providerIndex];
    const config: CloudLlmConfig = {
      baseUrl: provider.custom ? this.customBaseUrl.trim() : provider.baseUrl,
      apiKey: this.apiKey.trim(),
      model: provider.custom ? this.model.trim() : this.model
    };
    this.testing = true;
    this.testResult = '';
    try {
      const reply = await new CloudLlmRecognizer(config).testConnection();
      this.testSuccess = true;
      this.testResult = getContext(this).resourceManager.getStringSync($r('app.string.test_success_prefix')) +
        this.truncateReply(reply);
    } catch (error) {
      this.testSuccess = false;
      this.testResult = (error as Error).message;
    } finally {
      this.testing = false;
    }
  }

  truncateReply(reply: string): string {
    const trimmed = reply.trim();
    if (trimmed.length <= REPLY_DISPLAY_MAX) {
      return trimmed;
    }
    return trimmed.substring(0, REPLY_DISPLAY_MAX) + '...';
  }

  // 导出训练数据：经系统保存选择器写为 .json，方便传到电脑
  async onExportSamples(): Promise<void> {
    const count = await OcrSampleCollector.sampleCount(getContext(this) as common.Context);
    if (count <= 0) {
      Toast.error($r('app.string.train_export_empty'));
      return;
    }
    try {
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = ['训练数据.json'];
      saveOptions.fileSuffixChoices = ['JSON 数据|.json'];
      const documentPicker = new picker.DocumentViewPicker(getContext(this));
      const uris = await documentPicker.save(saveOptions);
      if (!uris || uris.length === 0) {
        return;
      }
      const exported = await OcrSampleCollector.exportTo(getContext(this) as common.Context, uris[0]);
      Toast.success($r('app.string.train_export_success', exported));
      this.trainSampleCount = await OcrSampleCollector.sampleCount(getContext(this) as common.Context);
    } catch (err) {
      Logger.error('导出训练数据失败', (err as Error).message);
      Toast.error($r('app.string.export_failed'));
    }
  }

  // 自检端侧 OCR：选一张图实跑 recognizeBlocks，把识别出的文本行数与完整文本反馈出来
  async onTestOcr(): Promise<void> {
    const ctx = getContext(this);
    if (!canIUse('SystemCapability.AI.OCR.TextRecognition')) {
      this.ocrTestResult = ctx.resourceManager.getStringSync($r('app.string.ocr_unsupported'));
      this.ocrTestFullText = '';
      Toast.error($r('app.string.ocr_unsupported'));
      return;
    }
    this.ocrTesting = true;
    this.ocrTestResult = '';
    this.ocrTestFullText = '';
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await photoPicker.select(options);
      if (result.photoUris.length === 0) {
        this.ocrTestResult = ctx.resourceManager.getStringSync($r('app.string.pick_image_failed'));
        return;
      }
      const vision = await new LocalOcrRecognizer().recognizeBlocks(result.photoUris[0]);
      this.ocrTestResult = ctx.resourceManager.getStringSync($r('app.string.ocr_test_success'), vision.blocks.length);
      const lines: string[] = [];
      for (const block of vision.blocks) {
        lines.push(`${block.text}  [${block.left.toFixed(3)},${block.top.toFixed(3)} ${block.right.toFixed(3)},${block.bottom.toFixed(3)}]`);
      }
      this.ocrTestFullText = lines.join('\n');
      Toast.success($r('app.string.ocr_test_success', vision.blocks.length));
    } catch (err) {
      const e = err as Error;
      Logger.error('OCR 自检失败', e.message);
      this.ocrTestResult = e.message ? e.message : ctx.resourceManager.getStringSync($r('app.string.ocr_failed'));
      this.ocrTestFullText = '';
      Toast.error(e.message ? e.message : $r('app.string.ocr_failed'));
    } finally {
      this.ocrTesting = false;
    }
  }

  // 刷新样本列表与计数
  async refreshSamples(): Promise<void> {
    this.trainSampleCount = await OcrSampleCollector.sampleCount(getContext(this) as common.Context);
    this.samples = await OcrSampleCollector.listSamples(getContext(this) as common.Context);
  }

  async onDeleteSample(index: number): Promise<void> {
    await OcrSampleCollector.deleteSample(getContext(this) as common.Context, index);
    await this.refreshSamples();
    Toast.success($r('app.string.train_delete_success'));
  }

  async onClearSamples(): Promise<void> {
    await OcrSampleCollector.clearAll(getContext(this) as common.Context);
    await this.refreshSamples();
    Toast.success($r('app.string.train_clear_success'));
  }

  confirmClearSamples(): void {
    AlertDialog.show({
      title: $r('app.string.train_clear_confirm_title'),
      message: $r('app.string.train_clear_confirm_msg'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.confirm'),
        fontColor: this.tk().danger,
        action: () => {
          this.onClearSamples();
        }
      }
    });
  }

  @Builder SectionTitle(label: ResourceStr) {
    Text(label)
      .width('100%')
      .fontSize(this.fs(14))
      .fontColor(this.tk().textPrimary)
      .margin({ bottom: SPACE_SMALL })
  }

  @Builder FormRow(label: ResourceStr, placeholder: ResourceStr, value: string, isPassword: boolean,
    onValueChange: (value: string) => void) {
    Row() {
      Text(label)
        .width(72)
        .fontSize(this.fs(14))
        .fontColor(this.tk().textPrimary)
      TextInput({ text: value, placeholder: placeholder })
        .type(isPassword ? InputType.Password : InputType.Normal)
        .fontSize(this.fs(14))
        .fontColor(this.tk().textPrimary)
        .layoutWeight(1)
        .backgroundColor(this.tk().surface)
        .onChange(onValueChange)
    }.width('100%').height(44)
  }

  build() {
    Column() {
      AccountNavigator({ title: $r('app.string.model_settings') })
      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          Column({ space: SPACE_MEDIUM }) {
            this.SectionTitle($r('app.string.recognizer_type_label'))
            Column({ space: SPACE_TINY }) {
              Row({ space: SPACE_MEDIUM }) {
                Text($r('app.string.recognizer_ocr'))
                  .fontSize(this.fs(15))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.tk().textPrimary)
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: $$this.ocrEnabled })
              }.width('100%')
              Text($r('app.string.ocr_hint'))
                .width('100%')
                .fontSize(this.fs(12))
                .lineHeight(this.fs(17))
                .fontColor(this.tk().textSecondary)
            }.width('100%')
            Divider().color(this.tk().surfaceVariant)
            Column({ space: SPACE_TINY }) {
              Row({ space: SPACE_MEDIUM }) {
                Text($r('app.string.recognizer_cloud'))
                  .fontSize(this.fs(15))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.tk().textPrimary)
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: $$this.cloudEnabled })
              }.width('100%')
              Text($r('app.string.cloud_hint'))
                .width('100%')
                .fontSize(this.fs(12))
                .lineHeight(this.fs(17))
                .fontColor(this.tk().textSecondary)
            }.width('100%')
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          Column({ space: SPACE_MEDIUM }) {
            this.SectionTitle($r('app.string.train_section_title'))
            Column({ space: SPACE_TINY }) {
              Row({ space: SPACE_MEDIUM }) {
                Text($r('app.string.train_collect_label'))
                  .fontSize(this.fs(15))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.tk().textPrimary)
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: this.trainCollectEnabled })
                  .onChange((value: boolean) => {
                    this.trainCollectEnabled = value;
                    void CloudLlmConfigStore.saveTrainCollectEnabled(value);
                  })
              }.width('100%')
              Text($r('app.string.train_collect_hint'))
                .width('100%')
                .fontSize(this.fs(12))
                .lineHeight(this.fs(17))
                .fontColor(this.tk().textSecondary)
            }.width('100%')
            Divider().color(this.tk().surfaceVariant)
            Row({ space: SPACE_MEDIUM }) {
              Text(this.ocrSupported ? $r('app.string.ocr_supported') : $r('app.string.ocr_unsupported'))
                .fontSize(this.fs(13))
                .fontColor(this.ocrSupported ? this.tk().primary : this.tk().danger)
                .layoutWeight(1)
              Text($r('app.string.train_collected_count', this.trainSampleCount))
                .fontSize(this.fs(13))
                .fontColor(this.tk().textSecondary)
            }.width('100%')
            Row({ space: SPACE_SMALL }) {
              Button(this.ocrTesting ? $r('app.string.ocr_testing') : $r('app.string.ocr_test_do'))
                .layoutWeight(1)
                .height(32)
                .fontSize(this.fs(13))
                .backgroundColor(this.tk().surface)
                .fontColor(this.tk().primary)
                .type(ButtonType.Normal)
                .borderRadius(SPACE_SMALL)
                .border({ width: 1, color: this.tk().primary })
                .enabled(!this.ocrTesting)
                .onClick(() => {
                  this.onTestOcr();
                })
              Button($r('app.string.train_export_do'))
                .layoutWeight(1)
                .height(32)
                .fontSize(this.fs(13))
                .backgroundColor(this.tk().surface)
                .fontColor(this.tk().primary)
                .type(ButtonType.Normal)
                .borderRadius(SPACE_SMALL)
                .border({ width: 1, color: this.tk().primary })
                .onClick(() => {
                  this.onExportSamples();
                })
            }.width('100%')
            if (this.ocrTestResult.length > 0) {
              Text(this.ocrTestResult)
                .width('100%')
                .fontSize(this.fs(13))
                .lineHeight(this.fs(18))
                .fontColor(this.tk().textPrimary)
                .margin({ top: SPACE_SMALL })
            }
            if (this.ocrTestFullText.length > 0) {
              Column({ space: 0 }) {
                Text($r('app.string.ocr_test_detail'))
                  .width('100%')
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().textSecondary)
                  .margin({ bottom: SPACE_TINY })
                Text(this.ocrTestFullText)
                  .width('100%')
                  .fontSize(this.fs(13))
                  .lineHeight(this.fs(20))
                  .fontColor(this.tk().textPrimary)
              }
              .width('100%')
              .margin({ top: SPACE_SMALL })
              .padding(SPACE_SMALL)
              .backgroundColor(this.tk().background)
              .borderRadius(SPACE_SMALL)
            }
            if (this.samples.length > 0) {
              Column({ space: SPACE_TINY }) {
                Text($r('app.string.train_list_title'))
                  .width('100%')
                  .fontSize(this.fs(12))
                  .fontColor(this.tk().textSecondary)
                ForEach(this.samples, (item: SampleSummary) => {
                  Row({ space: SPACE_SMALL }) {
                    Column({ space: 2 }) {
                      Text(dayjs(item.capturedAt).format('MM-DD HH:mm') + '  #' + item.index)
                        .fontSize(this.fs(12))
                        .fontColor(this.tk().textPrimary)
                      Text(`${item.txnPreview} · ${item.lineCount} 行 · ${item.txnCount} 笔`)
                        .fontSize(this.fs(11))
                        .fontColor(this.tk().textSecondary)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    Text($r('app.string.delete'))
                      .fontSize(this.fs(12))
                      .fontColor(this.tk().danger)
                      .onClick(() => {
                        this.onDeleteSample(item.index);
                      })
                  }
                  .width('100%')
                  .padding({ top: 6, bottom: 6 })
                }, (item: SampleSummary) => item.capturedAt + '_' + item.index)
                Button($r('app.string.train_clear_all'))
                  .width('100%')
                  .height(32)
                  .fontSize(this.fs(13))
                  .fontColor(this.tk().danger)
                  .backgroundColor(this.tk().surface)
                  .type(ButtonType.Normal)
                  .borderRadius(SPACE_SMALL)
                  .border({ width: 1, color: this.tk().danger })
                  .margin({ top: SPACE_TINY })
                  .onClick(() => {
                    this.confirmClearSamples();
                  })
              }
              .width('100%')
              .margin({ top: SPACE_SMALL })
              .padding(SPACE_SMALL)
              .backgroundColor(this.tk().background)
              .borderRadius(SPACE_SMALL)
            }
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

          if (this.cloudEnabled) {
            Column({ space: SPACE_MEDIUM }) {
              this.SectionTitle($r('app.string.edit_config_title'))
              Column({ space: SPACE_TINY }) {
                Text($r('app.string.provider_label'))
                  .fontSize(this.fs(14))
                  .fontColor(this.tk().textPrimary)
                Select(this.providerSelectOptions())
                  .selected(this.providerIndex)
                  .value(LLM_PROVIDERS[this.providerIndex].name)
                  .font({ size: this.fs(14) })
                  .fontColor(this.tk().textPrimary)
                  .width('100%')
                  .height(44)
                  .onSelect((index: number) => {
                    this.selectProviderById(LLM_PROVIDERS[index].id);
                  })
              }.width('100%')
              if (LLM_PROVIDERS[this.providerIndex].custom) {
                Divider().color(this.tk().surfaceVariant)
                this.FormRow($r('app.string.base_url_label'), $r('app.string.base_url_placeholder'), this.customBaseUrl, false,
                  (value: string) => {
                    this.customBaseUrl = value;
                  })
              }
              Divider().color(this.tk().surfaceVariant)
              if (LLM_PROVIDERS[this.providerIndex].models.length > 0) {
                Column({ space: SPACE_TINY }) {
                  Text($r('app.string.model_label'))
                    .fontSize(this.fs(14))
                    .fontColor(this.tk().textPrimary)
                  Select(this.modelSelectOptions())
                    .selected(this.modelIndex)
                    .value(LLM_PROVIDERS[this.providerIndex].models[this.modelIndex].label)
                    .font({ size: this.fs(14) })
                    .fontColor(this.tk().textPrimary)
                    .width('100%')
                    .height(44)
                    .onSelect((index: number) => {
                      this.modelIndex = index;
                      this.model = LLM_PROVIDERS[this.providerIndex].models[index].id;
                    })
                }.width('100%')
              } else {
                this.FormRow($r('app.string.model_label'), $r('app.string.model_placeholder'), this.model, false,
                  (value: string) => {
                    this.model = value;
                  })
              }
              Divider().color(this.tk().surfaceVariant)
              this.FormRow($r('app.string.api_key_label'), $r('app.string.api_key_placeholder'), this.apiKey, true,
                (value: string) => {
                  this.apiKey = value;
                })
              Text($r('app.string.cloud_hint'))
                .width('100%')
                .fontSize(this.fs(12))
                .lineHeight(this.fs(17))
                .fontColor(this.tk().textSecondary)
              Button($r('app.string.provider_save'))
                .width('100%')
                .height(40)
                .fontSize(this.fs(14))
                .fontColor(this.tk().surface)
                .backgroundColor(this.tk().primary)
                .type(ButtonType.Normal)
                .borderRadius(SPACE_SMALL)
                .onClick(() => {
                  this.saveCurrentProvider();
                })
            }
            .width('100%')
            .padding(SPACE_LARGE)
            .backgroundColor(this.tk().surface)
            .borderRadius(RADIUS_CARD)
            .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

            Column({ space: SPACE_SMALL }) {
              this.SectionTitle($r('app.string.provider_list_title'))
              if (this.savedProviders.length > 0) {
                ForEach(this.savedProviders, (item: SavedProviderConfig) => {
                  Row({ space: SPACE_SMALL }) {
                    Column({ space: 2 }) {
                      Row({ space: SPACE_SMALL }) {
                        Text(findProvider(item.id).name)
                          .fontSize(this.fs(14))
                          .fontWeight(FontWeight.Medium)
                          .fontColor(this.tk().textPrimary)
                        if (this.activeProviderId === item.id) {
                          Text($r('app.string.provider_active_tag'))
                            .fontSize(this.fs(11))
                            .fontColor(this.tk().primary)
                        }
                      }
                      Text(`${findModelLabel(item.id, item.model)} · ${this.maskApiKey(item.apiKey)}`)
                        .fontSize(this.fs(12))
                        .fontColor(this.tk().textSecondary)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    if (this.activeProviderId !== item.id) {
                      Text($r('app.string.provider_use'))
                        .fontSize(this.fs(13))
                        .fontColor(this.tk().primary)
                        .onClick(() => {
                          this.useProvider(item.id);
                        })
                    }
                    Text($r('app.string.delete'))
                      .fontSize(this.fs(13))
                      .fontColor(this.tk().danger)
                      .margin({ left: SPACE_SMALL })
                      .onClick(() => {
                        this.deleteProvider(item.id);
                      })
                  }
                  .width('100%')
                  .padding({ top: 8, bottom: 8 })
                }, (item: SavedProviderConfig) => item.id)
                Button($r('app.string.provider_clear_all'))
                  .width('100%')
                  .height(32)
                  .fontSize(this.fs(13))
                  .fontColor(this.tk().danger)
                  .backgroundColor(this.tk().surface)
                  .type(ButtonType.Normal)
                  .borderRadius(SPACE_SMALL)
                  .border({ width: 1, color: this.tk().danger })
                  .margin({ top: SPACE_TINY })
                  .onClick(() => {
                    this.confirmClearProviders();
                  })
              } else {
                Text($r('app.string.provider_none'))
                  .width('100%')
                  .fontSize(this.fs(13))
                  .fontColor(this.tk().textSecondary)
              }
            }
            .width('100%')
            .padding(SPACE_LARGE)
            .backgroundColor(this.tk().surface)
            .borderRadius(RADIUS_CARD)
            .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

            Column({ space: SPACE_MEDIUM }) {
              if (this.testing) {
                Row({ space: SPACE_MEDIUM }) {
                  LoadingProgress()
                    .width(24)
                    .height(24)
                    .color(this.tk().primary)
                  Text($r('app.string.testing_connection'))
                    .fontSize(this.fs(14))
                    .fontColor(this.tk().textSecondary)
                }.width('100%').height(44).justifyContent(FlexAlign.Center)
              } else {
                Button($r('app.string.test_connection'))
                  .width('100%')
                  .height(44)
                  .fontSize(this.fs(16))
                  .backgroundColor(this.tk().surface)
                  .fontColor(this.tk().primary)
                  .type(ButtonType.Normal)
                  .borderRadius(SPACE_SMALL)
                  .border({ width: 1, color: this.tk().primary })
                  .onClick(() => {
                    this.onTestConnection();
                  })
              }
              if (this.testResult.length > 0) {
                Text(this.testResult)
                  .width('100%')
                  .fontSize(this.fs(13))
                  .lineHeight(this.fs(18))
                  .fontColor(this.testSuccess ? this.tk().primary : this.tk().danger)
              }
            }
            .width('100%')
            .padding(SPACE_LARGE)
            .backgroundColor(this.tk().surface)
            .borderRadius(RADIUS_CARD)
            .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
          }

          Button($r('app.string.save'))
            .width('100%')
            .height(44)
            .fontSize(this.fs(16))
            .backgroundColor(this.tk().primary)
            .fontColor(this.tk().surface)
            .type(ButtonType.Normal)
            .borderRadius(SPACE_SMALL)
            .onClick(() => {
              this.onSave();
            })
        }
        .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
        .padding({ left: SPACE_XLARGE, right: SPACE_XLARGE, top: SPACE_MEDIUM })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tk().background)
  }
}
