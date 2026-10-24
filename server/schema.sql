-- Lysay 后端数据库（Cloudflare D1）
-- 时间一律为毫秒时间戳

CREATE TABLE IF NOT EXISTS users (
  id              TEXT PRIMARY KEY,
  provider        TEXT NOT NULL,            -- apple / google
  provider_sub    TEXT NOT NULL,            -- 第三方账号的唯一 ID
  email           TEXT,
  name            TEXT,
  status          TEXT NOT NULL DEFAULT 'active',   -- active / disabled
  ai_seconds_used INTEGER NOT NULL DEFAULT 0,       -- AI 语音已用秒数
  created_at      INTEGER NOT NULL,
  last_login_at   INTEGER NOT NULL,
  UNIQUE (provider, provider_sub)
);

-- 每个用户当前的订阅（没有记录 = 无套餐）
CREATE TABLE IF NOT EXISTS subscriptions (
  user_id     TEXT PRIMARY KEY,
  plan_id     TEXT NOT NULL,
  started_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);

-- 订阅变动记录（后台升级、取消等）
CREATE TABLE IF NOT EXISTS subscription_events (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  action      TEXT NOT NULL,     -- grant / revoke
  plan_id     TEXT,
  amount      INTEGER,
  currency    TEXT,
  expires_at  INTEGER,
  operator    TEXT,              -- admin
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS plans (
  id        TEXT PRIMARY KEY,    -- monthly / yearly
  name      TEXT NOT NULL,
  price     INTEGER NOT NULL,
  currency  TEXT NOT NULL,
  days      INTEGER NOT NULL,
  sort      INTEGER NOT NULL DEFAULT 0,
  active    INTEGER NOT NULL DEFAULT 1
);

INSERT OR IGNORE INTO plans (id, name, price, currency, days, sort) VALUES
  ('monthly', 'Pro 月付', 150, 'TWD', 30, 1),
  ('yearly',  'Pro 年付', 550, 'TWD', 365, 2);

-- 剪贴板同步：收藏文件夹、文件夹里的文字、剪贴板记录
CREATE TABLE IF NOT EXISTS clip_folders (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  name        TEXT NOT NULL,
  sort        REAL NOT NULL DEFAULT 0,
  updated_at  INTEGER NOT NULL,
  deleted     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_clip_folders_user ON clip_folders (user_id, updated_at);

CREATE TABLE IF NOT EXISTS clip_items (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  folder_id   TEXT,
  text        TEXT NOT NULL,
  sort        REAL NOT NULL DEFAULT 0,
  updated_at  INTEGER NOT NULL,
  deleted     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_clip_items_user ON clip_items (user_id, updated_at);

CREATE TABLE IF NOT EXISTS clip_history (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL,
  text        TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  deleted     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_clip_history_user ON clip_history (user_id, updated_at);

-- Apple App 内购买订阅（以 originalTransactionId 对应用户）
CREATE TABLE IF NOT EXISTS iap_transactions (
  original_transaction_id TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL,
  product_id   TEXT NOT NULL,
  expires_at   INTEGER,
  environment  TEXT,
  revoked      INTEGER NOT NULL DEFAULT 0,
  updated_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_iap_user ON iap_transactions (user_id);
