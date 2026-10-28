import auth from '@hw-agconnect/auth';
import { AuthUser, HwIdCredentialInfo, SignInParam } from '@hw-agconnect/auth';
import util from '@ohos.util';
import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import { BusinessError } from '@kit.BasicServicesKit';
import { authentication } from '@kit.AccountKit';
import { resetAgcCredential } from './AgcCredentialReset';

const AUTH_DOMAIN: number = 0xFF01;
const AUTH_TAG: string = 'AuthService';

// 登录用户资料：uid 必有；昵称/头像由华为账号授权决定，未授权或未设置时为空串
export interface AccountProfile {
  uid: string;
  displayName: string;
  photoUrl: string;
}

// 华为账号头像昵称授权结果（Account Kit profile scope）
export interface HuaweiProfile {
  nickName: string;
  avatarUri: string;
}

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

  // 华为账号登录：首次会拉起华为账号授权，成功后返回 AGC 用户资料（含昵称/头像）
  async signInWithHuaweiId(): Promise<AccountProfile | null> {
    let profile = await this.doSignIn();
    // 401 且极快返回 = 本地加密凭证损坏（HUKS 解密失败），重置 AGC 本地凭证后原地重试一次
    if (!profile && this.lastSignInCode === 401 && !this.credentialResetTried && this.context) {
      this.credentialResetTried = true;
      hilog.warn(AUTH_DOMAIN, AUTH_TAG, 'signIn rejected locally (401), resetting AGC local credential');
      const resetOk = await resetAgcCredential(this.context);
      hilog.info(AUTH_DOMAIN, AUTH_TAG, 'reset AGC local credential done: %{public}s', String(resetOk));
      profile = await this.doSignIn();
    }
    return profile;
  }

  // 本次进程内是否已执行过凭证重置（供 UI 判断是否提示重启应用）
  needsRestartHint(): boolean {
    return this.credentialResetTried;
  }

  private async doSignIn(): Promise<AccountProfile | null> {
    this.lastSignInCode = 0;
    const credentialInfo: HwIdCredentialInfo = { kind: 'hwid' };
    const param: SignInParam = {
      credentialInfo: credentialInfo,
      autoCreateUser: true
    };
    hilog.info(AUTH_DOMAIN, AUTH_TAG, 'signIn start');
    try {
      const result = await auth.signIn(param);
      const user = result.getUser();
      const profile: AccountProfile = this.toProfile(user);
      hilog.info(AUTH_DOMAIN, AUTH_TAG, 'signIn success uid: %{public}s', profile.uid);
      return profile;
    } catch (err) {
      const e = err as BusinessError;
      this.lastSignInCode = e.code;
      hilog.error(AUTH_DOMAIN, AUTH_TAG, 'signIn failed, code: %{public}s, msg: %{public}s, raw: %{public}s',
        String(e.code), String(e.message), JSON.stringify(err));
      return null;
    }
  }

  // 静默获取当前登录用户资料（含昵称/头像），未登录返回 null
  async getCurrentProfile(): Promise<AccountProfile | null> {
    try {
      const user = await auth.getCurrentUser();
      if (!user) {
        return null;
      }
      return this.toProfile(user);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(AUTH_DOMAIN, AUTH_TAG, 'getCurrentProfile failed, code: %{public}s, msg: %{public}s',
        String(e.code), String(e.message));
      return null;
    }
  }

  // 请求华为账号头像昵称授权（profile scope）：force=true 且未授权时拉起授权页，已授权时静默返回；取消/失败返回 null
  async requestHuaweiProfile(context: common.Context, force: boolean): Promise<HuaweiProfile | null> {
    try {
      const authRequest = new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest();
      authRequest.scopes = ['profile'];
      authRequest.forceAuthorization = force;
      authRequest.state = util.generateRandomUUID();
      const controller = new authentication.AuthenticationController(context);
      const data = await controller.executeRequest(authRequest);
      const response = data as authentication.AuthorizationWithHuaweiIDResponse;
      // state 一致性校验，防止跨站攻击
      const reqState = authRequest.state ? authRequest.state : '';
      const respState = response.state ? response.state : '';
      if (reqState !== respState) {
        hilog.error(AUTH_DOMAIN, AUTH_TAG, 'profile auth state mismatch, req: %{public}s, resp: %{public}s',
          reqState, respState);
        return null;
      }
      const credential = response.data;
      if (!credential) {
        hilog.error(AUTH_DOMAIN, AUTH_TAG, 'profile auth response has no credential');
        return null;
      }
      const profile: HuaweiProfile = {
        nickName: credential.nickName ? credential.nickName : '',
        avatarUri: credential.avatarUri ? credential.avatarUri : ''
      };
      hilog.info(AUTH_DOMAIN, AUTH_TAG, 'profile auth success, hasName: %{public}s, hasAvatar: %{public}s',
        String(profile.nickName.length > 0), String(profile.avatarUri.length > 0));
      return profile;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(AUTH_DOMAIN, AUTH_TAG, 'profile auth failed, code: %{public}s, msg: %{public}s',
        String(e.code), String(e.message));
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

  // SDK 边界兜底：getDisplayName/getPhotoUrl 在账号未授权昵称/头像时返回 undefined，统一归一为空串
  private toProfile(user: AuthUser): AccountProfile {
    const uid = user.getUid();
    const displayName = user.getDisplayName();
    const photoUrl = user.getPhotoUrl();
    const profile: AccountProfile = {
      uid: uid ? uid : '',
      displayName: displayName ? displayName : '',
      photoUrl: photoUrl ? photoUrl : ''
    };
    return profile;
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
