import AccountNavigator from '../components/Navigator';
import { CloudLlmConfig } from '../models/recognition/CloudLlmModels';
import CloudLlmConfigStore from '../service/recognition/CloudLlmConfigStore';
import { CloudLlmRecognizer } from '../service/recognition/CloudLlmRecognizer';
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

  @State baseUrl: string = '';
  @State apiKey: string = '';
  @State model: string = '';
  @State ocrEnabled: boolean = true;
  @State cloudEnabled: boolean = false;
  @State hasSavedConfig: boolean = false;
  @State savedBaseUrl: string = '';
  @State savedModel: string = '';
  @State savedApiKey: string = '';
  @State testing: boolean = false;
  @State testResult: string = '';
  @State testSuccess: boolean = false;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  async aboutToAppear(): Promise<void> {
    try {
      const config = await CloudLlmConfigStore.loadConfig();
      this.baseUrl = config.baseUrl;
      this.apiKey = config.apiKey;
      this.model = config.model;
      this.ocrEnabled = await CloudLlmConfigStore.loadOcrEnabled();
      this.cloudEnabled = await CloudLlmConfigStore.loadCloudEnabled();
      this.updateSavedSummary(config);
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

  updateSavedSummary(config: CloudLlmConfig): void {
    this.hasSavedConfig = config.baseUrl.length > 0 || config.apiKey.length > 0 || config.model.length > 0;
    this.savedBaseUrl = config.baseUrl;
    this.savedModel = config.model;
    this.savedApiKey = this.maskApiKey(config.apiKey);
  }

  async onSave(): Promise<void> {
    try {
      if (this.cloudEnabled) {
        const config: CloudLlmConfig = {
          baseUrl: this.baseUrl.trim(),
          apiKey: this.apiKey.trim(),
          model: this.model.trim()
        };
        await CloudLlmConfigStore.saveConfig(config);
        this.updateSavedSummary(config);
      }
      await CloudLlmConfigStore.saveOcrEnabled(this.ocrEnabled);
      await CloudLlmConfigStore.saveCloudEnabled(this.cloudEnabled);
      Toast.success($r('app.string.settings_saved'));
    } catch (error) {
      Logger.error('保存设置失败', (error as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  confirmClear(): void {
    AlertDialog.show({
      title: $r('app.string.delete_confirm_title'),
      message: $r('app.string.clear_confirm_msg'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.clear_config'),
        fontColor: this.tk().danger,
        action: () => {
          this.clearConfig();
        }
      }
    });
  }

  async clearConfig(): Promise<void> {
    const empty: CloudLlmConfig = { baseUrl: '', apiKey: '', model: '' };
    try {
      await CloudLlmConfigStore.saveConfig(empty);
      this.baseUrl = '';
      this.apiKey = '';
      this.model = '';
      this.updateSavedSummary(empty);
      Toast.success($r('app.string.clear_success'));
    } catch (error) {
      Logger.error('清空设置失败', (error as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  async onTestConnection(): Promise<void> {
    const config: CloudLlmConfig = {
      baseUrl: this.baseUrl.trim(),
      apiKey: this.apiKey.trim(),
      model: this.model.trim()
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

  @Builder InfoRow(label: ResourceStr, value: string) {
    Row() {
      Text(label)
        .width(72)
        .fontSize(this.fs(14))
        .fontColor(this.tk().textSecondary)
      Text(value)
        .fontSize(this.fs(14))
        .fontColor(this.tk().textPrimary)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%').height(32)
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

          if (this.cloudEnabled) {
            Column() {
              this.SectionTitle($r('app.string.edit_config_title'))
              this.FormRow($r('app.string.base_url_label'), $r('app.string.base_url_placeholder'), this.baseUrl, false,
                (value: string) => {
                  this.baseUrl = value;
                })
              Divider().color(this.tk().surfaceVariant)
              this.FormRow($r('app.string.api_key_label'), $r('app.string.api_key_placeholder'), this.apiKey, true,
                (value: string) => {
                  this.apiKey = value;
                })
              Divider().color(this.tk().surfaceVariant)
              this.FormRow($r('app.string.model_label'), $r('app.string.model_placeholder'), this.model, false,
                (value: string) => {
                  this.model = value;
                })
            }
            .width('100%')
            .padding(SPACE_LARGE)
            .backgroundColor(this.tk().surface)
            .borderRadius(RADIUS_CARD)
            .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })

            Column({ space: SPACE_SMALL }) {
              this.SectionTitle($r('app.string.saved_config_title'))
              if (this.hasSavedConfig) {
                this.InfoRow($r('app.string.base_url_label'), this.savedBaseUrl)
                this.InfoRow($r('app.string.model_label'), this.savedModel)
                this.InfoRow($r('app.string.api_key_label'), this.savedApiKey)
                Button($r('app.string.clear_config'))
                  .width('100%')
                  .height(36)
                  .fontSize(this.fs(14))
                  .fontColor(this.tk().danger)
                  .backgroundColor(this.tk().surface)
                  .type(ButtonType.Normal)
                  .borderRadius(SPACE_SMALL)
                  .border({ width: 1, color: this.tk().danger })
                  .margin({ top: SPACE_SMALL })
                  .onClick(() => {
                    this.confirmClear();
                  })
              } else {
                Text($r('app.string.no_saved_config'))
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
