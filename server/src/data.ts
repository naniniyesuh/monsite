// Veritabanı yardımcıları ve istemciye dönen JSON biçimleri.

import { nextRun } from "./schedule.ts";
import type { CheckJob, DeviceRow, Env, PackageRow, SiteRow } from "./types.ts";

export const RETENTION_DAYS = 8;

export const limits = (env: Env) => ({
  sitesPerPackage: Number(env.MAX_SITES_PER_PACKAGE ?? env.MAX_SITES_PER_DEVICE ?? 50),
  packagesPerDevice: Number(env.MAX_PACKAGES_PER_DEVICE ?? 5),
  members: Number(env.MAX_MEMBERS ?? 20),
  packages: Number(env.MAX_PACKAGES ?? 300),
});

export async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function getDevice(env: Env, id: string): Promise<DeviceRow | null> {
  return env.DB.prepare("SELECT * FROM devices WHERE id = ?").bind(id).first<DeviceRow>();
}

export function isAdmin(env: Env, deviceId: string): boolean {
  return (env.ADMIN_DEVICE_IDS ?? "").split(",").map((s) => s.trim()).filter(Boolean).includes(deviceId);
}

// ---------------------------------------------------------------- paketler

const KEY_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";

/** 12 karakterlik katılım anahtarı; uygulama XXXX-XXXX-XXXX olarak gösterir. */
export function newJoinKey(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return [...bytes].map((b) => KEY_ALPHABET[b % KEY_ALPHABET.length]).join("");
}

/** Kullanıcının yazdığı anahtarı karşılaştırılabilir hale getirir (tire, boşluk, küçük harf). */
export function normalizeKey(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const k = raw.toUpperCase().replace(/[^0-9A-Z]/g, "");
  return k.length >= 8 && k.length <= 32 ? k : null;
}

export async function packagesOf(env: Env, deviceId: string): Promise<PackageRow[]> {
  const r = await env.DB.prepare(
    "SELECT p.* FROM packages p JOIN members m ON m.package_id = p.id WHERE m.device_id = ? ORDER BY m.joined_at, p.created_at",
  ).bind(deviceId).all<PackageRow>();
  return r.results;
}

export async function memberPackage(env: Env, deviceId: string, packageId: string): Promise<PackageRow | null> {
  return env.DB.prepare(
    "SELECT p.* FROM packages p JOIN members m ON m.package_id = p.id WHERE m.device_id = ? AND p.id = ?",
  ).bind(deviceId, packageId).first<PackageRow>();
}

export async function memberCount(env: Env, packageId: string): Promise<number> {
  const r = await env.DB.prepare("SELECT COUNT(*) AS n FROM members WHERE package_id = ?").bind(packageId).first<{ n: number }>();
  return r?.n ?? 0;
}

export async function createPackage(env: Env, deviceId: string, name: string, nowMs: number, from?: { retries: number; timeout_s: number }): Promise<PackageRow> {
  const pkg: PackageRow = {
    id: crypto.randomUUID(), name, join_key: newJoinKey(), owner_id: deviceId,
    retries: from?.retries ?? 2, timeout_s: from?.timeout_s ?? 15, created_at: nowMs,
  };
  await env.DB.batch([
    env.DB.prepare("INSERT INTO packages (id, name, join_key, owner_id, retries, timeout_s, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)")
      .bind(pkg.id, pkg.name, pkg.join_key, pkg.owner_id, pkg.retries, pkg.timeout_s, nowMs),
    env.DB.prepare("INSERT INTO members (package_id, device_id, joined_at) VALUES (?, ?, ?)").bind(pkg.id, deviceId, nowMs),
    adminLog(env, nowMs, "created", pkg.id, name),
  ]);
  return pkg;
}

export function adminLog(env: Env, at: number, kind: string, packageId: string | null, text: string) {
  return env.DB.prepare("INSERT INTO admin_log (at, kind, package_id, text) VALUES (?, ?, ?, ?)").bind(at, kind, packageId, text.slice(0, 200));
}

/** Paketi ve ona ait her şeyi siler. */
export function deletePackageStatements(env: Env, packageId: string) {
  return [
    env.DB.prepare("DELETE FROM site_prefs WHERE site_id IN (SELECT id FROM sites WHERE package_id = ?)").bind(packageId),
    env.DB.prepare("DELETE FROM events WHERE site_id IN (SELECT id FROM sites WHERE package_id = ?)").bind(packageId),
    env.DB.prepare("DELETE FROM sites WHERE package_id = ?").bind(packageId),
    env.DB.prepare("DELETE FROM runs WHERE package_id = ?").bind(packageId),
    env.DB.prepare("DELETE FROM members WHERE package_id = ?").bind(packageId),
    env.DB.prepare("DELETE FROM packages WHERE id = ?").bind(packageId),
  ];
}

/**
 * Üyeyi paketten çıkarır. Son üyeyse paket silinir; sahibi ayrılırsa sahiplik en eski üyeye geçer.
 * Döndürülen ifadeler tek batch'te çalıştırılmalı.
 */
