// Kontrol zamanlaması: tüm kontroller saat başına hizalıdır.
//
// - 15 / 30 / 60 dakikalık aralıklar doğrudan saate göre çalışır: 15 dk → :00 :15 :30 :45.
// - 6 / 12 / 24 saatlik aralıklar, site eklendikten sonraki ilk tam saatten başlar ve
//   oradan aralık kadar ilerler (ör. 14:07'de eklenen günlük kontrol her gün 15:00'te).
//
// Zaman "dakika" cinsinden tutulur: Unix zamanı / 60_000.

export const INTERVALS = [15, 30, 60, 360, 720, 1440] as const;
export const TICK_MIN = 15;

export function isValidInterval(n: unknown): n is number {
  return typeof n === "number" && (INTERVALS as readonly number[]).includes(n);
}

export function toMin(ms: number): number {
  return Math.floor(ms / 60_000);
}

/** Cron zamanını 15 dakikalık tura yuvarlar (cron birkaç saniye geç tetiklenebilir). */
export function tickOf(ms: number): number {
  const m = toMin(ms + 30_000);
  return m - (m % TICK_MIN);
}

/** Site eklendiğinde ilk hizalı kontrol dakikası. */
export function anchorFor(intervalMin: number, createdMs: number): number {
  const step = Math.min(intervalMin, 60);
  const m = toMin(createdMs);
  return m - (m % step) + step;
}

export function isDue(intervalMin: number, anchorMin: number, tickMin: number): boolean {
  if (tickMin < anchorMin) return false;
  return (tickMin - anchorMin) % intervalMin === 0;
}

/** Verilen andan sonraki ilk planlı kontrol (dakika). */
export function nextRun(intervalMin: number, anchorMin: number, nowMs: number): number {
  const now = toMin(nowMs);
  if (now < anchorMin) return anchorMin;
  const k = Math.floor((now - anchorMin) / intervalMin) + 1;
  return anchorMin + k * intervalMin;
}
