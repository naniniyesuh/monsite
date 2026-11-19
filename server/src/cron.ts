// 15 dakikada bir çalışan zamanlanmış görev.

import { isDue, tickOf } from "./schedule.ts";
import { jobsFor, RETENTION_DAYS } from "./data.ts";
import { makeBatches, runJobs, type RunOptions } from "./monitor.ts";
import type { Ctx, Env } from "./types.ts";

export async function scheduled(env: Env, ctx: Ctx, scheduledMs: number, opts: RunOptions = {}): Promise<{ due: number; batches: number }> {
  const tick = tickOf(scheduledMs);
  await env.DB.prepare("INSERT INTO meta (key, value) VALUES ('last_cron', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value")
    .bind(String(scheduledMs)).run();

  // Günde bir kez eski kayıtları temizle (UTC 03:00 turunda).
  if (tick % 1440 === 180) {
    const runCutoff = tick - RETENTION_DAYS * 1440;
    const eventCutoff = scheduledMs - 90 * 86_400_000;
    await env.DB.batch([
      env.DB.prepare("DELETE FROM runs WHERE at_min < ?").bind(runCutoff),
      env.DB.prepare("DELETE FROM events WHERE at < ?").bind(eventCutoff),
    ]);
  }

  const jobs = (await jobsFor(env)).filter((j) => isDue(j.site.interval_min, j.site.anchor_min, tick));
  if (jobs.length === 0) return { due: 0, batches: 0 };

  const batches = makeBatches(jobs);
  const self = env.SELF;
  if (batches.length === 1 || !self || !env.INTERNAL_KEY) {
    // Tek grup ya da kendini çağırma yok: sırayla burada çalıştır.
    for (const b of batches) await runJobs(env, b, tick, { ...opts, nowMs: opts.nowMs ?? scheduledMs });
    return { due: jobs.length, batches: batches.length };
  }

  // Her grup ayrı bir çağrıda çalışır; böylece her biri kendi istek sınırına sahip olur.
  const key = env.INTERNAL_KEY;
  const calls = batches.map((b) => self.fetch("https://upsite.internal/internal/batch", {
    method: "POST",
    headers: { "content-type": "application/json", "x-internal-key": key },
    body: JSON.stringify({ tick, scheduledMs, siteIds: b.map((j) => j.site.id) }),
  }).then((r) => r.status).catch(() => 0));
  ctx.waitUntil(Promise.all(calls));
  await Promise.all(calls);
  return { due: jobs.length, batches: batches.length };
}

export async function handleBatch(env: Env, req: Request, opts: RunOptions = {}): Promise<Response> {
  if (!env.INTERNAL_KEY || req.headers.get("x-internal-key") !== env.INTERNAL_KEY) return new Response("forbidden", { status: 403 });
  const body = (await req.json()) as { tick: number; scheduledMs: number; siteIds: string[] };
  const jobs = await jobsFor(env, body.siteIds.slice(0, 60));
  const t = await runJobs(env, jobs, body.tick, { ...opts, nowMs: opts.nowMs ?? body.scheduledMs });
  return Response.json({ checked: jobs.length, changes: t.length });
}