export async function leaveStatements(env: Env, pkg: PackageRow, deviceId: string, nowMs: number) {
  const others = (await env.DB.prepare("SELECT device_id FROM members WHERE package_id = ? AND device_id != ? ORDER BY joined_at")
    .bind(pkg.id, deviceId).all<{ device_id: string }>()).results;
  if (others.length === 0) return [...deletePackageStatements(env, pkg.id), adminLog(env, nowMs, "deleted", pkg.id, pkg.name)];
  const st = [
    env.DB.prepare("DELETE FROM members WHERE package_id = ? AND device_id = ?").bind(pkg.id, deviceId),
    env.DB.prepare("DELETE FROM site_prefs WHERE device_id = ? AND site_id IN (SELECT id FROM sites WHERE package_id = ?)").bind(deviceId, pkg.id),
  ];
  if (pkg.owner_id === deviceId) st.push(env.DB.prepare("UPDATE packages SET owner_id = ? WHERE id = ?").bind(others[0].device_id, pkg.id));
  return st;
}

// ---------------------------------------------------------------- kontroller

const chunks = <T>(arr: T[], n: number) => Array.from({ length: Math.ceil(arr.length / n) }, (_, i) => arr.slice(i * n, i * n + n));

export async function jobsFor(env: Env, siteIds?: string[]): Promise<CheckJob[]> {
  let sites: SiteRow[];
  if (siteIds) {
    if (siteIds.length === 0) return [];
    sites = (await env.DB.prepare(`SELECT * FROM sites WHERE paused = 0 AND package_id IS NOT NULL AND id IN (${siteIds.map(() => "?").join(",")})`)
      .bind(...siteIds).all<SiteRow>()).results;
  } else {
    sites = (await env.DB.prepare("SELECT * FROM sites WHERE paused = 0 AND package_id IS NOT NULL").all<SiteRow>()).results;
  }
  if (sites.length === 0) return [];
  const ids = [...new Set(sites.map((s) => s.package_id))];
  const pkgs = new Map<string, PackageRow & { members: number }>();
  for (const chunk of chunks(ids, 90)) {
    const rows = (await env.DB.prepare(
      `SELECT p.*, (SELECT COUNT(*) FROM members m WHERE m.package_id = p.id) AS members FROM packages p WHERE p.id IN (${chunk.map(() => "?").join(",")})`,
    ).bind(...chunk).all<PackageRow & { members: number }>()).results;
    for (const p of rows) pkgs.set(p.id, p);
  }
  return sites.filter((s) => pkgs.has(s.package_id)).map((s) => {
    const p = pkgs.get(s.package_id) as PackageRow & { members: number };
    return { site: s, pkg: p, members: p.members };
  });
}

export interface Recipient extends DeviceRow { site_id: string; nd: number; nu: number }

/** Durumu değişen siteler için bildirim alacak üyeler (tercihleriyle). */
export async function recipientsFor(env: Env, sites: SiteRow[]): Promise<Recipient[]> {
  if (sites.length === 0) return [];
  const out: Recipient[] = [];
  for (const chunk of chunks(sites, 40)) {
    const r = await env.DB.prepare(
      `SELECT d.*, s.id AS site_id, COALESCE(sp.notify_down, 1) AS nd, COALESCE(sp.notify_up, 1) AS nu
       FROM sites s
       JOIN members m ON m.package_id = s.package_id
       JOIN devices d ON d.id = m.device_id
       LEFT JOIN site_prefs sp ON sp.site_id = s.id AND sp.device_id = d.id
       WHERE s.id IN (${chunk.map(() => "?").join(",")})`,
    ).bind(...chunk.map((s) => s.id)).all<Recipient>();
    out.push(...r.results);
  }
  return out;
}

interface RunRow { package_id: string; at_min: number; data: string }

export async function runsOf(env: Env, packageIds: string[], sinceMin: number): Promise<{ pkg: string; at: number; data: Record<string, number> }[]> {
  if (packageIds.length === 0) return [];
  const r = await env.DB.prepare(
    `SELECT package_id, at_min, data FROM runs WHERE package_id IN (${packageIds.map(() => "?").join(",")}) AND at_min >= ? ORDER BY at_min DESC`,
  ).bind(...packageIds, sinceMin).all<RunRow>();
  return r.results.map((row) => {
    let data: Record<string, number> = {};
    try { data = JSON.parse(row.data); } catch { /* bozuk satırı atla */ }
    return { pkg: row.package_id, at: row.at_min, data };
  });
}

export interface Prefs { nd: number; nu: number }

