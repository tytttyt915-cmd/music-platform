/**
 * 后端网关 API 客户端（对齐 Phase 1 NestJS 后端路由与 DTO）。
 *
 * 路由对照（backend/src）：
 * - POST /auth/guest | /auth/wechat/login | /auth/sms/send | /auth/sms/verify
 * - POST /auth/refresh | POST /auth/logout
 * - DELETE /account（注销账号，Apple 5.1.1(v) 合规）
 * - GET /music/feed?page=&pageSize= | GET /music/search?q=&page=&pageSize=
 * - GET /music/track/:id | GET /music/track/:id/lyrics
 * - GET /music/track/:id/stream?quality=（302 跳转到带防盗链签名的对象存储 URL）
 * - POST /music/track/:id/play（播放统计，防刷）
 */
import AsyncStorage from '@react-native-async-storage/async-storage';
import {
  API_URL,
  GUEST_FLAG_STORAGE_KEY,
  NICKNAME_STORAGE_KEY,
  REFRESH_TOKEN_STORAGE_KEY,
  TOKEN_STORAGE_KEY,
} from './config';

/** 音频码率（与后端 StreamQueryDto 的 TRACK_QUALITIES 对齐） */
export type AudioQuality = 'standard' | 'high' | 'lossless' | 'hires';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

export interface AuthResult extends TokenPair {
  isNew?: boolean;
}

/** 后端 Track 实体字段（对齐 backend/src/entities/track.entity.ts） */
export interface TrackInfo {
  id: string;
  title: string;
  artist: string;
  coverUrl: string | null;
  durationMs: number;
  playCount: string;
}

export interface PageResult<T> {
  list: T[];
  total: number;
  page: number;
  pageSize: number;
}

export interface LyricsResult {
  lrcText: string | null;
  lrcSynced: boolean;
}

export interface LocalProfile {
  nickname: string;
  isGuest: boolean;
}

/** 统一的 API 错误，携带 HTTP 状态码（0 表示网络层失败） */
export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
  }
}

function networkErrorMessage(e: unknown): string {
  if (e instanceof Error) {
    // React Native iOS 底层是 NSError，message 里通常带 code（如 -1009 断网、-1022 ATS 拦截）
    // 把 name 也带上，方便区分 TypeError(网络)/其他异常
    return `${e.name}: ${e.message}`;
  }
  return String(e);
}

// ---------------- 本地登录态 ----------------

export async function getStoredToken(): Promise<string | null> {
  return AsyncStorage.getItem(TOKEN_STORAGE_KEY);
}

async function saveTokens(
  pair: TokenPair,
  nickname: string,
  isGuest: boolean,
): Promise<void> {
  // AsyncStorage 3.x 用 setMany 批量写入（旧版 multiSet 已移除）
  await AsyncStorage.setMany({
    [TOKEN_STORAGE_KEY]: pair.accessToken,
    [REFRESH_TOKEN_STORAGE_KEY]: pair.refreshToken,
    [NICKNAME_STORAGE_KEY]: nickname,
    [GUEST_FLAG_STORAGE_KEY]: isGuest ? '1' : '0',
  });
}

export async function clearTokens(): Promise<void> {
  // AsyncStorage 3.x 用 removeMany 批量删除（旧版 multiRemove 已移除）
  await AsyncStorage.removeMany([
    TOKEN_STORAGE_KEY,
    REFRESH_TOKEN_STORAGE_KEY,
    NICKNAME_STORAGE_KEY,
    GUEST_FLAG_STORAGE_KEY,
  ]);
}

export async function getLocalProfile(): Promise<LocalProfile> {
  // AsyncStorage 3.x 用 getMany 批量读取（旧版 multiGet 已移除）
  const values = await AsyncStorage.getMany([
    NICKNAME_STORAGE_KEY,
    GUEST_FLAG_STORAGE_KEY,
  ]);
  return {
    nickname: values[NICKNAME_STORAGE_KEY] ?? '游客',
    isGuest: (values[GUEST_FLAG_STORAGE_KEY] ?? '1') === '1',
  };
}

// ---------------- 底层 fetch 封装 ----------------

/** 刷新 accessToken；失败返回 false（调用方应引导重新登录或重建游客身份） */
async function tryRefreshToken(): Promise<boolean> {
  try {
    const refreshToken = await AsyncStorage.getItem(REFRESH_TOKEN_STORAGE_KEY);
    if (!refreshToken) {
      return false;
    }
    const res = await fetch(`${API_URL}/auth/refresh`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({refreshToken}),
    });
    if (!res.ok) {
      return false;
    }
    const pair = (await res.json()) as TokenPair;
    if (!pair.accessToken) {
      return false;
    }
    await AsyncStorage.setItem(TOKEN_STORAGE_KEY, pair.accessToken);
    if (pair.refreshToken) {
      await AsyncStorage.setItem(REFRESH_TOKEN_STORAGE_KEY, pair.refreshToken);
    }
    return true;
  } catch (e) {
    console.warn('[api] refresh token 失败', networkErrorMessage(e));
    return false;
  }
}

/**
 * 带鉴权的 fetch 封装：
 * - 自动从 AsyncStorage 取 token 附加 Authorization: Bearer
 * - 401 时尝试 refresh 后重试一次；仍失败则清本地登录态并抛 ApiError(401)
 * - 非 2xx 统一抛 ApiError，优先读取后端返回的 message 字段
 */
