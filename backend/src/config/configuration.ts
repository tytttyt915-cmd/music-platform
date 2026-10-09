/** 按 REDIS_HOST / REDIS_PORT / REDIS_PASSWORD 拼出连接 URL（含密码转义） */
function buildRedisUrl(): string {
  const host = process.env.REDIS_HOST ?? 'localhost';
  const port = process.env.REDIS_PORT ?? '6379';
  const password = process.env.REDIS_PASSWORD;
  return password
    ? `redis://:${encodeURIComponent(password)}@${host}:${port}`
    : `redis://${host}:${port}`;
}

export default () => ({
  port: parseInt(process.env.PORT ?? '3000', 10),
  nodeEnv: process.env.NODE_ENV ?? 'development',

  database: {
    host: process.env.DB_HOST ?? 'localhost',
    port: parseInt(process.env.DB_PORT ?? '5432', 10),
    username: process.env.DB_USERNAME ?? 'music',
    password: process.env.DB_PASSWORD ?? 'music_password',
    database: process.env.DB_DATABASE ?? 'musicdb',
  },
  redis: {
    // 显式 REDIS_URL 优先；否则按 REDIS_HOST / REDIS_PORT / REDIS_PASSWORD 自动拼接
    url: process.env.REDIS_URL ?? buildRedisUrl(),
  },

  jwt: {
    // 启动时强制校验：生产环境绝不允许默认密钥
    secret: process.env.JWT_SECRET ?? '',
    expiresIn: process.env.JWT_EXPIRES_IN ?? '3600s',
    refreshTtlDays: parseInt(process.env.REFRESH_TOKEN_TTL_DAYS ?? '30', 10),
  },

  auth: {
    mock: (process.env.AUTH_MOCK ?? 'true').toLowerCase() === 'true',
    smsMock: (process.env.SMS_MOCK ?? 'true').toLowerCase() === 'true',
    wechatAppId: process.env.WECHAT_APPID ?? '',
    wechatSecret: process.env.WECHAT_SECRET ?? '',
    smsProvider: process.env.SMS_PROVIDER ?? 'mock',
  },

  storage: {
    provider: (process.env.STORAGE_PROVIDER ?? 'oss').toLowerCase(),
    signedUrlTtl: parseInt(process.env.SIGNED_URL_TTL ?? '3600', 10),
    oss: {
      region: process.env.OSS_REGION ?? '',
      bucket: process.env.OSS_BUCKET ?? '',
      accessKeyId: process.env.OSS_ACCESS_KEY_ID ?? '',
      accessKeySecret: process.env.OSS_ACCESS_KEY_SECRET ?? '',
      endpoint: process.env.OSS_ENDPOINT ?? '',
    },
    cos: {
      region: process.env.COS_REGION ?? '',
      bucket: process.env.COS_BUCKET ?? '',
      secretId: process.env.COS_SECRET_ID ?? '',
      secretKey: process.env.COS_SECRET_KEY ?? '',
    },
  },

  prediction: {
    enabled: process.env.PREDICTION_ENABLED ?? 'true',
    timesfmUrl: process.env.TIMESFM_URL ?? 'http://127.0.0.1:8100',
    cacheTtlSec: process.env.PREDICTION_CACHE_TTL ?? '3600',
    candidateLimit: process.env.PREDICTION_CANDIDATES ?? '300',
    requestTimeoutMs: process.env.PREDICTION_TIMEOUT_MS ?? '15000',
  },

  // 第三方免费音乐 API（全都不用 key），单个服务挂了只降级不影响主流程
  external: {
    lyricsOvh: {
      enabled: process.env.LYRICSOVH_ENABLED ?? 'true',
      baseUrl: process.env.LYRICSOVH_BASE_URL ?? 'https://api.lyrics.ovh',
      timeoutMs: process.env.LYRICSOVH_TIMEOUT_MS ?? '5000',
    },
    musicbrainz: {
      enabled: process.env.MUSICBRAINZ_ENABLED ?? 'true',
      baseUrl: process.env.MUSICBRAINZ_BASE_URL ?? 'https://musicbrainz.org',
      userAgent:
        process.env.MUSICBRAINZ_USER_AGENT ??
        'music-platform/1.0 (https://github.com/tytttyt915-cmd/music-platform)',
      timeoutMs: process.env.MUSICBRAINZ_TIMEOUT_MS ?? '5000',
    },
    itunes: {
      enabled: process.env.ITUNES_ENABLED ?? 'true',
      baseUrl: process.env.ITUNES_BASE_URL ?? 'https://itunes.apple.com',
      country: process.env.ITUNES_COUNTRY ?? 'CN',
      timeoutMs: process.env.ITUNES_TIMEOUT_MS ?? '5000',
      maxResults: process.env.ITUNES_MAX_RESULTS ?? '5',
    },
  },
});