export function siteJson(s: SiteRow, nowMs: number, recent: [number, number][], prefs?: Prefs) {
  return {
    id: s.id,
    packageId: s.package_id,
    url: s.url,
    name: s.name,
    intervalMin: s.interval_min,
    notifyDown: (prefs?.nd ?? 1) === 1,
    notifyUp: (prefs?.nu ?? 1) === 1,
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

/** Tek bir sitenin bu cihaza göre JSON'u (son sonuçlarıyla). */
export async function siteState(env: Env, deviceId: string, site: SiteRow, nowMs: number) {
  const runs = await runsOf(env, [site.package_id], Math.floor(nowMs / 60_000) - 25 * 60);
  const recent = runs.filter((r) => site.id in r.data).map((r) => [r.at, r.data[site.id]] as [number, number]);
  const p = await env.DB.prepare("SELECT notify_down AS nd, notify_up AS nu FROM site_prefs WHERE site_id = ? AND device_id = ?")
    .bind(site.id, deviceId).first<Prefs>();
  return siteJson(site, nowMs, recent, p ?? undefined);
}

/** Cihazın üye olduğu paketler ve siteleri, son sonuçlarıyla. */
export async function stateOf(env: Env, deviceId: string, nowMs: number) {
  const pkgs = await packagesOf(env, deviceId);
  const ids = pkgs.map((p) => p.id);
  const sites = ids.length
    ? (await env.DB.prepare(`SELECT * FROM sites WHERE package_id IN (${ids.map(() => "?").join(",")}) ORDER BY created_at`).bind(...ids).all<SiteRow>()).results
    : [];
  const counts = ids.length
    ? (await env.DB.prepare(`SELECT package_id, COUNT(*) AS n FROM members WHERE package_id IN (${ids.map(() => "?").join(",")}) GROUP BY package_id`).bind(...ids).all<{ package_id: string; n: number }>()).results
    : [];
  const prefs = (await env.DB.prepare("SELECT site_id, notify_down AS nd, notify_up AS nu FROM site_prefs WHERE device_id = ?")
    .bind(deviceId).all<Prefs & { site_id: string }>()).results;
  const prefBy = new Map(prefs.map((p) => [p.site_id, p]));

  // Son 24 sonuç için 25 saat yeter (en uzun aralık 1 saat).
  const runs = await runsOf(env, ids, Math.floor(nowMs / 60_000) - 25 * 60);
  const bySite = new Map<string, [number, number][]>();
  for (const run of runs) {
    for (const [id, code] of Object.entries(run.data)) {
      const list = bySite.get(id) ?? [];
      list.push([run.at, code]);
      bySite.set(id, list);
    }
  }
  const json = sites.map((s) => siteJson(s, nowMs, bySite.get(s.id) ?? [], prefBy.get(s.id)));

  const lastCron = await env.DB.prepare("SELECT value FROM meta WHERE key = 'last_cron'").first<{ value: string }>();
  const push = await env.DB.prepare("SELECT push_at, push_result FROM devices WHERE id = ?")
    .bind(deviceId).first<{ push_at: number | null; push_result: string | null }>();
  const countBy = new Map(counts.map((c) => [c.package_id, c.n]));
  return {
    serverTime: nowMs,
    lastCronAt: lastCron ? Number(lastCron.value) : null,
    lastPush: push?.push_at ? { at: push.push_at, result: push.push_result ?? "" } : null,
    minBuild: Number(env.MIN_APP_BUILD ?? 0) || 0,
    isAdmin: isAdmin(env, deviceId),
    packages: pkgs.map((p) => ({
      id: p.id,
      name: p.name,
      key: p.join_key,
      isOwner: p.owner_id === deviceId,
      members: countBy.get(p.id) ?? 1,
      retries: p.retries,
      timeoutS: p.timeout_s,
      createdAt: p.created_at,
    })),
    // 2.0.x sürümleri için düz liste; 2.1 siteleri packageId ile gruplar.
    sites: json,
  };
}

/** Yönetici ekranı: tüm paketler, siteleri ve haber akışı. */
export async function adminState(env: Env) {
  const pkgs = (await env.DB.prepare(
    "SELECT p.id, p.name, p.created_at, (SELECT COUNT(*) FROM members m WHERE m.package_id = p.id) AS members FROM packages p ORDER BY p.created_at DESC",
  ).all<{ id: string; name: string; created_at: number; members: number }>()).results;
  const sites = (await env.DB.prepare("SELECT package_id, url, interval_min, paused, status FROM sites ORDER BY created_at")
    .all<{ package_id: string; url: string; interval_min: number; paused: number; status: string }>()).results;
  const log = (await env.DB.prepare("SELECT at, kind, package_id, text FROM admin_log ORDER BY at DESC, id DESC LIMIT 200")
    .all<{ at: number; kind: string; package_id: string | null; text: string }>()).results;
  const devices = await env.DB.prepare("SELECT COUNT(*) AS n FROM devices").first<{ n: number }>();
  const bySite = new Map<string, typeof sites>();
  for (const s of sites) bySite.set(s.package_id, [...(bySite.get(s.package_id) ?? []), s]);
  return {
    totals: { packages: pkgs.length, sites: sites.length, devices: devices?.n ?? 0 },
    limits: limits(env),
    packages: pkgs.map((p) => ({
      id: p.id, name: p.name, createdAt: p.created_at, members: p.members,
      sites: (bySite.get(p.id) ?? []).map((s) => ({ url: s.url, intervalMin: s.interval_min, paused: s.paused === 1, status: s.status })),
    })),
    log: log.map((l) => ({ at: l.at, kind: l.kind, packageId: l.package_id, text: l.text })),
  };
}
