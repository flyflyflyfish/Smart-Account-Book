import auth from '@hw-agconnect/auth';
import { HwIdCredentialInfo, SignInParam } from '@hw-agconnect/auth';
import util from '@ohos.util';
import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import { BusinessError } from '@kit.BasicServicesKit';
import { resetAgcCredential } from './AgcCredentialReset';

const AUTH_DOMAIN: number = 0xFF01;
const AUTH_TAG: string = 'AuthService';

/**
 * 认证服务封装：负责华为账号登录与用户身份获取，owner_uid 取自 getUid
 */
class AuthService {
  private inited: boolean = false;
  private context: common.UIAbilityContext | undefined = undefined;
  private lastSignInCode: number = 0;
  private credentialResetTried: boolean = false;

  // 启动时读取 agconnect-services.json 初始化认证 SDK
  init(context: common.UIAbilityContext): void {
    this.context = context;
    try {
      const fileContent: Uint8Array = context.resourceManager.getRawFileContentSync('agconnect-services.json');
      const decoder = util.TextDecoder.create('utf-8');
      const json: string = decoder.decodeToString(fileContent);
      auth.init(context, json);
      this.inited = true;
      hilog.info(AUTH_DOMAIN, AUTH_TAG, 'auth init success, length: %{public}d', json.length);
    } catch (err) {
      const e = err as Error;
      hilog.error(AUTH_DOMAIN, AUTH_TAG, 'auth init failed: %{public}s', e.message);
    }
  }

  isReady(): boolean {
    return this.inited;
  }

  // 华为账号登录：首次会拉起华为账号授权，成功后返回 AGC 用户 uid
  async signInWithHuaweiId(): Promise<string | null> {
    let uid = await this.doSignIn();
    // 401 且极快返回 = 本地加密凭证损坏（HUKS 解密失败），重置 AGC 本地凭证后原地重试一次
    if (!uid && this.lastSignInCode === 401 && !this.credentialResetTried && this.context) {
      this.credentialResetTried = true;
      hilog.warn(AUTH_DOMAIN, AUTH_TAG, 'signIn rejected locally (401), resetting AGC local credential');
      const resetOk = await resetAgcCredential(this.context);
      hilog.info(AUTH_DOMAIN, AUTH_TAG, 'reset AGC local credential done: %{public}s', String(resetOk));
      uid = await this.doSignIn();
    }
    return uid;
  }

  // 本次进程内是否已执行过凭证重置（供 UI 判断是否提示重启应用）
  needsRestartHint(): boolean {
    return this.credentialResetTried;
  }

  private async doSignIn(): Promise<string | null> {
    this.lastSignInCode = 0;
    const credentialInfo: HwIdCredentialInfo = { kind: 'hwid' };
    const param: SignInParam = {
      credentialInfo: credentialInfo,
      autoCreateUser: true
    };
    hilog.info(AUTH_DOMAIN, AUTH_TAG, 'signIn start');
    try {
      const result = await auth.signIn(param);
      const uid = result.getUser().getUid();
      hilog.info(AUTH_DOMAIN, AUTH_TAG, 'signIn success uid: %{public}s', uid);
      return uid;
    } catch (err) {
      const e = err as BusinessError;
      this.lastSignInCode = e.code;
      hilog.error(AUTH_DOMAIN, AUTH_TAG, 'signIn failed, code: %{public}s, msg: %{public}s, raw: %{public}s',
        String(e.code), String(e.message), JSON.stringify(err));
      return null;
    }
  }

  // 静默获取当前登录用户 uid，未登录返回 null
  async getCurrentUid(): Promise<string | null> {
    try {
      const user = await auth.getCurrentUser();
      return user ? user.getUid() : null;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(AUTH_DOMAIN, AUTH_TAG, 'getCurrentUser failed, code: %{public}s, msg: %{public}s, raw: %{public}s',
        String(e.code), String(e.message), JSON.stringify(err));
      return null;
    }
  }

  // 退出登录，清除本地登录态
  async signOut(): Promise<boolean> {
    try {
      await auth.signOut();
      return true;
    } catch (err) {
      const e = err as Error;
      hilog.error(AUTH_DOMAIN, AUTH_TAG, 'signOut failed: %{public}s', e.message);
      return false;
    }
  }
}

export default new AuthService();
