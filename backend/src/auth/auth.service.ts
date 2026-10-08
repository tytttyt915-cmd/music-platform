import {
  BadRequestException,
  Inject,
  Injectable,
  Logger,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { createHash, randomBytes } from 'crypto';
import { Redis } from 'ioredis';
import { Repository } from 'typeorm';
import { REDIS_CLIENT } from '../redis/redis.module';
import { RefreshToken } from '../entities/refresh-token.entity';
import {
  User,
  USER_STATUS_ACTIVE,
  USER_STATUS_DELETED,
} from '../entities/user.entity';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  tokenType: 'Bearer';
  expiresIn: string;
}

interface WechatSessionResult {
  unionid: string;
  openid: string;
}

const SMS_CODE_KEY = (phone: string) => `sms:code:${phone}`;
const SMS_CODE_TTL_SEC = 600;
const MOCK_SMS_CODE = '123456';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly config: ConfigService,
    private readonly jwtService: JwtService,
    @InjectRepository(User)
    private readonly usersRepo: Repository<User>,
    @InjectRepository(RefreshToken)
    private readonly refreshRepo: Repository<RefreshToken>,
    @Inject(REDIS_CLIENT)
    private readonly redis: Redis,
  ) {}

  // ---------------- 微信登录 ----------------

  async wechatLogin(code: string): Promise<TokenPair & { isNew: boolean }> {
    const session = await this.resolveWechatSession(code);
    let user = await this.usersRepo.findOne({
      where: { unionid: session.unionid, status: USER_STATUS_ACTIVE },
    });
    let isNew = false;
    if (!user) {
      user = this.usersRepo.create({
        unionid: session.unionid,
        phone: null,
        isGuest: false,
        status: USER_STATUS_ACTIVE,
      });
      await this.usersRepo.save(user);
      isNew = true;
      this.logger.log(`微信新用户创建: ${user.id} (unionid 已脱敏)`);
    }
    const tokens = await this.issueTokens(user);
    return { ...tokens, isNew };
  }

  private async resolveWechatSession(code: string): Promise<WechatSessionResult> {
    const mock = this.config.get<boolean>('auth.mock', true);
    if (mock) {
      // Mock 模式：任意 code 均可登录，unionid 由 code 派生（不同 code = 不同测试用户）
      return { unionid: `mock:${code}`, openid: `mock_openid:${code}` };
    }

    const appId = this.config.get<string>('auth.wechatAppId', '');
    const secret = this.config.get<string>('auth.wechatSecret', '');
    if (!appId || !secret) {
      throw new ServiceUnavailableException(
        '微信登录未配置：AUTH_MOCK=false 时必须设置 WECHAT_APPID / WECHAT_SECRET',
      );
    }

    const url =
      `https://api.weixin.qq.com/sns/jscode2session` +
      `?appid=${encodeURIComponent(appId)}` +
      `&secret=${encodeURIComponent(secret)}` +
      `&js_code=${encodeURIComponent(code)}` +
      `&grant_type=authorization_code`;

    let data: Record<string, unknown>;
    try {
      const res = await fetch(url, {
        signal: AbortSignal.timeout(8000),
      });
      data = (await res.json()) as Record<string, unknown>;
    } catch (err) {
      this.logger.error(`微信 code2session 网络失败: ${String(err)}`);
      throw new ServiceUnavailableException('微信登录服务暂时不可用，请稍后重试');
    }

    if (data.errcode && Number(data.errcode) !== 0) {
      this.logger.warn(`微信 code2session 失败: errcode=${data.errcode}`);
      throw new BadRequestException(`微信登录失败 (${data.errmsg ?? data.errcode})`);
    }

    // unionid 要求小程序已绑定开放平台；未绑定时降级用 openid 标识
    const unionid = (data.unionid as string) ?? `openid:${data.openid as string}`;
    const openid = (data.openid as string) ?? '';
    if (!openid) {
      throw new BadRequestException('微信登录失败：未获取到 openid');
    }
    return { unionid, openid };
  }

  // ---------------- 短信验证码 ----------------

  async sendSmsCode(phone: string): Promise<{ mock: boolean }> {
    const smsMock = this.config.get<boolean>('auth.smsMock', true);
    const code = smsMock
      ? MOCK_SMS_CODE
      : String(Math.floor(100000 + Math.random() * 900000));

    if (smsMock) {
      this.logger.warn(`[SMS Mock] ${phone} 的验证码为 ${code}（AUTH_MOCK/SMS_MOCK 模式）`);
    } else {
      await this.sendRealSms(phone, code);
    }

    await this.redis.set(SMS_CODE_KEY(phone), code, 'EX', SMS_CODE_TTL_SEC);
    return { mock: smsMock };
  }

  /** 真实短信通道扩展点：按 SMS_PROVIDER 接入阿里云/腾讯云短信 */
  private async sendRealSms(phone: string, _code: string): Promise<void> {
    const provider = this.config.get<string>('auth.smsProvider', 'mock');
    // TODO: 在此处按 provider 接入真实短信网关：
    //   - aliyun: @alicloud/dysmsapi20170525
    //   - tencent: tencentcloud-sdk-nodejs SmsClient
    // 接入完成后将 SMS_MOCK 设为 false 即可平滑切换。
    this.logger.error(`短信通道 ${provider} 尚未接入实现`);
    throw new ServiceUnavailableException(
      `短信服务未配置：SMS_PROVIDER=${provider} 尚未接入，请先完成短信网关对接或保持 SMS_MOCK=true`,
    );
  }

  async verifySmsCode(
    phone: string,
    code: string,
  ): Promise<TokenPair & { isNew: boolean }> {
    const stored = await this.redis.get(SMS_CODE_KEY(phone));
    if (!stored) {
      throw new BadRequestException('验证码已过期，请重新获取');
    }
    if (stored !== code) {
      throw new BadRequestException('验证码不正确');
    }
    await this.redis.del(SMS_CODE_KEY(phone));

    let user = await this.usersRepo.findOne({
      where: { phone, status: USER_STATUS_ACTIVE },
    });
    let isNew = false;
    if (!user) {
      user = this.usersRepo.create({
        phone,
        unionid: null,
        isGuest: false,
        status: USER_STATUS_ACTIVE,
      });
      await this.usersRepo.save(user);
      isNew = true;
      this.logger.log(`手机号新用户创建: ${user.id}`);
    }
    const tokens = await this.issueTokens(user);
    return { ...tokens, isNew };
  }

  // ---------------- 游客 ----------------

  /** 纯净游客试听模式（Guideline 5.1.1）：无任何身份标识即可签发 token */
  async guestLogin(): Promise<TokenPair> {
    const user = this.usersRepo.create({
      unionid: null,
      phone: null,
      isGuest: true,
      status: USER_STATUS_ACTIVE,
    });
    await this.usersRepo.save(user);
    return this.issueTokens(user);
  }

  // ---------------- Token 签发 / 刷新 / 吊销 ----------------

  private async issueTokens(user: User): Promise<TokenPair> {
    const payload = { sub: user.id, isGuest: user.isGuest };
    const accessToken = this.jwtService.sign(payload);

    const refreshToken = randomBytes(32).toString('hex');
    const tokenHash = createHash('sha256').update(refreshToken).digest('hex');
    const ttlDays = this.config.get<number>('jwt.refreshTtlDays', 30);
    const expiresAt = new Date(Date.now() + ttlDays * 86400 * 1000);

    await this.refreshRepo.save(
      this.refreshRepo.create({ userId: user.id, tokenHash, expiresAt }),
    );

    return {
      accessToken,
      refreshToken,
      tokenType: 'Bearer',
      expiresIn: this.config.get<string>('jwt.expiresIn', '3600s'),
    };
  }

  private hashToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  async refresh(refreshToken: string): Promise<TokenPair> {
    const tokenHash = this.hashToken(refreshToken);
    const stored = await this.refreshRepo.findOne({
      where: { tokenHash, revoked: false },
    });
    if (!stored || stored.expiresAt.getTime() <= Date.now()) {
      throw new UnauthorizedException('refreshToken 无效或已过期');
    }

    const user = await this.usersRepo.findOne({
      where: { id: stored.userId, status: USER_STATUS_ACTIVE },
    });
    if (!user) {
      throw new UnauthorizedException('用户不存在或已被注销');
    }

    // 轮换：吊销旧 token 后再签发新 token 对（防重放）
    await this.refreshRepo.update({ id: stored.id }, { revoked: true });
    return this.issueTokens(user);
  }

  async logout(userId: string, refreshToken: string): Promise<void> {
    const tokenHash = this.hashToken(refreshToken);
    await this.refreshRepo.update(
      { userId, tokenHash, revoked: false },
      { revoked: true },
    );
  }

  // ---------------- 账号注销（Apple 5.1.1(v)） ----------------

  /**
   * 账号注销闭环：
   *  - 吊销该用户全部 refresh token
   *  - 软删除用户：status='deleted'，unionid/phone 置空（避免唯一键冲突，允许重新注册），
   *    身份标识脱敏。isGuest 置 true 以满足 chk_user_identity 约束。
   */
  async deleteAccount(userId: string): Promise<void> {
    await this.usersRepo.manager.transaction(async (manager) => {
      await manager.update(
        RefreshToken,
        { userId, revoked: false },
        { revoked: true },
      );
      const result = await manager.update(
        User,
        { id: userId, status: USER_STATUS_ACTIVE },
        {
          status: USER_STATUS_DELETED,
          deletedAt: () => 'now()',
          unionid: null,
          phone: null,
          nickname: null,
          avatarUrl: null,
          isGuest: true,
        },
      );
      if ((result.affected ?? 0) === 0) {
        throw new BadRequestException('账号不存在或已被注销');
      }
    });
    this.logger.log(`账号已注销（软删除）: ${userId}`);
  }
}
