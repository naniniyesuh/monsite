// Kontrol zamanlaması: tüm kontroller saat başına hizalıdır.
//
// Aralık 1–60 dakika arasıdır. Kontroller her saatin başından itibaren aralığın katlarında
// yapılır: 15 dk → :00 :15 :30 :45, 4 dk → :00 :04 … :56. 60'ı tam bölmeyen aralıklarda
// (ör. 7 dk → :00 :07 … :56) sayım her saat başında yeniden :00'dan başlar.
// Sunucu her dakika çalışır ve o dakikada sırası gelen siteleri kontrol eder.
//
// Zaman "dakika" cinsinden tutulur: Unix zamanı / 60_000.

export const PRESETS = [1, 5, 10, 15, 30, 60] as const;
export const MIN_INTERVAL = 1;
export const MAX_INTERVAL = 60;

/**
 * İstemciden gelen aralığı doğrular. 2.0 sürümünün gönderebildiği 6/12/24 saatlik
 * değerler 60 dakikaya indirilir. Geçersizse null.
 */
export function normalizeInterval(n: unknown): number | null {
  if (typeof n !== "number" || !Number.isInteger(n) || n < MIN_INTERVAL || n > 1440) return null;
  return Math.min(n, MAX_INTERVAL);
}

export function toMin(ms: number): number {
  return Math.floor(ms / 60_000);
}

/** Cron zamanını dakikaya yuvarlar (cron birkaç saniye geç ya da erken tetiklenebilir). */
export function tickOf(ms: number): number {
  return toMin(ms + 30_000);
}

/** Site eklendiğinde ya da aralığı değiştiğinde planlı kontrollerin başlayacağı dakika. */
export function anchorFor(_intervalMin: number, createdMs: number): number {
  return toMin(createdMs) + 1;
}

export function isDue(intervalMin: number, anchorMin: number, tickMin: number): boolean {
  if (tickMin < anchorMin) return false;
  const step = Math.min(Math.max(intervalMin, 1), MAX_INTERVAL);
  return (tickMin % 60) % step === 0;
}

/** Verilen andan sonraki ilk planlı kontrol (dakika). */
export function nextRun(intervalMin: number, anchorMin: number, nowMs: number): number {
  let t = Math.max(toMin(nowMs) + 1, anchorMin);
  for (let i = 0; i < 61; i++, t++) if (isDue(intervalMin, anchorMin, t)) return t;
  return t;
}
