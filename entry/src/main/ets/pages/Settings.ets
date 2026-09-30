import router from '@ohos.router';
import AccountNavigator from '../components/Navigator';
import { RecognizerType } from '../common/Config';
import { CloudLlmConfig } from '../models/recognition/CloudLlmModels';
import CloudLlmConfigStore from '../service/recognition/CloudLlmConfigStore';
import { CloudLlmRecognizer } from '../service/recognition/CloudLlmRecognizer';
import { Toast } from '../components/ToastDialog';
import { Logger } from '../utils/Logger';
import BreakpointConstants from '../common/breakpoint';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_XLARGE } from '../common/dimens';

// 测试结果中模型回复的展示上限，避免刷屏
const REPLY_DISPLAY_MAX: number = 50;

@Entry
@Component
struct Settings {
  @State baseUrl: string = '';
  @State apiKey: string = '';
  @State model: string = '';
  @State recognizerType: RecognizerType = RecognizerType.MOCK;
  // 已保存配置的只读摘要，apiKey 打码展示
  @State hasSavedConfig: boolean = false;
  @State savedBaseUrl: string = '';
  @State savedModel: string = '';
  @State savedApiKey: string = '';
  // 连通性测试状态与结果
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
      this.recognizerType = await CloudLlmConfigStore.loadRecognizerType();
      this.updateSavedSummary(config);
    } catch (error) {
      Logger.error('加载设置失败', (error as Error).message);
    }
  }

  // apiKey 只露首尾，避免完整 Key 常驻屏幕
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

  // 保存到本机 Preferences，停留在本页并刷新“已保存配置”摘要
  async onSave(): Promise<void> {
    const config: CloudLlmConfig = {
      baseUrl: this.baseUrl.trim(),
      apiKey: this.apiKey.trim(),
      model: this.model.trim()
    };
    try {
      await CloudLlmConfigStore.saveConfig(config);
      await CloudLlmConfigStore.saveRecognizerType(this.recognizerType);
      this.updateSavedSummary(config);
      Toast.success($r('app.string.settings_saved'));
    } catch (error) {
      Logger.error('保存设置失败', (error as Error).message);
      Toast.error($r('app.string.save_failed'));
    }
  }

  // 清空前二次确认，避免误删
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
        fontColor: $r('app.color.red'),
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

  // 用表单当前值测试连通性，无需先保存
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

  @Builder FormRow(label: ResourceStr, placeholder: ResourceStr, value: string, isPassword: boolean,
    onValueChange: (value: string) => void) {
    Row() {
      Text(label)
        .width(64)
        .fontSize(14)
        .fontColor($r('app.color.font_3'))
      TextInput({ text: value, placeholder: placeholder })
        .type(isPassword ? InputType.Password : InputType.Normal)
        .fontSize(14)
        .fontColor($r('app.color.font_3'))
        .layoutWeight(1)
        .backgroundColor($r('app.color.white'))
        .onChange(onValueChange)
    }.width('100%').height(44)
  }

  @Builder InfoRow(label: ResourceStr, value: string) {
    Row() {
      Text(label)
        .width(64)
        .fontSize(14)
        .fontColor($r('app.color.font_2'))
      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.font_3'))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('100%').height(32)
  }

  build() {
    Column() {
      AccountNavigator()
      Scroll() {
        Column({ space: SPACE_MEDIUM }) {
          Text($r('app.string.settings_title'))
            .width('100%')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.font_1'))

          // 识别引擎切换：mock / cloud
          Column({ space: SPACE_MEDIUM }) {
            Text($r('app.string.recognizer_type_label'))
              .width('100%')
              .fontSize(14)
              .fontColor($r('app.color.font_3'))
            Row({ space: SPACE_MEDIUM }) {
              Button($r('app.string.recognizer_mock'))
                .layoutWeight(1)
                .height(40)
                .fontSize(15)
                .fontColor(this.recognizerType === RecognizerType.MOCK ? $r('app.color.white') : $r('app.color.font_2'))
                .backgroundColor(this.recognizerType === RecognizerType.MOCK ? $r('app.color.green') : $r('app.color.grey_1'))
                .type(ButtonType.Normal)
                .borderRadius(SPACE_SMALL)
                .onClick(() => {
                  this.recognizerType = RecognizerType.MOCK;
                })
              Button($r('app.string.recognizer_cloud'))
                .layoutWeight(1)
                .height(40)
                .fontSize(15)
                .fontColor(this.recognizerType === RecognizerType.CLOUD ? $r('app.color.white') : $r('app.color.font_2'))
                .backgroundColor(this.recognizerType === RecognizerType.CLOUD ? $r('app.color.green') : $r('app.color.grey_1'))
                .type(ButtonType.Normal)
                .borderRadius(SPACE_SMALL)
                .onClick(() => {
                  this.recognizerType = RecognizerType.CLOUD;
                })
            }.width('100%')
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor($r('app.color.white'))
          .borderRadius(RADIUS_CARD)

          // 已保存配置摘要，可清空
          Column({ space: SPACE_SMALL }) {
            Text($r('app.string.saved_config_title'))
              .width('100%')
              .fontSize(14)
              .fontColor($r('app.color.font_3'))
            if (this.hasSavedConfig) {
              this.InfoRow($r('app.string.base_url_label'), this.savedBaseUrl)
              this.InfoRow($r('app.string.model_label'), this.savedModel)
              this.InfoRow($r('app.string.api_key_label'), this.savedApiKey)
              Button($r('app.string.clear_config'))
                .width('100%')
                .height(36)
                .fontSize(14)
                .fontColor($r('app.color.red'))
                .backgroundColor($r('app.color.white'))
                .type(ButtonType.Normal)
                .borderRadius(SPACE_SMALL)
                .border({ width: 1, color: $r('app.color.red') })
                .margin({ top: SPACE_SMALL })
                .onClick(() => {
                  this.confirmClear();
                })
            } else {
              Text($r('app.string.no_saved_config'))
                .width('100%')
                .fontSize(13)
                .fontColor($r('app.color.font_2'))
            }
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor($r('app.color.white'))
          .borderRadius(RADIUS_CARD)

          // 修改配置表单
          Column() {
            Text($r('app.string.edit_config_title'))
              .width('100%')
              .fontSize(14)
              .fontColor($r('app.color.font_3'))
              .margin({ bottom: SPACE_SMALL })
            this.FormRow($r('app.string.base_url_label'), $r('app.string.base_url_placeholder'), this.baseUrl, false,
              (value: string) => {
                this.baseUrl = value;
              })
            Divider().color($r('app.color.grey_1'))
            this.FormRow($r('app.string.api_key_label'), $r('app.string.api_key_placeholder'), this.apiKey, true,
              (value: string) => {
                this.apiKey = value;
              })
            Divider().color($r('app.color.grey_1'))
            this.FormRow($r('app.string.model_label'), $r('app.string.model_placeholder'), this.model, false,
              (value: string) => {
                this.model = value;
              })
            Text($r('app.string.cloud_hint'))
              .width('100%')
              .fontSize(12)
              .lineHeight(17)
              .fontColor($r('app.color.font_2'))
              .margin({ top: SPACE_SMALL })
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor($r('app.color.white'))
          .borderRadius(RADIUS_CARD)

          Button($r('app.string.save'))
            .width('100%')
            .height(44)
            .fontSize(16)
            .backgroundColor($r('app.color.green'))
            .fontColor($r('app.color.white'))
            .type(ButtonType.Normal)
            .borderRadius(SPACE_SMALL)
            .onClick(() => {
              this.onSave();
            })

          // 连通性测试：使用表单当前值，无需先保存
          Column({ space: SPACE_MEDIUM }) {
            if (this.testing) {
              Row({ space: SPACE_MEDIUM }) {
                LoadingProgress()
                  .width(24)
                  .height(24)
                  .color($r('app.color.green'))
                Text($r('app.string.testing_connection'))
                  .fontSize(14)
                  .fontColor($r('app.color.font_2'))
              }.width('100%').height(44).justifyContent(FlexAlign.Center)
            } else {
              Button($r('app.string.test_connection'))
                .width('100%')
                .height(44)
                .fontSize(16)
                .backgroundColor($r('app.color.white'))
                .fontColor($r('app.color.green'))
                .type(ButtonType.Normal)
                .borderRadius(SPACE_SMALL)
                .border({ width: 1, color: $r('app.color.green') })
                .onClick(() => {
                  this.onTestConnection();
                })
            }
            if (this.testResult.length > 0) {
              Text(this.testResult)
                .width('100%')
                .fontSize(13)
                .lineHeight(18)
                .fontColor(this.testSuccess ? $r('app.color.green') : $r('app.color.red'))
            }
          }
          .width('100%')
          .padding(SPACE_LARGE)
          .backgroundColor($r('app.color.white'))
          .borderRadius(RADIUS_CARD)
          .margin({ bottom: SPACE_MEDIUM })
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
    .backgroundColor($r('app.color.bg'))
  }
}
