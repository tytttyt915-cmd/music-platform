/**
* 网关地址与本地存储键配置。
*
* 把 API_URL 替换为你自己的后端网关公网地址
*（Phase 1 部署的 NestJS 服务，建议经 Nginx 反向代理后的 HTTPS 地址）。
*/
export const API_URL = 'http://YOUR_SERVER_IP/audio';

/** AsyncStorage 存储键 */
export const TOKEN_STORAGE_KEY = '@musicapp/access_token';
export const REFRESH_TOKEN_STORAGE_KEY = '@musicapp/refresh_token';
export const NICKNAME_STORAGE_KEY = '@musicapp/nickname';
export const GUEST_FLAG_STORAGE_KEY = '@musicapp/is_guest';
