-- ============================================================
-- music-platform Phase 1: 流媒体数据库建表 DDL
-- PostgreSQL 16 · 幂等初始化脚本（docker-entrypoint-initdb.d）
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------- 用户表 ----------------
-- 微信 unionid / 手机号双绑定；status='deleted' 为软删除（账号注销闭环）
CREATE TABLE IF NOT EXISTS users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    unionid     VARCHAR(64) UNIQUE,
    phone       VARCHAR(20) UNIQUE,
    nickname    VARCHAR(64),
    avatar_url  TEXT,
    is_guest    BOOLEAN NOT NULL DEFAULT TRUE,   -- 纯净游客试听模式
    status      VARCHAR(16) NOT NULL DEFAULT 'active'
                CHECK (status IN ('active', 'deleted')),
    deleted_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_user_identity CHECK (unionid IS NOT NULL OR phone IS NOT NULL OR is_guest)
);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_users_unionid ON users(unionid) WHERE status = 'active';

-- ---------------- 歌曲主表 ----------------
CREATE TABLE IF NOT EXISTS tracks (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title        VARCHAR(255) NOT NULL,
    artist       VARCHAR(255) NOT NULL,
    album        VARCHAR(255),
    cover_url    TEXT,
    duration_ms  INTEGER NOT NULL DEFAULT 0 CHECK (duration_ms >= 0),
    lrc_text     TEXT,                        -- LRC 歌词原文
    lrc_synced   BOOLEAN NOT NULL DEFAULT FALSE,
    play_count   BIGINT NOT NULL DEFAULT 0,    -- 防刷后的有效播放数
    status       VARCHAR(16) NOT NULL DEFAULT 'online'
                 CHECK (status IN ('online', 'offline')),
    preferred_source VARCHAR(16) NOT NULL DEFAULT 'auto'
                 CHECK (preferred_source IN ('auto', 'local', 'netease', 'qq', 'kugou')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist);
CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title);
CREATE INDEX IF NOT EXISTS idx_tracks_status ON tracks(status) WHERE status = 'online';

-- ---------------- 多码率元数据 ----------------
CREATE TABLE IF NOT EXISTS track_sources (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    track_id        UUID NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    quality         VARCHAR(16) NOT NULL
                    CHECK (quality IN ('standard', 'high', 'lossless', 'hires')),
    bitrate_kbps    INTEGER NOT NULL CHECK (bitrate_kbps > 0),
    sample_rate_hz  INTEGER,
    file_size_bytes BIGINT CHECK (file_size_bytes >= 0),
    storage_key     TEXT NOT NULL,             -- OSS / COS object key，下发时动态签名
    duration_ms     INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_track_quality UNIQUE (track_id, quality)
);
CREATE INDEX IF NOT EXISTS idx_track_sources_track ON track_sources(track_id);

-- ---------------- 歌单 ----------------
CREATE TABLE IF NOT EXISTS playlists (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id    UUID REFERENCES users(id) ON DELETE SET NULL,
    title       VARCHAR(255) NOT NULL,
    cover_url   TEXT,
    is_public   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS playlist_tracks (
    playlist_id UUID NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    track_id    UUID NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    position    INTEGER NOT NULL DEFAULT 0,
    added_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (playlist_id, track_id)
);
CREATE INDEX IF NOT EXISTS idx_playlist_tracks_pos ON playlist_tracks(playlist_id, position);

-- ---------------- 播放事件（防刷） ----------------
-- 同一登录用户同一歌曲自然日内只计一次有效播放（函数唯一索引）
CREATE TABLE IF NOT EXISTS play_events (
    id         BIGSERIAL PRIMARY KEY,
    user_id    UUID REFERENCES users(id) ON DELETE SET NULL,
    track_id   UUID NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    quality    VARCHAR(16),
    ip         INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_play_events_daily
    ON play_events (user_id, track_id, (created_at::date))
    WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_play_events_track_day ON play_events (track_id, created_at);

-- ---------------- 刷新令牌 ----------------
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  CHAR(64) NOT NULL,             -- SHA-256 hex
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id) WHERE revoked = FALSE;

-- ---------------- updated_at 自动维护 ----------------
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_users_updated') THEN
        CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users
            FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_tracks_updated') THEN
        CREATE TRIGGER trg_tracks_updated BEFORE UPDATE ON tracks
            FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_playlists_updated') THEN
        CREATE TRIGGER trg_playlists_updated BEFORE UPDATE ON playlists
            FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    END IF;
END $$;

-- ---------------- 种子数据（联调用，可删除） ----------------
INSERT INTO tracks (id, title, artist, album, duration_ms, lrc_text, lrc_synced)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    '测试曲目 · 夜航星',
    'Demo Artist',
    'Demo Album',
    213000,
    '[00:00.00]测试曲目 · 夜航星' || chr(10) || '[00:05.00]第一行歌词' || chr(10) || '[00:10.00]第二行歌词',
    TRUE
) ON CONFLICT (id) DO NOTHING;

INSERT INTO track_sources (track_id, quality, bitrate_kbps, sample_rate_hz, file_size_bytes, storage_key, duration_ms)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'standard', 128, 44100, 3400000, 'audio/demo/yehangxing_128.mp3', 213000),
    ('11111111-1111-1111-1111-111111111111', 'high',     320, 44100, 8500000, 'audio/demo/yehangxing_320.mp3', 213000)
ON CONFLICT (track_id, quality) DO NOTHING;
