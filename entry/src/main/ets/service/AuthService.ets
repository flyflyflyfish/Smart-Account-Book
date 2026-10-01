import auth from '@hw-agconnect/auth';
import { HwIdCredentialInfo, SignInParam } from '@hw-agconnect/auth';
import util from '@ohos.util';
import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';

const AUTH_DOMAIN: number = 0xFF01;
const AUTH_TAG: string = 'AuthService';

/**
 * 认证服务封装：负责华为账号登录与用户身份获取，owner_uid 取自 getUid
 */
class AuthService {
  private inited: boolean = false;

  // 启动时读取 agconnect-services.json 初始化认证 SDK
  init(context: common.UIAbilityContext): void {
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
      const e = err as Error;
      hilog.error(AUTH_DOMAIN, AUTH_TAG, 'signIn failed: %{public}s', e.message);
      return null;
    }
  }

  // 静默获取当前登录用户 uid，未登录返回 null
  async getCurrentUid(): Promise<string | null> {
    try {
      const user = await auth.getCurrentUser();
      return user ? user.getUid() : null;
    } catch (err) {
      const e = err as Error;
      hilog.error(AUTH_DOMAIN, AUTH_TAG, 'getCurrentUser failed: %{public}s', e.message);
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
