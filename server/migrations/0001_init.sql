-- UpSite: ilk şema

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL,
  apns_token TEXT,
  apns_env TEXT NOT NULL DEFAULT 'production',
  lang TEXT NOT NULL DEFAULT 'tr',
  tz TEXT NOT NULL DEFAULT 'Europe/Istanbul',
  retries INTEGER NOT NULL DEFAULT 2,
  timeout_s INTEGER NOT NULL DEFAULT 15,
  quiet_start TEXT,
  quiet_end TEXT,
  created_at INTEGER NOT NULL,
  last_seen INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sites (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  name TEXT NOT NULL,
  interval_min INTEGER NOT NULL,
  anchor_min INTEGER NOT NULL,
  notify_down INTEGER NOT NULL DEFAULT 1,
  notify_up INTEGER NOT NULL DEFAULT 1,
  paused INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'unknown',
  status_since INTEGER,
  last_code INTEGER,
  last_error TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sites_device ON sites(device_id);

-- Her kontrol turunda cihaz başına tek satır: {"<siteId>": <kod veya -1>}
CREATE TABLE IF NOT EXISTS runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id TEXT NOT NULL,
  at_min INTEGER NOT NULL,
  data TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS runs_device_at ON runs(device_id, at_min);

CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  site_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  at INTEGER NOT NULL,
  kind TEXT NOT NULL,
  code INTEGER,
  error TEXT
);
CREATE INDEX IF NOT EXISTS events_site ON events(site_id, at);
CREATE INDEX IF NOT EXISTS events_device ON events(device_id);

CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
