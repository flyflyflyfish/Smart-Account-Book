import auth from '@hw-agconnect/auth';
import { cloudCommon, cloudDatabase } from '@kit.CloudFoundationKit';
import { Logger } from '../utils/Logger';
import { CLOUD_SCHEMA_FILE, CLOUD_ZONE_NAME } from '../common/constants';
import CloudSettingSync from '../service/CloudSettingSync';

/**
 * 云开发服务初始化：登录成功后调用，缓存 DatabaseZone 供云端仓储复用；
 * 同时把存储区与用户 uid 注入设置同步模块，启用设置/墓碑的即时上传
 */
class CloudInit {
  private databaseZone: cloudDatabase.DatabaseZone | undefined = undefined;
  private ready: boolean = false;

  init(ownerUid: string): void {
    try {
      const authProvider = auth.getAuthProvider();
      cloudCommon.init({
        region: cloudCommon.CloudRegion.CHINA,
        authProvider: authProvider,
        databaseOptions: { schema: CLOUD_SCHEMA_FILE }
      });
      this.databaseZone = cloudDatabase.zone(CLOUD_ZONE_NAME);
      this.ready = true;
      CloudSettingSync.attach(this.databaseZone, ownerUid);
      Logger.debug('云开发服务初始化完成');
    } catch (err) {
      const e = err as Error;
      Logger.error('云开发服务初始化失败', e.message);
    }
  }

  getZone(): cloudDatabase.DatabaseZone | undefined {
    return this.ready ? this.databaseZone : undefined;
  }

  isReady(): boolean {
    return this.ready;
  }

  // 退出登录后失效，避免继续用旧凭证同步；同步辅助记录一并清空
  reset(): void {
    this.databaseZone = undefined;
    this.ready = false;
    CloudSettingSync.detach();
  }
}

export default new CloudInit();