export async function apiFetch<T>(
  path: string,
  init: RequestInit = {},
  retried = false,
): Promise<T> {
  const token = await AsyncStorage.getItem(TOKEN_STORAGE_KEY);
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...((init.headers as Record<string, string> | undefined) ?? {}),
  };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, {...init, headers});
  } catch (e) {
    throw new ApiError(0, `网络请求失败：${networkErrorMessage(e)}`);
  }

  if (res.status === 401 && !retried) {
    const ok = await tryRefreshToken();
    if (ok) {
      return apiFetch<T>(path, init, true);
    }
    await clearTokens();
    throw new ApiError(401, '登录已过期，请重新登录');
  }

  if (!res.ok) {
    let message = `请求失败（HTTP ${res.status}）`;
    try {
      const body = (await res.json()) as {message?: string | string[]};
      if (typeof body.message === 'string' && body.message) {
        message = body.message;
      } else if (Array.isArray(body.message)) {
        message = body.message.join('；');
      }
    } catch {
      // 响应体不是 JSON 时忽略，保持默认 message
    }
    throw new ApiError(res.status, message);
  }

  if (res.status === 204) {
    return undefined as unknown as T;
  }
  return (await res.json()) as T;
}

function post<T>(path: string, body: unknown): Promise<T> {
  return apiFetch<T>(path, {method: 'POST', body: JSON.stringify(body)});
}

// ---------------- 认证 ----------------

/** 纯净游客试听模式（Guideline 5.1.1）：未登录也可签发 token */
export async function guestLogin(): Promise<AuthResult> {
  const result = await post<AuthResult>('/auth/guest', {});
  const nickname = `游客${Math.floor(1000 + Math.random() * 9000)}`;
  await saveTokens(result, nickname, true);
  return result;
}

/** 微信授权登录：code 来自微信 SDK（未接入 SDK 时走后端 Mock 联调通道） */
export async function wechatLogin(code: string): Promise<AuthResult> {
  const result = await post<AuthResult>('/auth/wechat/login', {code});
  await saveTokens(result, '微信用户', false);
  return result;
}

/** 发送短信验证码 */
export async function sendSms(phone: string): Promise<{mock: boolean}> {
  return post<{mock: boolean}>('/auth/sms/send', {phone});
}

/** 校验短信验证码并登录 */
export async function verifySms(
  phone: string,
  code: string,
): Promise<AuthResult> {
  const result = await post<AuthResult>('/auth/sms/verify', {phone, code});
  await saveTokens(result, phone, false);
  return result;
}

/** 退出登录：服务端注销 refreshToken，本地清登录态（失败也不阻塞本地清理） */
export async function logout(): Promise<void> {
  try {
    const refreshToken = await AsyncStorage.getItem(REFRESH_TOKEN_STORAGE_KEY);
    if (refreshToken) {
      await apiFetch('/auth/logout', {
        method: 'POST',
        body: JSON.stringify({refreshToken}),
      });
    }
  } catch (e) {
    console.warn('[api] 服务端退出登录失败，仅清理本地', networkErrorMessage(e));
  } finally {
    await clearTokens();
  }
}

/**
 * 注销账号（Apple 5.1.1(v) 合规闭环）：
 * 服务端永久删除账号及云端数据 → 本地清登录态。
 */
export async function deleteAccount(): Promise<void> {
  await apiFetch<void>('/account', {method: 'DELETE'});
  await clearTokens();
}

// ---------------- 音乐 ----------------

export function getFeed(
  page = 1,
  pageSize = 20,
): Promise<PageResult<TrackInfo>> {
  return apiFetch<PageResult<TrackInfo>>(
    `/music/feed?page=${page}&pageSize=${pageSize}`,
  );
}

export function searchTracks(
  q: string,
  page = 1,
  pageSize = 20,
): Promise<PageResult<TrackInfo>> {
  return apiFetch<PageResult<TrackInfo>>(
    `/music/search?q=${encodeURIComponent(q)}&page=${page}&pageSize=${pageSize}`,
  );
}

export function getTrack(id: string): Promise<TrackInfo> {
  return apiFetch<TrackInfo>(`/music/track/${id}`);
}

export function getLyrics(id: string): Promise<LyricsResult> {
  return apiFetch<LyricsResult>(`/music/track/${id}/lyrics`);
}

/** 播放统计上报（后端做登录用户自然日去重防刷；失败不抛给调用方，由调用方决定） */
export function reportPlay(id: string, quality: AudioQuality): Promise<void> {
  return post<void>(`/music/track/${id}/play`, {quality});
}

/**
 * 获取播放地址：后端 /stream 接口返回 302 跳转到带防盗链签名的对象存储 URL。
 * 用 redirect:'manual' 拦截跳转，优先读取 Location 头拿到签名直链；
 * 兜底读取 response.url（某些 RN fetch 实现在 manual 下仍会跟随跳转）。
 * 音频字节由对象存储经 Nginx/CDN 直接下发，支持 HTTP Range 206。
 */
export async function getStreamUrl(
  id: string,
  quality: AudioQuality = 'high',
): Promise<string> {
  const token = await AsyncStorage.getItem(TOKEN_STORAGE_KEY);
  const reqUrl = `${API_URL}/music/track/${id}/stream?quality=${quality}`;
  let res: Response;
  try {
    res = await fetch(reqUrl, {
      headers: token ? {Authorization: `Bearer ${token}`} : {},
      // manual：不自动跟随 302，让我们拿到签名直链后自己交给播放器
      redirect: 'manual',
    });
  } catch (e) {
    throw new ApiError(0, `获取播放地址失败：${networkErrorMessage(e)}`);
  }

  if (res.status >= 300 && res.status < 400) {
    const location =
      res.headers.get('location') ?? res.headers.get('Location');
    if (location) {
      return location;
    }
  }
  if (res.url && res.url !== reqUrl) {
    return res.url;
  }
  throw new ApiError(res.status, '未获取到有效的播放地址');
}
