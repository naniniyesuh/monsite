-- UpSite 2.1: paketler
--
-- Siteler artık bir pakete ait. Paketin üyeleri (cihazlar) aynı siteleri görür; her site
-- pakette yalnızca bir kez kontrol edilir. Bildirim tercihleri üye başınadır (site_prefs).
-- Yanlış alarm ayarları (tekrar deneme, zaman aşımı) paket düzeyindedir.

CREATE TABLE packages (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  join_key TEXT NOT NULL UNIQUE,
  owner_id TEXT,
  retries INTEGER NOT NULL DEFAULT 2,
  timeout_s INTEGER NOT NULL DEFAULT 15,
  created_at INTEGER NOT NULL
);

CREATE TABLE members (
  package_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  joined_at INTEGER NOT NULL,
  PRIMARY KEY (package_id, device_id)
) WITHOUT ROWID;
CREATE INDEX members_device ON members(device_id);

-- Satır yoksa varsayılan: iki bildirim de açık.
CREATE TABLE site_prefs (
  site_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  notify_down INTEGER NOT NULL,
  notify_up INTEGER NOT NULL,
  PRIMARY KEY (site_id, device_id)
) WITHOUT ROWID;

-- Yönetici ekranındaki haber akışı (paket oluşturuldu, silindi …).
CREATE TABLE admin_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  at INTEGER NOT NULL,
  kind TEXT NOT NULL,
  package_id TEXT,
  text TEXT NOT NULL
);

-- sites tablosu yeniden kuruluyor: package_id eklenir ve devices'a olan ON DELETE CASCADE kaldırılır
-- (bir üye uygulamayı silince ortak paketteki, onun eklediği siteler silinmemeli).
CREATE TABLE sites_new (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  package_id TEXT,
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
INSERT INTO sites_new (id, device_id, package_id, url, name, interval_min, anchor_min, notify_down, notify_up, paused, status, status_since, last_code, last_error, created_at)
  SELECT id, device_id, 'p-' || device_id, url, name, interval_min, anchor_min, notify_down, notify_up, paused, status, status_since, last_code, last_error, created_at FROM sites;
DROP TABLE sites;
ALTER TABLE sites_new RENAME TO sites;
CREATE INDEX sites_device ON sites(device_id);
CREATE INDEX sites_package ON sites(package_id);

-- Mevcut veriler: sitesi olan her cihaza kişisel paket.
INSERT INTO packages (id, name, join_key, owner_id, retries, timeout_s, created_at)
  SELECT 'p-' || d.id,
         CASE d.lang WHEN 'en' THEN 'My sites' ELSE 'Sitelerim' END,
         upper(hex(randomblob(6))),
         d.id, d.retries, d.timeout_s, d.created_at
  FROM devices d
  WHERE EXISTS (SELECT 1 FROM sites s WHERE s.device_id = d.id);

INSERT INTO members (package_id, device_id, joined_at)
  SELECT id, owner_id, created_at FROM packages;

INSERT INTO site_prefs (site_id, device_id, notify_down, notify_up)
  SELECT id, device_id, notify_down, notify_up FROM sites
  WHERE notify_down = 0 OR notify_up = 0;

-- Kontrol geçmişi pakete bağlanır.
CREATE TABLE runs_new (
  package_id TEXT NOT NULL,
  at_min INTEGER NOT NULL,
  data TEXT NOT NULL,
  PRIMARY KEY (package_id, at_min)
) WITHOUT ROWID;
INSERT OR REPLACE INTO runs_new (package_id, at_min, data)
  SELECT 'p-' || device_id, at_min, data FROM runs;
DROP TABLE runs;
ALTER TABLE runs_new RENAME TO runs;

INSERT INTO admin_log (at, kind, package_id, text)
  SELECT created_at, 'migrated', id, name FROM packages;
