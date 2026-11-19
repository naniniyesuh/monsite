// Bildirim metinleri (Türkçe / İngilizce) ve sessiz saat hesabı.

export type Lang = "tr" | "en";

export function langOf(s: string | null | undefined): Lang {
  return s === "en" ? "en" : "tr";
}

/** Cihazın saat diliminde "HH:mm" */
export function localTime(ms: number, tz: string): string {
  try {
    return new Intl.DateTimeFormat("en-GB", { timeZone: tz, hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(ms));
  } catch {
    return new Intl.DateTimeFormat("en-GB", { timeZone: "UTC", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(ms));
  }
}

function minutesOfDay(hhmm: string): number | null {
  const m = /^(\d{1,2}):(\d{2})$/.exec(hhmm);
  if (!m) return null;
  const h = Number(m[1]), mi = Number(m[2]);
  if (h > 23 || mi > 59) return null;
  return h * 60 + mi;
}

/** Sessiz saat aralığında mı? Gece yarısını aşan aralıkları da destekler (23:00–07:00). */
export function inQuietHours(ms: number, tz: string, start: string | null, end: string | null): boolean {
  if (!start || !end) return false;
  const s = minutesOfDay(start), e = minutesOfDay(end);
  if (s === null || e === null || s === e) return false;
  const now = minutesOfDay(localTime(ms, tz));
  if (now === null) return false;
  return s < e ? now >= s && now < e : now >= s || now < e;
}

export function formatDuration(ms: number, lang: Lang): string {
  const totalMin = Math.max(1, Math.round(ms / 60_000));
  const d = Math.floor(totalMin / 1440);
  const h = Math.floor((totalMin % 1440) / 60);
  const m = totalMin % 60;
  const parts: string[] = [];
  if (lang === "tr") {
    if (d) parts.push(`${d} gün`);
    if (h) parts.push(`${h} saat`);
    if (m && !d) parts.push(`${m} dakika`);
  } else {
    if (d) parts.push(`${d} ${d === 1 ? "day" : "days"}`);
    if (h) parts.push(`${h} ${h === 1 ? "hour" : "hours"}`);
    if (m && !d) parts.push(`${m} ${m === 1 ? "minute" : "minutes"}`);
  }
  return parts.join(" ");
}

function reason(code: number | null, error: string | null, lang: Lang): string {
  if (code !== null) return `HTTP ${code}`;
  const tr: Record<string, string> = { timeout: "Zaman aşımı", dns: "Alan adı çözümlenemedi", tls: "Güvenli bağlantı kurulamadı", connect: "Bağlantı kurulamadı" };
  const en: Record<string, string> = { timeout: "Timed out", dns: "Domain could not be resolved", tls: "Secure connection failed", connect: "Could not connect" };
  const map = lang === "tr" ? tr : en;
  return map[error ?? "connect"] ?? map.connect;
}

export function downMessage(name: string, code: number | null, error: string | null, attempts: number, atMs: number, tz: string, lang: Lang) {
  const t = localTime(atMs, tz);
  const r = reason(code, error, lang);
  if (lang === "tr") {
    return { title: `${name} erişilemiyor`, body: `${r} · ${t} kontrolünde${attempts > 1 ? `, ${attempts} denemede yanıt alınamadı` : ""}.` };
  }
  return { title: `${name} is down`, body: `${r} · ${t} check${attempts > 1 ? `, no response after ${attempts} attempts` : ""}.` };
}

export function upMessage(name: string, downSinceMs: number | null, atMs: number, lang: Lang) {
  const dur = downSinceMs ? formatDuration(atMs - downSinceMs, lang) : null;
  if (lang === "tr") {
    return { title: `${name} tekrar erişilebilir`, body: dur ? `Kesinti ${dur} sürdü.` : "Site yeniden yanıt veriyor." };
  }
  return { title: `${name} is back up`, body: dur ? `Downtime lasted ${dur}.` : "The site is responding again." };
}

export function testMessage(lang: Lang) {
  return lang === "tr"
    ? { title: "UpSite test bildirimi", body: "Bildirimler çalışıyor. Bir siteniz erişilemez olursa böyle haber vereceğiz." }
    : { title: "UpSite test notification", body: "Notifications are working. This is how we'll tell you when a site goes down." };
}
