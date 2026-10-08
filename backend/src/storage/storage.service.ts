import {
  Injectable,
  Logger,
  OnModuleInit,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import OSS from '@alicloud/oss';
import COS from 'cos-nodejs-sdk-v5';

export type StorageProvider = 'oss' | 'cos' | 'none';

/**
 * 对象存储预签名服务。
 * 按 STORAGE_PROVIDER 选择 oss / cos / none。
 * none = 未配置对象存储：后端可正常启动（登录/搜索/歌单可用），
 * 仅 /music/track/:id/stream 返回 503 提示补配存储。
 * oss / cos 缺配置时启动即抛错说明原因。
 */
@Injectable()
export class StorageService implements OnModuleInit {
  private readonly logger = new Logger(StorageService.name);
  private readonly provider: StorageProvider;
  private readonly ttl: number;
  private ossClient: OSS | null = null;
  private cosClient: COS | null = null;

  constructor(private readonly config: ConfigService) {
    const provider = this.config.get<string>('storage.provider', 'oss');
    if (provider !== 'oss' && provider !== 'cos' && provider !== 'none') {
      throw new Error(
        `STORAGE_PROVIDER 非法: "${provider}"，仅支持 oss | cos | none`,
      );
    }
    this.provider = provider;
    this.ttl = this.config.get<number>('storage.signedUrlTtl', 3600);
    if (!Number.isFinite(this.ttl) || this.ttl <= 0) {
      throw new Error(`SIGNED_URL_TTL 非法: "${this.ttl}"，必须为正整数（秒）`);
    }
  }

  onModuleInit() {
    if (this.provider === 'none') {
      this.logger.warn(
        'STORAGE_PROVIDER=none：对象存储未配置，音频流接口将返回 503，补配 COS/OSS 后重启生效',
      );
      return;
    }
    if (this.provider === 'oss') {
      const { region, bucket, accessKeyId, accessKeySecret, endpoint } =
        this.config.get('storage.oss');
      const missing: string[] = [];
      if (!region) missing.push('OSS_REGION');
      if (!bucket) missing.push('OSS_BUCKET');
      if (!accessKeyId) missing.push('OSS_ACCESS_KEY_ID');
      if (!accessKeySecret) missing.push('OSS_ACCESS_KEY_SECRET');
      if (missing.length > 0) {
        throw new Error(
          `STORAGE_PROVIDER=oss 但缺少配置: ${missing.join(', ')}，请在环境变量中补齐后重启`,
        );
      }
      this.ossClient = new OSS({
        region,
        bucket,
        accessKeyId,
        accessKeySecret,
        ...(endpoint ? { endpoint } : {}),
      });
      this.logger.log(`Storage provider: oss (bucket=${bucket}, ttl=${this.ttl}s)`);
    } else {
      const { region, bucket, secretId, secretKey } =
        this.config.get('storage.cos');
      const missing: string[] = [];
      if (!region) missing.push('COS_REGION');
      if (!bucket) missing.push('COS_BUCKET');
      if (!secretId) missing.push('COS_SECRET_ID');
      if (!secretKey) missing.push('COS_SECRET_KEY');
      if (missing.length > 0) {
        throw new Error(
          `STORAGE_PROVIDER=cos 但缺少配置: ${missing.join(', ')}，请在环境变量中补齐后重启`,
        );
      }
      this.cosClient = new COS({ SecretId: secretId, SecretKey: secretKey });
      this.logger.log(`Storage provider: cos (bucket=${bucket}, ttl=${this.ttl}s)`);
    }
  }

  /** 生成对象存储 GET 预签名 URL（防盗链，SIGNED_URL_TTL 秒有效） */
  async signGetUrl(storageKey: string): Promise<string> {
    if (!storageKey) {
      throw new Error('storageKey 不能为空');
    }
    if (this.provider === 'none') {
      throw new ServiceUnavailableException(
        '对象存储未配置（STORAGE_PROVIDER=none），请补配 COS/OSS 后重启后端',
      );
    }
    if (this.provider === 'oss') {
      // @alicloud/oss: signatureUrl 同步返回签名 URL
      return this.ossClient!.signatureUrl(storageKey, {
        expires: this.ttl,
      }) as string;
    }
    const { region, bucket } = this.config.get('storage.cos');
    return this.cosClient!.getObjectUrl({
      Bucket: bucket,
      Region: region,
      Key: storageKey,
      Sign: true,
      Expires: this.ttl,
    });
  }
}
