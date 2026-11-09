import AccountNavigator from '../components/Navigator';
import { CloudLlmConfig, SavedProviderConfig } from '../models/recognition/CloudLlmModels';
import { LLM_PROVIDERS, LlmProvider, findProvider, findModelLabel } from '../models/recognition/LlmProviders';
import CloudLlmConfigStore from '../service/recognition/CloudLlmConfigStore';
import { CloudLlmRecognizer } from '../service/recognition/CloudLlmRecognizer';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import BreakpointConstants from '../common/breakpoint';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_TINY, SPACE_XLARGE } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

const REPLY_DISPLAY_MAX: number = 50;

// 各服务商 API Key 获取指引：步骤 + 控制台入口（点击 API Key 标签旁「?」弹出）
interface ProviderKeyGuide {
  steps: string;
  consoleUrl: string;
}

const PROVIDER_KEY_GUIDES: Record<string, ProviderKeyGuide> = {
  'doubao': {
    steps: '1. 注册并登录火山引擎，开通「火山方舟」大模型服务\n2. 进入控制台「API Key 管理」创建 API Key',
    consoleUrl: 'https://console.volcengine.com/ark'
  },
  'qwen': {
    steps: '1. 注册并登录阿里云，开通「百炼」大模型服务\n2. 在百炼控制台「API-KEY」页面创建密钥',
    consoleUrl: 'https://bailian.console.aliyun.com'
  },
  'glm': {
    steps: '1. 注册并登录智谱开放平台\n2. 在「API Keys」页面创建密钥',
    consoleUrl: 'https://open.bigmodel.cn'
  },
  'deepseek': {
    steps: '1. 注册并登录 DeepSeek 开放平台\n2. 在「API keys」页面创建密钥',
    consoleUrl: 'https://platform.deepseek.com'
  },
  'kimi': {
    steps: '1. 注册并登录月之暗面开放平台\n2. 在「API Key 管理」创建密钥',
    consoleUrl: 'https://platform.moonshot.cn'
  },
  'custom': {
    steps: '自定义服务商请前往对应平台，创建 OpenAI 兼容接口的 API Key 后填入',
    consoleUrl: ''
  }
};

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

  // 当前编辑中的模型是否不支持图片输入：固定服务商查目录 vision 标记，
  // 自定义服务商模型名无法判断，不作提示
  selectedModelNoVision(): boolean {
    const provider = LLM_PROVIDERS[this.providerIndex];
    if (provider.custom) {
      return false;
    }
    for (const m of provider.models) {
      if (m.id === this.model) {
        return !m.vision;
      }
    }
    return false;
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

  // 端侧识别开关：切换即持久化，退出重进不丢
  async onToggleOcr(value: boolean): Promise<void> {
    this.ocrEnabled = value;
    try {
      await CloudLlmConfigStore.saveOcrEnabled(value);
    } catch (error) {
      Logger.error('保存端侧识别开关失败', (error as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  // 云端大模型开关：切换即持久化，退出重进不丢
  async onToggleCloud(value: boolean): Promise<void> {
    this.cloudEnabled = value;
    try {
      await CloudLlmConfigStore.saveCloudEnabled(value);
    } catch (error) {
      Logger.error('保存云端识别开关失败', (error as Error).message);
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

  @Builder SectionTitle(label: ResourceStr) {
    Text(label)
      .width('100%')
      .fontSize(this.fs(14))
      .fontColor(this.tk().textPrimary)
      .margin({ bottom: SPACE_SMALL })
  }

  // 弹出当前服务商的 API Key 获取指引
  showApiKeyGuide(): void {
    const provider = LLM_PROVIDERS[this.providerIndex];
    const guide = PROVIDER_KEY_GUIDES[provider.id];
    const message = guide === undefined ? '' :
      (guide.consoleUrl.length > 0 ? guide.steps + '\n\n控制台：' + guide.consoleUrl : guide.steps);
    AlertDialog.show({
      title: $r('app.string.api_key_guide_title'),
      message: message,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.guide_got_it'),
        fontColor: this.tk().primary,
        action: (): void => {
        }
      }
    });
  }

  // API Key 输入行：标签旁带「?」帮助入口，点击弹出获取指引
  @Builder ApiKeyRow() {
    Row() {
      Text($r('app.string.api_key_label'))
        .fontSize(this.fs(14))
        .fontColor(this.tk().textPrimary)
      Text('?')
        .width(16)
        .height(16)
        .fontSize(this.fs(10))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tk().textSecondary)
        .borderRadius(8)
        .border({ width: 1, color: this.tk().textSecondary })
        .textAlign(TextAlign.Center)
        .margin({ left: SPACE_SMALL })
        .onClick(() => {
          this.showApiKeyGuide();
        })
      TextInput({ text: this.apiKey, placeholder: $r('app.string.api_key_placeholder') })
        .type(InputType.Password)
        .fontSize(this.fs(14))
        .fontColor(this.tk().textPrimary)
        .layoutWeight(1)
        .backgroundColor(this.tk().surface)
        .onChange((value: string) => {
          this.apiKey = value;
        })
    }.width('100%').height(44)
  }

  @Builder FormRow(label: ResourceStr, placeholder: ResourceStr, value: string, isPassword: boolean,
    onValueChange: (value: string) => void) {
    Row() {
      Text(label)
        .width(this.fs(72))
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
                Toggle({ type: ToggleType.Switch, isOn: this.ocrEnabled })
                  .onChange((value: boolean) => {
                    this.onToggleOcr(value);
                  })
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
                Toggle({ type: ToggleType.Switch, isOn: this.cloudEnabled })
                  .onChange((value: boolean) => {
                    this.onToggleCloud(value);
                  })
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
                  // 纯文本模型选中的即时警示：账单识别必须多模态，提前拦住而不是等识别失败才提示
                  if (this.selectedModelNoVision()) {
                    Text($r('app.string.model_no_vision_hint'))
                      .width('100%')
                      .fontSize(this.fs(12))
                      .lineHeight(this.fs(17))
                      .fontColor(this.tk().warning)
                  }
                }.width('100%')
              } else {
                this.FormRow($r('app.string.model_label'), $r('app.string.model_placeholder'), this.model, false,
                  (value: string) => {
                    this.model = value;
                  })
              }
              Divider().color(this.tk().surfaceVariant)
              this.ApiKeyRow()
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
                }, (item: SavedProviderConfig) => `${item.id}_${item.model}_${item.apiKey.length}`)
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
                  .backgroundColor(this.tk().primary)
                  .fontColor(this.tk().surface)
                  .type(ButtonType.Normal)
                  .borderRadius(SPACE_SMALL)
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
