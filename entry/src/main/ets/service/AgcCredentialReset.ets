import { huks } from '@kit.UniversalKeystoreKit';
import preferences from '@ohos.data.preferences';
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import { BusinessError } from '@kit.BasicServicesKit';

const RESET_DOMAIN: number = 0xFF01;
const RESET_TAG: string = 'AgcCredReset';

// auth SDK 内部使用的 HUKS 密钥别名（agconnect_auth_keyAlies + 区域后缀），
// 由 SDK 字节码字符串池与设备日志交叉确认
const HUKS_KEY_ALIASES: string[] = [
  'agconnect_auth_keyAliesCN',
  'agconnect_auth_keyAlies'
];

// auth SDK 的本地凭证存储（StoredManager / ClientTokenStored），
// 由 SDK 字节码字符串池提取
const PREF_STORES: string[] = [
  'ohos_agc_credential_api12',
  'auth_storedManager',
  'auth_storedManager_fs',
  'auth_storedManager_sp'
];

// 文件名命中以下特征且非应用自身数据时，视为 AGC SDK 残留文件
function isAgcArtifact(name: string): boolean {
  const lower = name.toLowerCase();
  return lower.indexOf('agc') >= 0 || lower.indexOf('agconnect') >= 0 ||
    lower.indexOf('storedmanager') >= 0;
}

/**
 * 重置 AGC 认证 SDK 的本地凭证状态（HUKS 密钥 + 本地存储文件）。
 * 适用于覆盖安装后本地加密凭证损坏（HUKS GCM 校验失败 → 登录 401）的场景。
 * 应用自身数据（account_store、OCR 样本）不受影响。
 */
export async function resetAgcCredential(context: common.Context): Promise<boolean> {
  let allOk = true;
  for (const alias of HUKS_KEY_ALIASES) {
    try {
      const options: huks.HuksOptions = { properties: [] };
      await huks.deleteKeyItem(alias, options);
      hilog.info(RESET_DOMAIN, RESET_TAG, 'huks key deleted: %{public}s', alias);
    } catch (err) {
      const e = err as BusinessError;
      // 密钥不存在是预期情况（首次重置或已删除），不算失败
      hilog.info(RESET_DOMAIN, RESET_TAG, 'huks key %{public}s skip, code: %{public}d', alias, e.code);
    }
  }
  for (const name of PREF_STORES) {
    try {
      await preferences.deletePreferences(context, { name: name });
      hilog.info(RESET_DOMAIN, RESET_TAG, 'preference deleted: %{public}s', name);
    } catch (err) {
      const e = err as BusinessError;
      // 实例被 SDK 持有时删除会失败，后面兜底直接删文件
      hilog.info(RESET_DOMAIN, RESET_TAG, 'preference %{public}s skip, code: %{public}d', name, e.code);
    }
  }
  const dirs: string[] = [context.preferencesDir, context.filesDir];
  for (const dir of dirs) {
    try {
      const names: string[] = fs.listFileSync(dir);
      for (const name of names) {
        if (!isAgcArtifact(name)) {
          continue;
        }
        const full: string = `${dir}/${name}`;
        try {
          const stat = fs.statSync(full);
          if (stat.isDirectory()) {
            continue;
          }
          fs.unlinkSync(full);
          hilog.info(RESET_DOMAIN, RESET_TAG, 'file deleted: %{public}s', full);
        } catch (err) {
          const e = err as BusinessError;
          allOk = false;
          hilog.warn(RESET_DOMAIN, RESET_TAG, 'delete file %{public}s failed, code: %{public}d', full, e.code);
        }
      }
    } catch (err) {
      hilog.warn(RESET_DOMAIN, RESET_TAG, 'list dir %{public}s failed', dir);
    }
  }
  return allOk;
}
