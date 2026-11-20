// Kontrolleri çalıştırır, durum değişikliklerini kaydeder ve bildirim gönderir.

import { checkWithRetries } from "./check.ts";
import { pushResultText, sendPushAnyEnv, type PushConfig } from "./apns.ts";
import { downMessage, inQuietHours, langOf, upMessage } from "./messages.ts";
import { recipientsFor } from "./data.ts";
import type { CheckJob, CheckResult, D1Statement, Env, SiteRow } from "./types.ts";

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
  result: CheckResult;
  from: SiteRow["status"];
  to: "up" | "down";
}

/** Bir sonucun durum geçişini hesaplar. */
export function transitionFor(site: SiteRow, result: CheckResult): { to: "up" | "down"; changed: boolean } {
  const to = result.ok ? "up" : "down";
  return { to, changed: site.status !== to };
}

/** Geçiş için bu üyeye bildirim gidecek mi? (kesinti: notify_down; düzelme: yalnızca önceki durum "down" ise) */
export function shouldNotify(t: Transition, r: { nd: number; nu: number }): boolean {
  if (t.to === "down") return r.nd === 1;
  return t.from === "down" && r.nu === 1;
}

export async function runJobs(env: Env, jobs: CheckJob[], tickMin: number, opts: RunOptions = {}): Promise<Transition[]> {
  if (jobs.length === 0) return [];
  const fetchFn = opts.fetchFn ?? fetch;
  const nowMs = opts.nowMs ?? Date.now();

  const results = await Promise.all(jobs.map((j) =>
    checkWithRetries(j.site.url, j.pkg.timeout_s * 1000, j.pkg.retries, fetchFn, opts.retryWaitMs ?? 2000)));

  const statements: D1Statement[] = [];
  const perPackage = new Map<string, Record<string, number>>();
  const transitions: Transition[] = [];

  jobs.forEach((job, i) => {
    const r = results[i];
    const runData = perPackage.get(job.pkg.id) ?? {};
    runData[job.site.id] = r.ok ? (r.code ?? 200) : (r.code ?? -1);
    perPackage.set(job.pkg.id, runData);

    const t = transitionFor(job.site, r);
    if (t.changed) {
      statements.push(env.DB.prepare(
        "UPDATE sites SET status = ?, status_since = ?, last_code = ?, last_error = ? WHERE id = ?",
      ).bind(t.to, nowMs, r.code, r.error, job.site.id));
      if (!(job.site.status === "unknown" && t.to === "up")) {
        statements.push(env.DB.prepare(
          "INSERT INTO events (site_id, device_id, at, kind, code, error) VALUES (?, ?, ?, ?, ?, ?)",
        ).bind(job.site.id, job.site.device_id, nowMs, t.to, r.code, r.error));
      }
      transitions.push({ site: job.site, result: r, from: job.site.status, to: t.to });
    } else if (t.to === "down" && (job.site.last_code !== r.code || job.site.last_error !== r.error)) {
      statements.push(env.DB.prepare("UPDATE sites SET last_code = ?, last_error = ? WHERE id = ?")
        .bind(r.code, r.error, job.site.id));
    }
  });

  for (const [packageId, data] of perPackage) {
    statements.push(env.DB.prepare(
      // Aynı dakikada aynı paket için ikinci bir grup ya da "şimdi kontrol et" sonuçları birleştirilir.
      "INSERT INTO runs (package_id, at_min, data) VALUES (?, ?, ?) ON CONFLICT(package_id, at_min) DO UPDATE SET data = json_patch(runs.data, excluded.data)",
    ).bind(packageId, tickMin, JSON.stringify(data)));
  }
  if (statements.length) await env.DB.batch(statements);

  const cfg = pushConfig(env);
  if (!cfg || transitions.length === 0) return transitions;

  const byId = new Map(transitions.map((t) => [t.site.id, t]));
  const recipients = (await recipientsFor(env, transitions.map((t) => t.site)))
    .filter((r) => r.apns_token && shouldNotify(byId.get(r.site_id) as Transition, r));
  const invalid: string[] = [];
  const pushLog: D1Statement[] = [];
  await Promise.all(recipients.map(async (d) => {
    const t = byId.get(d.site_id) as Transition;
    const lang = langOf(d.lang);
    const text = t.to === "down"
      ? downMessage(t.site.name, t.result.code, t.result.error, t.result.attempts, nowMs, d.tz, lang)
      : upMessage(t.site.name, t.site.status_since, nowMs, lang);
    const quiet = inQuietHours(nowMs, d.tz, d.quiet_start, d.quiet_end);
    const res = await sendPushAnyEnv(cfg, d.apns_token as string, d.apns_env, {
      ...text, quiet, threadId: t.site.id, data: { siteId: t.site.id, kind: t.to },
    }, Math.floor(nowMs / 1000), fetchFn);
    pushLog.push(env.DB.prepare("UPDATE devices SET push_at = ?, push_result = ?, apns_env = ? WHERE id = ?")
      .bind(nowMs, pushResultText(res), res.env, d.id));
    // Yalnızca Apple jetonun artık geçerli olmadığını kesin söylediğinde silinir.
    if (res.outcome === "invalid-token" && res.reason !== "BadDeviceToken") invalid.push(d.id);
  }));
  const after = [...pushLog, ...[...new Set(invalid)].map((id) =>
    env.DB.prepare("UPDATE devices SET apns_token = NULL WHERE id = ?").bind(id))];
  if (after.length) await env.DB.batch(after);
  return transitions;
}

/** Bir grup için "dış istek" maliyeti: denemeler + olası bildirim. */
export function jobCost(job: CheckJob): number {
  // Denemeler + durum değişirse her üyeye birer bildirim (her geçişte BadDeviceToken için olası ikinci deneme hariç).
  return job.pkg.retries + 1 + Math.max(1, job.members);
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
