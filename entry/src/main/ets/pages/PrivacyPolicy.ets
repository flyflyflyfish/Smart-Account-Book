import AccountNavigator from '../components/Navigator';
import BreakpointConstants from '../common/breakpoint';
import { RADIUS_CARD, SPACE_LARGE, SPACE_MEDIUM, SPACE_SMALL, SPACE_XLARGE } from '../common/dimens';
import { ThemeKit, ThemePalette } from '../common/theme/Theme';

/**
 * 隐私政策页（应用内本地全文）：说明数据收集、存储、权限用途、第三方服务与开发者联系方式。
 * 政策正文以中文版本为准；供应用市场提审与用户随时查阅。
 */
@Entry
@Component
struct PrivacyPolicy {

  @StorageProp('themeSeq') themeSeq: number = 0;
  @StorageProp('currentBreakpoint') currentBreakpoint: string = BreakpointConstants.BREAKPOINT_SM;

  tk(): ThemePalette {
    return ThemeKit.palette(this.themeSeq);
  }

  fs(base: number): number {
    return ThemeKit.fontScaled(base, this.themeSeq);
  }

  @Builder
  PolicyHeading(text: string) {
    Text(text)
      .fontSize(this.fs(14))
      .fontWeight(FontWeight.Bold)
      .fontColor(this.tk().textPrimary)
      .padding({ top: SPACE_MEDIUM })
  }

  @Builder
  PolicyText(text: string) {
    Text(text)
      .fontSize(this.fs(12))
      .fontColor(this.tk().textSecondary)
      .lineHeight(this.fs(20))
      .textAlign(TextAlign.JUSTIFY)
  }

  build() {
    Column() {
      AccountNavigator({ title: $r('app.string.privacy_policy') })
      Scroll() {
        Column() {
          Column({ space: SPACE_SMALL }) {
            Text($r('app.string.privacy_policy'))
              .fontSize(this.fs(18))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.tk().textPrimary)
            this.PolicyText('更新日期：2026年11月6日')
            this.PolicyHeading('一、引言')
            this.PolicyText('智能记账助手（以下简称“本应用”）是一款个人记账工具。我们非常重视你的个人信息与隐私。'
              + '本政策说明本应用收集哪些信息、如何存储与使用这些信息，以及你所拥有的控制权。'
              + '请你仔细阅读并充分理解本政策后使用本应用。')
            this.PolicyHeading('二、我们收集的信息')
            this.PolicyText('1. 账单信息：你手动录入或通过识别功能生成的账单内容，包括金额、时间、商家、分类与备注。'
              + '账单数据默认保存在本机数据库中。\n'
              + '2. 账号标识：当你选择登录华为账号以启用云同步时，我们会取得你的华为账号匿名标识（uid），'
              + '仅用于标识云端数据的归属，不用于其他用途。\n'
              + '3. 学习记忆：为提升识别准确率，本应用会在本机记录“商家—分类”的学习记忆，'
              + '你可在“设置 → 隐私与安全”中随时清除。\n'
              + '4. 我们不收集你的通讯录、短信、位置信息，也不收集与记账无关的任何个人敏感信息。')
            this.PolicyHeading('三、信息的存储')
            this.PolicyText('1. 本地优先：所有账单数据首先保存在本机数据库，未登录账号时数据不离开你的设备。\n'
              + '2. 云端同步：登录华为账号后，你的账单、账本与设置将经加密通道同步到华为云数据库（AppGallery Connect），'
              + '用于在你登录同一账号的设备间保持数据一致。云端数据归属于你的华为账号。\n'
              + '3. 识别服务密钥：你在模型设置中填写的第三方大模型服务 API Key 仅保存在本机，'
              + '不上传云端，也不经我们转手。')
            this.PolicyHeading('四、权限用途')
            this.PolicyText('本应用遵循最小权限原则，仅在对应功能使用时申请权限：\n'
              + '1. 相机：用于拍摄账单票据以识别账单；\n'
              + '2. 麦克风：用于语音记账；\n'
              + '3. 通知：用于预算提醒与重复账单提醒；\n'
              + '4. 照片访问：用于从相册选择票据图片进行识别。\n'
              + '拒绝授权不影响其他功能的正常使用。')
            this.PolicyHeading('五、第三方服务')
            this.PolicyText('1. 华为账号服务（Account Kit）：提供账号登录与身份标识；\n'
              + '2. 华为云数据库（AppGallery Connect）：登录后提供端云数据同步；\n'
              + '3. 大模型识别服务：当你启用云端识别时，账单图片或文本将由你的设备直接发送至你自行配置的服务商'
              + '（如字节跳动豆包、阿里通义千问、智谱 GLM、DeepSeek、月之暗面 Kimi 等）进行识别，'
              + '该过程不经过我们的服务器，数据流转由你与服务商之间的协议约束。')
            this.PolicyHeading('六、信息的删除与控制')
            this.PolicyText('1. 你可在“设置 → 隐私与安全 → 数据管理”中清空全部账单数据，'
              + '该操作会同时删除本机与云端的全部账单及账本记录，不可恢复；\n'
              + '2. 你可清除学习到的商家分类记忆；\n'
              + '3. 你可随时撤回云端识别授权、退出华为账号登录并停止云同步。')
            this.PolicyHeading('七、未成年人保护')
            this.PolicyText('本应用不面向未满十四周岁的儿童。监护人应为未成年人妥善保管设备与账号，'
              + '如发现未成年人在未经同意的情况下使用本应用，可联系我们删除相关数据。')
            this.PolicyHeading('八、政策更新')
            this.PolicyText('我们可能适时修订本政策。重大变更会通过应用内提示等方式通知你。'
              + '更新后你继续使用本应用，即视为接受修订后的政策。')
            this.PolicyHeading('九、联系我们')
            this.PolicyText('开发者：hid12163462\n联系邮箱：3855757949@qq.com\n'
              + '如你对本政策或个人信息处理有疑问、意见或建议，可通过上述邮箱与我们联系，我们会在合理期限内回复。')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(SPACE_LARGE)
          .backgroundColor(this.tk().surface)
          .borderRadius(RADIUS_CARD)
          .shadow({ radius: 16, color: this.tk().primaryShadow, offsetX: 0, offsetY: 6 })
        }
        .width(BreakpointConstants.max_content_size.getValue(this.currentBreakpoint))
        .padding({ left: SPACE_XLARGE, right: SPACE_XLARGE, top: SPACE_MEDIUM, bottom: SPACE_LARGE })
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
