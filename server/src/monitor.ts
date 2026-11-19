// Kontrolleri çalıştırır, durum değişikliklerini kaydeder ve bildirim gönderir.

import { checkWithRetries } from "./check.ts";
import { sendPush, type PushConfig } from "./apns.ts";
import { downMessage, inQuietHours, langOf, upMessage } from "./messages.ts";
import type { CheckJob, CheckResult, D1Statement, DeviceRow, Env, SiteRow } from "./types.ts";

type FetchFn = (input: string, init?: RequestInit) => Promise<Response>;

export interface RunOptions {
  fetchFn?: FetchFn;
  retryWaitMs?: number;
  nowMs?: number;
}

export function pushConfig(env: Env): PushConfig | null {
  if (!env.APNS_KEY || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) return null;
  return { p8: env.APNS_KEY, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, topic: env.APNS_TOPIC };
}

export interface Transition {
  site: SiteRow;
  device: DeviceRow;
  result: CheckResult;
  from: SiteRow["status"];
  to: "up" | "down";
  notify: boolean;
}

/** Bir sonucun durum geçişini hesaplar; bildirim gerekip gerekmediğine karar verir. */
export function transitionFor(site: SiteRow, result: CheckResult): { to: "up" | "down"; changed: boolean; notify: boolean } {
  const to = result.ok ? "up" : "down";
  const changed = site.status !== to;
  let notify = false;
  if (changed) {
    if (to === "down") notify = site.notify_down === 1;
    else notify = site.status === "down" && site.notify_up === 1;
  }
  return { to, changed, notify };
}

export async function runJobs(env: Env, jobs: CheckJob[], tickMin: number, opts: RunOptions = {}): Promise<Transition[]> {
  if (jobs.length === 0) return [];
  const fetchFn = opts.fetchFn ?? fetch;
  const nowMs = opts.nowMs ?? Date.now();

  const results = await Promise.all(jobs.map((j) =>
    checkWithRetries(j.site.url, j.device.timeout_s * 1000, j.device.retries, fetchFn, opts.retryWaitMs ?? 2000)));

  const statements: D1Statement[] = [];
  const perDevice = new Map<string, Record<string, number>>();
  const transitions: Transition[] = [];

  jobs.forEach((job, i) => {
    const r = results[i];
    const runData = perDevice.get(job.device.id) ?? {};
    runData[job.site.id] = r.ok ? (r.code ?? 200) : (r.code ?? -1);
    perDevice.set(job.device.id, runData);

    const t = transitionFor(job.site, r);
    if (t.changed) {
      statements.push(env.DB.prepare(
        "UPDATE sites SET status = ?, status_since = ?, last_code = ?, last_error = ? WHERE id = ?",
      ).bind(t.to, nowMs, r.code, r.error, job.site.id));
      if (!(job.site.status === "unknown" && t.to === "up")) {
        statements.push(env.DB.prepare(
          "INSERT INTO events (site_id, device_id, at, kind, code, error) VALUES (?, ?, ?, ?, ?, ?)",
        ).bind(job.site.id, job.device.id, nowMs, t.to, r.code, r.error));
      }
      transitions.push({ site: job.site, device: job.device, result: r, from: job.site.status, to: t.to, notify: t.notify });
    } else if (t.to === "down" && (job.site.last_code !== r.code || job.site.last_error !== r.error)) {
      statements.push(env.DB.prepare("UPDATE sites SET last_code = ?, last_error = ? WHERE id = ?")
        .bind(r.code, r.error, job.site.id));
    }
  });

  for (const [deviceId, data] of perDevice) {
    statements.push(env.DB.prepare("INSERT INTO runs (device_id, at_min, data) VALUES (?, ?, ?)")
      .bind(deviceId, tickMin, JSON.stringify(data)));
  }
  if (statements.length) await env.DB.batch(statements);

  const cfg = pushConfig(env);
  const invalid: string[] = [];
  if (cfg) {
    await Promise.all(transitions.filter((t) => t.notify && t.device.apns_token).map(async (t) => {
      const lang = langOf(t.device.lang);
      const text = t.to === "down"
        ? downMessage(t.site.name, t.result.code, t.result.error, t.result.attempts, nowMs, t.device.tz, lang)
        : upMessage(t.site.name, t.site.status_since, nowMs, lang);
      const quiet = inQuietHours(nowMs, t.device.tz, t.device.quiet_start, t.device.quiet_end);
      const res = await sendPush(cfg, t.device.apns_token as string, t.device.apns_env, {
        ...text, quiet, threadId: t.site.id, data: { siteId: t.site.id, kind: t.to },
      }, Math.floor(nowMs / 1000), fetchFn);
      if (res.outcome === "invalid-token") invalid.push(t.device.id);
    }));
  }
  if (invalid.length) {
    await env.DB.batch([...new Set(invalid)].map((id) =>
      env.DB.prepare("UPDATE devices SET apns_token = NULL WHERE id = ?").bind(id)));
  }
  return transitions;
}

/** Bir grup için "dış istek" maliyeti: denemeler + olası bildirim. */
export function jobCost(job: CheckJob): number {
  return job.device.retries + 1 + 1;
}

/** İşleri, her grup ücretsiz plandaki istek sınırının altında kalacak şekilde böler. */
export function makeBatches(jobs: CheckJob[], budget = 40): CheckJob[][] {
  const batches: CheckJob[][] = [];
  let current: CheckJob[] = [];
  let used = 0;
  for (const job of jobs) {
    const c = jobCost(job);
    if (current.length && used + c > budget) {
      batches.push(current);
      current = [];
      used = 0;
    }
    current.push(job);
    used += c;
  }
  if (current.length) batches.push(current);
  return batches;
}
