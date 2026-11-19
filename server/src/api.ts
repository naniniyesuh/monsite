// İstemci (iOS uygulaması) için HTTP API.

import { anchorFor, isValidInterval, toMin } from "./schedule.ts";
import { getDevice, jobsFor, RETENTION_DAYS, runsOf, sha256Hex, sitesOf, siteJson, stateOf } from "./data.ts";
import { pushConfig, runJobs, type RunOptions } from "./monitor.ts";
import { sendPush } from "./apns.ts";
import { langOf, testMessage } from "./messages.ts";
import type { Ctx, DeviceRow, Env, SiteRow } from "./types.ts";

const json = (data: unknown, status = 200) => Response.json(data, { status });
const error = (status: number, code: string) => json({ error: code }, status);

const ID_RE = /^[A-Za-z0-9-]{8,64}$/;

export function normalizeUrl(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  let s = raw.trim();
  if (!s || s.length > 2048) return null;
  if (!/^https?:\/\//i.test(s)) s = "https://" + s;
  let u: URL;
  try { u = new URL(s); } catch { return null; }
  if (u.protocol !== "http:" && u.protocol !== "https:") return null;
  if (u.username || u.password) return null;
  const host = u.hostname.toLowerCase();
  if (!host.includes(".") || host.endsWith(".local") || host.endsWith(".internal") || host === "localhost") return null;
  if (/^\d+\.\d+\.\d+\.\d+$/.test(host) || host.startsWith("[")) return null;
  u.hash = "";
  return u.toString();
}

export function defaultName(url: string): string {
  const u = new URL(url);
  const path = u.pathname === "/" ? "" : u.pathname.replace(/\/$/, "");
  return (u.hostname.replace(/^www\./, "") + path).slice(0, 80);
}

function cleanName(raw: unknown, url: string): string {
  if (typeof raw === "string" && raw.trim()) return raw.trim().slice(0, 80);
  return defaultName(url);
}

async function authed(env: Env, req: Request): Promise<DeviceRow | null> {
  const h = req.headers.get("authorization") ?? "";
  const m = /^Bearer ([A-Za-z0-9-]+)\.([A-Za-z0-9_-]{20,})$/.exec(h);
  if (!m) return null;
  const device = await getDevice(env, m[1]);
  if (!device) return null;
  if (device.secret_hash !== (await sha256Hex(m[2]))) return null;
  return device;
}

async function body(req: Request): Promise<Record<string, unknown>> {
  try {
    const b = await req.json();
    return b && typeof b === "object" ? (b as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

const bool = (v: unknown) => (v ? 1 : 0);
const hhmm = (v: unknown) => (typeof v === "string" && /^\d{1,2}:\d{2}$/.test(v) ? v : null);

export async function handle(env: Env, req: Request, ctx: Ctx, opts: RunOptions = {}): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const now = opts.nowMs ?? Date.now();
  const method = req.method;

  if (path === "/" || path === "/v1/health") {
    const last = await env.DB.prepare("SELECT value FROM meta WHERE key = 'last_cron'").first<{ value: string }>();
    return json({ ok: true, service: "upsite", lastCronAt: last ? Number(last.value) : null });
  }

  if (path === "/v1/register" && method === "POST") {
    const b = await body(req);
    const id = typeof b.deviceId === "string" ? b.deviceId : "";
    const secret = typeof b.secret === "string" ? b.secret : "";
    if (!ID_RE.test(id) || !/^[A-Za-z0-9_-]{20,128}$/.test(secret)) return error(400, "invalid");
    const hash = await sha256Hex(secret);
    const existing = await getDevice(env, id);
    if (existing) return existing.secret_hash === hash ? json({ ok: true }) : error(409, "conflict");
    const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM devices").first<{ n: number }>();
    if ((count?.n ?? 0) >= Number(env.MAX_DEVICES ?? 500)) return error(503, "capacity");
    await env.DB.prepare("INSERT INTO devices (id, secret_hash, created_at, last_seen) VALUES (?, ?, ?, ?)")
      .bind(id, hash, now, now).run();
    return json({ ok: true }, 201);
  }

  const device = await authed(env, req);
  if (!device) return error(401, "unauthorized");

  if (path === "/v1/state" && method === "GET") {
    await env.DB.prepare("UPDATE devices SET last_seen = ? WHERE id = ?").bind(now, device.id).run();
    return json(await stateOf(env, device.id, now));
  }

  if (path === "/v1/device" && method === "PUT") {
    const b = await body(req);
    const next = { ...device };
    if ("apnsToken" in b) next.apns_token = typeof b.apnsToken === "string" && /^[0-9a-fA-F]{32,200}$/.test(b.apnsToken) ? b.apnsToken : null;
    if (b.apnsEnv === "sandbox" || b.apnsEnv === "production") next.apns_env = b.apnsEnv;
    if (b.lang === "tr" || b.lang === "en") next.lang = b.lang;
    if (typeof b.tz === "string" && b.tz.length < 64) next.tz = b.tz;
    if (typeof b.retries === "number") next.retries = Math.max(0, Math.min(3, Math.round(b.retries)));
    if (typeof b.timeoutS === "number") next.timeout_s = Math.max(5, Math.min(30, Math.round(b.timeoutS)));
    if ("quietStart" in b) next.quiet_start = hhmm(b.quietStart);
    if ("quietEnd" in b) next.quiet_end = hhmm(b.quietEnd);
    await env.DB.prepare("UPDATE devices SET apns_token = ?, apns_env = ?, lang = ?, tz = ?, retries = ?, timeout_s = ?, quiet_start = ?, quiet_end = ?, last_seen = ? WHERE id = ?")
      .bind(next.apns_token, next.apns_env, next.lang, next.tz, next.retries, next.timeout_s, next.quiet_start, next.quiet_end, now, device.id).run();
    return json({ ok: true });
  }

  if (path === "/v1/device" && method === "DELETE") {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM runs WHERE device_id = ?").bind(device.id),
      env.DB.prepare("DELETE FROM events WHERE device_id = ?").bind(device.id),
      env.DB.prepare("DELETE FROM sites WHERE device_id = ?").bind(device.id),
      env.DB.prepare("DELETE FROM devices WHERE id = ?").bind(device.id),
    ]);
    return json({ ok: true });
  }

  if (path === "/v1/history" && method === "DELETE") {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM runs WHERE device_id = ?").bind(device.id),
      env.DB.prepare("DELETE FROM events WHERE device_id = ?").bind(device.id),
    ]);
    return json({ ok: true });
  }

  if (path === "/v1/push/test" && method === "POST") {
    const cfg = pushConfig(env);
    if (!cfg) return error(503, "push-not-configured");
    if (!device.apns_token) return error(409, "no-token");
    const res = await sendPush(cfg, device.apns_token, device.apns_env, { ...testMessage(langOf(device.lang)), quiet: false },
      Math.floor(now / 1000), opts.fetchFn);
    if (res.outcome === "invalid-token") {
      await env.DB.prepare("UPDATE devices SET apns_token = NULL WHERE id = ?").bind(device.id).run();
    }
    return json({ outcome: res.outcome, status: res.status, reason: res.reason ?? null }, res.outcome === "sent" ? 200 : 502);
  }

  if (path === "/v1/sites" && method === "POST") {
    const b = await body(req);
    const siteUrl = normalizeUrl(b.url);
    if (!siteUrl) return error(400, "invalid-url");
    const interval = isValidInterval(b.intervalMin) ? b.intervalMin : 15;
    const existing = await sitesOf(env, device.id);
    if (existing.length >= Number(env.MAX_SITES_PER_DEVICE ?? 50)) return error(403, "site-limit");
    if (existing.some((s) => s.url === siteUrl)) return error(409, "duplicate");
    const site: SiteRow = {
      id: crypto.randomUUID(), device_id: device.id, url: siteUrl, name: cleanName(b.name, siteUrl),
      interval_min: interval, anchor_min: anchorFor(interval, now),
      notify_down: "notifyDown" in b ? bool(b.notifyDown) : 1, notify_up: "notifyUp" in b ? bool(b.notifyUp) : 1,
      paused: 0, status: "unknown", status_since: null, last_code: null, last_error: null, created_at: now,
    };
    await env.DB.prepare("INSERT INTO sites (id, device_id, url, name, interval_min, anchor_min, notify_down, notify_up, paused, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 'unknown', ?)")
      .bind(site.id, device.id, site.url, site.name, site.interval_min, site.anchor_min, site.notify_down, site.notify_up, now).run();
    // İlk kontrol hemen (yanıtı bekletmeden).
    ctx.waitUntil(runJobs(env, [{ site, device }], toMin(now), opts).catch(() => undefined));
    return json(siteJson(site, now, []), 201);
  }

  const m = /^\/v1\/sites\/([A-Za-z0-9-]{8,64})(\/history|\/check)?$/.exec(path);
  if (m) {
    const site = await env.DB.prepare("SELECT * FROM sites WHERE id = ? AND device_id = ?").bind(m[1], device.id).first<SiteRow>();
    if (!site) return error(404, "not-found");
    const sub = m[2];

    if (!sub && method === "PATCH") {
      const b = await body(req);
      const next = { ...site };
      if (typeof b.name === "string") next.name = cleanName(b.name, site.url);
      if (isValidInterval(b.intervalMin) && b.intervalMin !== site.interval_min) {
        next.interval_min = b.intervalMin;
        next.anchor_min = anchorFor(b.intervalMin, now);
      }
      if ("notifyDown" in b) next.notify_down = bool(b.notifyDown);
      if ("notifyUp" in b) next.notify_up = bool(b.notifyUp);
      if ("paused" in b) {
        next.paused = bool(b.paused);
        if (next.paused === 0 && site.paused === 1) {
          next.anchor_min = anchorFor(next.interval_min, now);
          next.status = "unknown";
          next.status_since = null;
        }
      }
      await env.DB.prepare("UPDATE sites SET name = ?, interval_min = ?, anchor_min = ?, notify_down = ?, notify_up = ?, paused = ?, status = ?, status_since = ? WHERE id = ?")
        .bind(next.name, next.interval_min, next.anchor_min, next.notify_down, next.notify_up, next.paused, next.status, next.status_since, site.id).run();
      return json(siteJson(next, now, []));
    }

    if (!sub && method === "DELETE") {
      await env.DB.batch([
        env.DB.prepare("DELETE FROM events WHERE site_id = ?").bind(site.id),
        env.DB.prepare("DELETE FROM sites WHERE id = ?").bind(site.id),
      ]);
      return json({ ok: true });
    }

    if (sub === "/check" && method === "POST") {
      const jobs = await jobsFor(env, [site.id]);
      const job = jobs[0] ?? { site, device };
      await runJobs(env, [job], toMin(now), opts);
      const state = await stateOf(env, device.id, now);
      return json(state.sites.find((s) => s.id === site.id) ?? null);
    }

    if (sub === "/history" && method === "GET") {
      const days = Math.max(1, Math.min(RETENTION_DAYS, Number(url.searchParams.get("days") ?? 7) || 7));
      const runs = await runsOf(env, device.id, toMin(now) - days * 1440);
      const checks = runs.filter((r) => site.id in r.data).map((r) => [r.at * 60_000, r.data[site.id]]);
      const events = (await env.DB.prepare("SELECT at, kind, code, error FROM events WHERE site_id = ? ORDER BY at DESC LIMIT 30")
        .bind(site.id).all()).results;
      return json({ checks, events });
    }
  }

  return error(404, "not-found");
}
