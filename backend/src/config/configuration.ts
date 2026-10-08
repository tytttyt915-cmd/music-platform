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
    url: process.env.REDIS_URL ?? 'redis://localhost:6379',
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
});
