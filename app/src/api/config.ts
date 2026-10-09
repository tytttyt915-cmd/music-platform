/**
* 网关地址与本地存储键配置。
*
* 后端网关公网地址（docker-compose 的 Nginx 入口，默认 80 端口）。
* 各接口路径（/auth/*、/music/*）由 client.ts 自行拼接，不要带多余后缀。
*/
export const API_URL = 'https://111.230.155.174';

/** AsyncStorage 存储键 */
export const TOKEN_STORAGE_KEY = '@musicapp/access_token';
export const REFRESH_TOKEN_STORAGE_KEY = '@musicapp/refresh_token';
export const NICKNAME_STORAGE_KEY = '@musicapp/nickname';
export const GUEST_FLAG_STORAGE_KEY = '@musicapp/is_guest';
