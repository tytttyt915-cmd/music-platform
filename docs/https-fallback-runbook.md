# Plan B：HTTPS 兜底预案（仅当 v1.0.8 真机仍报 -1022 时启用）

> 制定时间：2026-10-09 上午 | 状态：待命，未执行
> 背景：用户已同意两步计划——① ATS 修复（v1.0.8 已交付，待真机验证）；② 若仍不通，直接上 HTTPS。
> 本预案仅在用户反馈 v1.0.8 仍失败后启用；若 v1.0.8 成功，本文件作废。

## 1. 买域名（用户操作）

- 腾讯云 DNSPod 注册 `.xyz` / `.top`，首年约 ¥10–30，支付宝可付。
- 国内注册商**强制实名认证**（上传身份证），通常几十分钟到几小时生效——这是整个链路里最不可控的耗时。
- DNSPod 控制台给域名加 A 记录 → `111.230.155.174`。

## 2. 免费证书（二选一，用户决策）

- **A. 腾讯云 SSL 控制台**：申请免费证书（TrustAsia DV，1 年有效）。域名走 DNSPod 解析可选"自动 DNS 验证"，审核约十几分钟~1 天；签发后下载 Nginx 版（.crt + .key）。
- **B. 服务器 acme.sh + Let's Encrypt**：nginx.conf 已预留 `/.well-known/acme-challenge/`（webroot `/var/www/certbot`），只需把宿主机目录挂进容器：
  `acme.sh --issue --webroot /var/www/certbot -d <域名>`；90 天有效，acme.sh 自动续期。

## 3. nginx 加 443（用户在服务器执行）

- `docker-compose.yml` 的 nginx 服务加端口映射：`"${NGINX_HTTPS_PORT:-443}:443"`，加证书挂载：`./nginx/ssl:/etc/nginx/ssl:ro`。
- `nginx/nginx.conf` 新增 server 块（location 照抄现有 80 块，含 `/audio/` 的 Range/206 头）：
  ```nginx
  server {
      listen 443 ssl;
      server_name <域名>;
      ssl_certificate     /etc/nginx/ssl/fullchain.crt;
      ssl_certificate_key /etc/nginx/ssl/priv.key;
      ssl_protocols TLSv1.2 TLSv1.3;
      # …其余 location 与 80 块一致…
  }
  ```
- 腾讯云安全组放行 443 端口；`docker compose up -d --force-recreate nginx` 后 `curl https://<域名>/health` 应返回 200。

## 4. App 切 https + 重新出包

- `API_URL` 改为 `https://<域名>`；后端所有对外 URL 同步走 https。
- Info.plist 无需任何 ATS 例外（https 默认放行）。
- 走现有流水线构建 v1.0.9 → Release → manifest → OTA 交付。

## 5. 时间预期（实话）

实名认证 + 证书签发**不是即时**的：最快 1–2 小时，慢则半天。若 v1.0.8 今晚失败，不要指望当场切完——先买域名把流程跑起来。

## 6. 合规提示（用户侧决策）

域名解析到境内服务器对外提供服务，名义上需要 ICP 备案；纯 App 接口场景执法重点在网站，但动手前用户心里要有数。

## 待用户拍板的点

1. 买哪个域名（名字用户定）；
2. 证书走腾讯云免费 DV 还是 acme.sh/Let's Encrypt。
