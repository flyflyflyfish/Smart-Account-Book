import auth from '@hw-agconnect/auth';
import { cloudCommon, cloudDatabase } from '@kit.CloudFoundationKit';
import { Logger } from '../utils/Logger';
import { CLOUD_SCHEMA_FILE, CLOUD_ZONE_NAME } from '../common/constants';

/**
 * 云开发服务初始化：登录成功后调用，缓存 DatabaseZone 供云端仓储复用
 */
class CloudInit {
  private databaseZone: cloudDatabase.DatabaseZone | undefined = undefined;
  private ready: boolean = false;

  init(): void {
    try {
      const authProvider = auth.getAuthProvider();
      cloudCommon.init({
        region: cloudCommon.CloudRegion.CHINA,
        authProvider: authProvider,
        databaseOptions: { schema: CLOUD_SCHEMA_FILE }
      });
      this.databaseZone = cloudDatabase.zone(CLOUD_ZONE_NAME);
      this.ready = true;
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

  // 退出登录后失效，避免继续用旧凭证同步
  reset(): void {
    this.databaseZone = undefined;
    this.ready = false;
  }
}

export default new CloudInit();
