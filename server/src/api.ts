// İstemci (iOS uygulaması) için HTTP API.

import { anchorFor, normalizeInterval, toMin } from "./schedule.ts";
import {
  adminLog, adminState, createPackage, deletePackageStatements, getDevice, isAdmin, jobsFor, leaveStatements, limits,
  memberCount, memberPackage, newJoinKey, normalizeKey, packagesOf, RETENTION_DAYS, runsOf, sha256Hex, siteState, stateOf,
} from "./data.ts";
import { pushConfig, runJobs, type RunOptions } from "./monitor.ts";
import { pushResultText, sendPushAnyEnv } from "./apns.ts";
import { langOf, testMessage } from "./messages.ts";
import type { Ctx, DeviceRow, Env, PackageRow, SiteRow } from "./types.ts";

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
const clampRetries = (v: number) => Math.max(0, Math.min(3, Math.round(v)));
const clampTimeout = (v: number) => Math.max(5, Math.min(30, Math.round(v)));

function packageName(raw: unknown, lang: string): string {
  if (typeof raw === "string" && raw.trim()) return raw.trim().slice(0, 60);
  return lang === "en" ? "My sites" : "Sitelerim";
}
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
  const lim = limits(env);

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
    if (typeof b.retries === "number") next.retries = clampRetries(b.retries);
    if (typeof b.timeoutS === "number") next.timeout_s = clampTimeout(b.timeoutS);
    if ("quietStart" in b) next.quiet_start = hhmm(b.quietStart);
    if ("quietEnd" in b) next.quiet_end = hhmm(b.quietEnd);
    const st = [env.DB.prepare("UPDATE devices SET apns_token = ?, apns_env = ?, lang = ?, tz = ?, retries = ?, timeout_s = ?, quiet_start = ?, quiet_end = ?, last_seen = ? WHERE id = ?")
      .bind(next.apns_token, next.apns_env, next.lang, next.tz, next.retries, next.timeout_s, next.quiet_start, next.quiet_end, now, device.id)];
    // 2.0.x: yanlış alarm ayarları cihazdaydı; yalnızca tek üyesi bu cihaz olan paketlere uygulanır.
    if (typeof b.retries === "number" || typeof b.timeoutS === "number") {
      st.push(env.DB.prepare(
        "UPDATE packages SET retries = ?, timeout_s = ? WHERE owner_id = ? AND (SELECT COUNT(*) FROM members m WHERE m.package_id = packages.id) = 1",
      ).bind(next.retries, next.timeout_s, device.id));
    }
    await env.DB.batch(st);
    return json({ ok: true });
  }

  if (path === "/v1/device" && method === "DELETE") {
    const st = [];
    for (const p of await packagesOf(env, device.id)) st.push(...(await leaveStatements(env, p, device.id, now)));
    st.push(env.DB.prepare("DELETE FROM site_prefs WHERE device_id = ?").bind(device.id));
    st.push(env.DB.prepare("DELETE FROM devices WHERE id = ?").bind(device.id));
    await env.DB.batch(st);
    return json({ ok: true });
  }

  if (path === "/v1/history" && method === "DELETE") {
    // Üyesi olunan tüm paketlerin geçmişi (paketin diğer üyeleri için de) silinir.
    const ids = (await packagesOf(env, device.id)).map((p) => p.id);
    if (ids.length) {
      const marks = ids.map(() => "?").join(",");
      await env.DB.batch([
        env.DB.prepare(`DELETE FROM runs WHERE package_id IN (${marks})`).bind(...ids),
        env.DB.prepare(`DELETE FROM events WHERE site_id IN (SELECT id FROM sites WHERE package_id IN (${marks}))`).bind(...ids),
      ]);
    }
    return json({ ok: true });
  }

  if (path === "/v1/push/test" && method === "POST") {
    const cfg = pushConfig(env);
    if (!cfg) return error(503, "push-not-configured");
    if (!device.apns_token) return error(409, "no-token");
    const res = await sendPushAnyEnv(cfg, device.apns_token, device.apns_env, { ...testMessage(langOf(device.lang)), quiet: false },
      Math.floor(now / 1000), opts.fetchFn);
    await env.DB.prepare("UPDATE devices SET push_at = ?, push_result = ?, apns_env = ? WHERE id = ?")
      .bind(now, pushResultText(res), res.env, device.id).run();
    if (res.outcome === "invalid-token" && res.reason !== "BadDeviceToken") {
      await env.DB.prepare("UPDATE devices SET apns_token = NULL WHERE id = ?").bind(device.id).run();
    }
    // Apple reddetse de 200 dönülür; uygulama nedeni ("BadDeviceToken" vb.) kullanıcıya gösterir.
    return json({ outcome: res.outcome, status: res.status, reason: res.reason ?? null });
  }

  if (path === "/v1/admin" && method === "GET") {
    if (!isAdmin(env, device.id)) return error(403, "forbidden");
    return json(await adminState(env));
  }

  // ---------------------------------------------------------------- paketler

  if (path === "/v1/packages" && method === "POST") {
    const b = await body(req);
    const mine = await packagesOf(env, device.id);
    if (mine.length >= lim.packagesPerDevice) return error(403, "package-limit");
    const total = await env.DB.prepare("SELECT COUNT(*) AS n FROM packages").first<{ n: number }>();
    if ((total?.n ?? 0) >= lim.packages) return error(503, "capacity");
    const pkg = await createPackage(env, device.id, packageName(b.name, device.lang), now);
    return json(packageJson(pkg, device.id, 1), 201);
  }

  if (path === "/v1/packages/join" && method === "POST") {
    const b = await body(req);
    const key = normalizeKey(b.key);
    if (!key) return error(404, "invalid-key");
    const pkg = await env.DB.prepare("SELECT * FROM packages WHERE join_key = ?").bind(key).first<PackageRow>();
    if (!pkg) return error(404, "invalid-key");
    if (await memberPackage(env, device.id, pkg.id)) return error(409, "already-member");
    const mine = await packagesOf(env, device.id);
    if (mine.length >= lim.packagesPerDevice) return error(403, "package-limit");
    const n = await memberCount(env, pkg.id);
    if (n >= lim.members) return error(403, "member-limit");
    await env.DB.batch([
      env.DB.prepare("INSERT INTO members (package_id, device_id, joined_at) VALUES (?, ?, ?)").bind(pkg.id, device.id, now),
      adminLog(env, now, "joined", pkg.id, pkg.name),
    ]);
    return json(packageJson(pkg, device.id, n + 1));
  }

  const pm = /^\/v1\/packages\/([A-Za-z0-9-]{8,64})(\/key|\/leave)?$/.exec(path);
  if (pm) {
    const pkg = await memberPackage(env, device.id, pm[1]);
    if (!pkg) return error(404, "not-found");
    const sub = pm[2];

    if (!sub && method === "PATCH") {
      const b = await body(req);
      const next = { ...pkg };
      if (typeof b.name === "string" && b.name.trim()) next.name = b.name.trim().slice(0, 60);
      if (typeof b.retries === "number") next.retries = clampRetries(b.retries);
      if (typeof b.timeoutS === "number") next.timeout_s = clampTimeout(b.timeoutS);
      await env.DB.prepare("UPDATE packages SET name = ?, retries = ?, timeout_s = ? WHERE id = ?")
        .bind(next.name, next.retries, next.timeout_s, pkg.id).run();
      return json(packageJson(next, device.id, await memberCount(env, pkg.id)));
    }

    if (sub === "/key" && method === "POST") {
      // Anahtarı yeniler: eski anahtarla artık katılınamaz, mevcut üyeler kalır.
      if (pkg.owner_id !== device.id) return error(403, "not-owner");
      const next = { ...pkg, join_key: newJoinKey() };
      await env.DB.prepare("UPDATE packages SET join_key = ? WHERE id = ?").bind(next.join_key, pkg.id).run();
      return json(packageJson(next, device.id, await memberCount(env, pkg.id)));
    }

    if (sub === "/leave" && method === "POST") {
      await env.DB.batch(await leaveStatements(env, pkg, device.id, now));
      return json({ ok: true });
    }

    if (!sub && method === "DELETE") {
      if (pkg.owner_id !== device.id) return error(403, "not-owner");
      await env.DB.batch([...deletePackageStatements(env, pkg.id), adminLog(env, now, "deleted", pkg.id, pkg.name)]);
      return json({ ok: true });
    }
  }

  // ---------------------------------------------------------------- siteler

  if (path === "/v1/sites" && method === "POST") {
    const b = await body(req);
    const siteUrl = normalizeUrl(b.url);
    if (!siteUrl) return error(400, "invalid-url");
    const interval = normalizeInterval(b.intervalMin) ?? 15;

    // Paket belirtilmediyse (2.0.x ya da ilk site): ilk paket, hiç yoksa kişisel paket oluşturulur.
    let pkg: PackageRow | null;
    if (typeof b.packageId === "string") {
      pkg = await memberPackage(env, device.id, b.packageId);
      if (!pkg) return error(404, "not-found");
    } else {
      pkg = (await packagesOf(env, device.id))[0] ?? null;
      if (!pkg) {
        const total = await env.DB.prepare("SELECT COUNT(*) AS n FROM packages").first<{ n: number }>();
        if ((total?.n ?? 0) >= lim.packages) return error(503, "capacity");
        pkg = await createPackage(env, device.id, packageName(null, device.lang), now, device);
      }
    }
    const existing = (await env.DB.prepare("SELECT url FROM sites WHERE package_id = ?").bind(pkg.id).all<{ url: string }>()).results;
    if (existing.length >= lim.sitesPerPackage) return error(403, "site-limit");
    if (existing.some((s) => s.url === siteUrl)) return error(409, "duplicate");
    const site: SiteRow = {
      id: crypto.randomUUID(), device_id: device.id, package_id: pkg.id, url: siteUrl, name: cleanName(b.name, siteUrl),
      interval_min: interval, anchor_min: anchorFor(interval, now), notify_down: 1, notify_up: 1,
      paused: 0, status: "unknown", status_since: null, last_code: null, last_error: null, created_at: now,
    };
    const nd = "notifyDown" in b ? bool(b.notifyDown) : 1;
    const nu = "notifyUp" in b ? bool(b.notifyUp) : 1;
    const st = [env.DB.prepare("INSERT INTO sites (id, device_id, package_id, url, name, interval_min, anchor_min, paused, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 'unknown', ?)")
      .bind(site.id, device.id, pkg.id, site.url, site.name, site.interval_min, site.anchor_min, now)];
    if (nd === 0 || nu === 0) {
      st.push(env.DB.prepare("INSERT INTO site_prefs (site_id, device_id, notify_down, notify_up) VALUES (?, ?, ?, ?)").bind(site.id, device.id, nd, nu));
    }
    await env.DB.batch(st);
    // İlk kontrol hemen (yanıtı bekletmeden).
    const members = await memberCount(env, pkg.id);
    ctx.waitUntil(runJobs(env, [{ site, pkg, members }], toMin(now), opts).catch(() => undefined));
    return json(await siteState(env, device.id, site, now), 201);
  }

  const m = /^\/v1\/sites\/([A-Za-z0-9-]{8,64})(\/history|\/check)?$/.exec(path);
  if (m) {
    const site = await env.DB.prepare(
      "SELECT s.* FROM sites s JOIN members mb ON mb.package_id = s.package_id WHERE s.id = ? AND mb.device_id = ?",
    ).bind(m[1], device.id).first<SiteRow>();
    if (!site) return error(404, "not-found");
    const sub = m[2];

    if (!sub && method === "PATCH") {
      const b = await body(req);
      const next = { ...site };
      if (typeof b.name === "string") next.name = cleanName(b.name, site.url);
      const iv = normalizeInterval(b.intervalMin);
      if (iv !== null && iv !== site.interval_min) {
        next.interval_min = iv;
        next.anchor_min = anchorFor(iv, now);
      }
      if ("paused" in b) {
        next.paused = bool(b.paused);
        if (next.paused === 0 && site.paused === 1) {
          next.anchor_min = anchorFor(next.interval_min, now);
          next.status = "unknown";
          next.status_since = null;
        }
      }
      const st = [env.DB.prepare("UPDATE sites SET name = ?, interval_min = ?, anchor_min = ?, paused = ?, status = ?, status_since = ? WHERE id = ?")
        .bind(next.name, next.interval_min, next.anchor_min, next.paused, next.status, next.status_since, site.id)];
      // Bildirim tercihleri kişiseldir.
      if ("notifyDown" in b || "notifyUp" in b) {
        const cur = await env.DB.prepare("SELECT notify_down AS nd, notify_up AS nu FROM site_prefs WHERE site_id = ? AND device_id = ?")
          .bind(site.id, device.id).first<{ nd: number; nu: number }>();
        const nd = "notifyDown" in b ? bool(b.notifyDown) : (cur?.nd ?? 1);
        const nu = "notifyUp" in b ? bool(b.notifyUp) : (cur?.nu ?? 1);
        st.push(env.DB.prepare(
          "INSERT INTO site_prefs (site_id, device_id, notify_down, notify_up) VALUES (?, ?, ?, ?) ON CONFLICT(site_id, device_id) DO UPDATE SET notify_down = excluded.notify_down, notify_up = excluded.notify_up",
        ).bind(site.id, device.id, nd, nu));
      }
      await env.DB.batch(st);
      return json(await siteState(env, device.id, next, now));
    }

    if (!sub && method === "DELETE") {
      await env.DB.batch([
        env.DB.prepare("DELETE FROM site_prefs WHERE site_id = ?").bind(site.id),
        env.DB.prepare("DELETE FROM events WHERE site_id = ?").bind(site.id),
        env.DB.prepare("DELETE FROM sites WHERE id = ?").bind(site.id),
      ]);
      return json({ ok: true });
    }

    if (sub === "/check" && method === "POST") {
      const jobs = await jobsFor(env, [site.id]);
      const pkg = await memberPackage(env, device.id, site.package_id) as PackageRow;
      const job = jobs[0] ?? { site, pkg, members: await memberCount(env, pkg.id) };
      await runJobs(env, [job], toMin(now), opts);
      const fresh = await env.DB.prepare("SELECT * FROM sites WHERE id = ?").bind(site.id).first<SiteRow>();
      return json(fresh ? await siteState(env, device.id, fresh, now) : null);
    }

    if (sub === "/history" && method === "GET") {
      const days = Math.max(1, Math.min(RETENTION_DAYS, Number(url.searchParams.get("days") ?? 7) || 7));
      const runs = await runsOf(env, [site.package_id], toMin(now) - days * 1440);
      const checks = runs.filter((r) => site.id in r.data).map((r) => [r.at * 60_000, r.data[site.id]]);
      const events = (await env.DB.prepare("SELECT at, kind, code, error FROM events WHERE site_id = ? ORDER BY at DESC LIMIT 30")
        .bind(site.id).all()).results;
      return json({ checks, events });
    }
  }

  return error(404, "not-found");
}

function packageJson(p: PackageRow, deviceId: string, members: number) {
  return {
    id: p.id, name: p.name, key: p.join_key, isOwner: p.owner_id === deviceId, members,
    retries: p.retries, timeoutS: p.timeout_s, createdAt: p.created_at,
  };
}
