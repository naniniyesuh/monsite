-- UpSite 2.0.1: dakikalık kontroller ve bildirim sonucu kaydı

-- Son bildirim denemesinin zamanı ve sonucu ("sent" ya da "<durum> <neden>"); Ayarlar → Sunucu durumu'nda görünür.
ALTER TABLE devices ADD COLUMN push_at INTEGER;
ALTER TABLE devices ADD COLUMN push_result TEXT;

-- 6/12/24 saatlik aralıklar kaldırıldı; en uzun aralık 1 saat.
UPDATE sites SET interval_min = 60 WHERE interval_min > 60;

-- Kontrol turları artık her dakika yazılabildiği için runs tablosu ayrı indeks olmadan
-- (cihaz, dakika) birincil anahtarıyla tutuluyor: satır başına tek yazma.
CREATE TABLE runs_new (
  device_id TEXT NOT NULL,
  at_min INTEGER NOT NULL,
  data TEXT NOT NULL,
  PRIMARY KEY (device_id, at_min)
) WITHOUT ROWID;
INSERT OR REPLACE INTO runs_new (device_id, at_min, data) SELECT device_id, at_min, data FROM runs;
DROP TABLE runs;
ALTER TABLE runs_new RENAME TO runs;
