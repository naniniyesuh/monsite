// Veritabanı yardımcıları ve istemciye dönen JSON biçimleri.

import { nextRun } from "./schedule.ts";
import type { CheckJob, DeviceRow, Env, SiteRow } from "./types.ts";

export const RETENTION_DAYS = 8;

export async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function getDevice(env: Env, id: string): Promise<DeviceRow | null> {
  return env.DB.prepare("SELECT * FROM devices WHERE id = ?").bind(id).first<DeviceRow>();
}

export async function sitesOf(env: Env, deviceId: string): Promise<SiteRow[]> {
  const r = await env.DB.prepare("SELECT * FROM sites WHERE device_id = ? ORDER BY created_at").bind(deviceId).all<SiteRow>();
  return r.results;
}

export async function jobsFor(env: Env, siteIds?: string[]): Promise<CheckJob[]> {
  let sites: SiteRow[];
  if (siteIds) {
    if (siteIds.length === 0) return [];
    const marks = siteIds.map(() => "?").join(",");
    sites = (await env.DB.prepare(`SELECT * FROM sites WHERE paused = 0 AND id IN (${marks})`).bind(...siteIds).all<SiteRow>()).results;
  } else {
    sites = (await env.DB.prepare("SELECT * FROM sites WHERE paused = 0").all<SiteRow>()).results;
  }
  if (sites.length === 0) return [];
  const ids = [...new Set(sites.map((s) => s.device_id))];
  const devices = new Map<string, DeviceRow>();
  for (let i = 0; i < ids.length; i += 90) {
    const chunk = ids.slice(i, i + 90);
    const rows = (await env.DB.prepare(`SELECT * FROM devices WHERE id IN (${chunk.map(() => "?").join(",")})`).bind(...chunk).all<DeviceRow>()).results;
    for (const d of rows) devices.set(d.id, d);
  }
  return sites.filter((s) => devices.has(s.device_id)).map((s) => ({ site: s, device: devices.get(s.device_id) as DeviceRow }));
}

interface RunRow { at_min: number; data: string }

export async function runsOf(env: Env, deviceId: string, sinceMin: number): Promise<{ at: number; data: Record<string, number> }[]> {
  const r = await env.DB.prepare("SELECT at_min, data FROM runs WHERE device_id = ? AND at_min >= ? ORDER BY at_min DESC")
    .bind(deviceId, sinceMin).all<RunRow>();
  return r.results.map((row) => {
    let data: Record<string, number> = {};
    try { data = JSON.parse(row.data); } catch { /* bozuk satırı atla */ }
    return { at: row.at_min, data };
  });
}

export function siteJson(s: SiteRow, nowMs: number, recent: [number, number][]) {
  return {
    id: s.id,
    url: s.url,
    name: s.name,
    intervalMin: s.interval_min,
    notifyDown: s.notify_down === 1,
    notifyUp: s.notify_up === 1,
    paused: s.paused === 1,
    status: s.status,
    statusSince: s.status_since,
    lastCode: recent[0]?.[1] ?? s.last_code,
    lastError: s.status === "down" ? s.last_error : null,
    lastCheckAt: recent[0] ? recent[0][0] * 60_000 : null,
    nextCheckAt: s.paused ? null : nextRun(s.interval_min, s.anchor_min, nowMs) * 60_000,
    // En yeni başta, en fazla 24 sonuç: [zaman(ms), kod] (kod -1 = bağlantı yok)
    recent: recent.slice(0, 24).map(([at, code]) => [at * 60_000, code]),
    createdAt: s.created_at,
  };
}

/** Cihazın tüm siteleri, son sonuçlarıyla. */
export async function stateOf(env: Env, deviceId: string, nowMs: number) {
  const sites = await sitesOf(env, deviceId);
  // Son 24 sonuç için 25 saat yeter (en uzun aralık 1 saat).
  const runs = await runsOf(env, deviceId, Math.floor(nowMs / 60_000) - 25 * 60);
  const bySite = new Map<string, [number, number][]>();
  for (const run of runs) {
    for (const [id, code] of Object.entries(run.data)) {
      const list = bySite.get(id) ?? [];
      list.push([run.at, code]);
      bySite.set(id, list);
    }
  }
  const lastCron = await env.DB.prepare("SELECT value FROM meta WHERE key = 'last_cron'").first<{ value: string }>();
  return {
    serverTime: nowMs,
    lastCronAt: lastCron ? Number(lastCron.value) : null,
    sites: sites.map((s) => siteJson(s, nowMs, bySite.get(s.id) ?? [])),
  };
}
