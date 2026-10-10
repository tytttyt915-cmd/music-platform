-- 迁移 2026-10-10：补齐 10-09 新增的两列
-- 背景：服务器上的 postgres 是 10-08 晚用旧版 db/init.sql 手工建的，
-- 之后 45fc4d1（手动换源）加了 tracks.preferred_source、
-- 90f3841（波形进度条）加了 track_sources.peaks，
-- 后端已按新代码部署，但表结构没跟上，导致所有查 tracks/track_sources
-- 的接口（/music/feed、/music/search 等）报 500（column does not exist）。
-- 本文件幂等，可重复执行。

ALTER TABLE tracks
  ADD COLUMN IF NOT EXISTS preferred_source VARCHAR(16) NOT NULL DEFAULT 'auto';

ALTER TABLE track_sources
  ADD COLUMN IF NOT EXISTS peaks JSONB;

-- 可选：与 init.sql 保持一致的取值约束（如需）
-- ALTER TABLE tracks
--   ADD CONSTRAINT chk_tracks_preferred_source
--   CHECK (preferred_source IN ('auto', 'local', 'netease', 'qq', 'kugou'));

-- 验证：
-- SELECT column_name FROM information_schema.columns
--  WHERE table_name IN ('tracks', 'track_sources')
--    AND column_name IN ('preferred_source', 'peaks');
