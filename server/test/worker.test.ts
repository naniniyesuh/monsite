import { test } from "node:test";
import assert from "node:assert/strict";
import { FakeD1 } from "./fake-d1.ts";
import { anchorFor, isDue, nextRun, normalizeInterval, tickOf } from "../src/schedule.ts";
import { formatDuration, inQuietHours, localTime } from "../src/messages.ts";
import { makeJwt, resetTokenCache } from "../src/apns.ts";
import { handle, normalizeUrl } from "../src/api.ts";
import { handleBatch, scheduled } from "../src/cron.ts";
import { makeBatches } from "../src/monitor.ts";
import type { CheckJob, Env } from "../src/types.ts";

const T = (iso: string) => Date.parse(iso);

// ---------------------------------------------------------------- zamanlama

test("aralık doğrulama: 1–60 dk, eski uzun aralıklar 60'a iner", () => {
  assert.equal(normalizeInterval(4), 4);
  assert.equal(normalizeInterval(1), 1);
  assert.equal(normalizeInterval(60), 60);
  assert.equal(normalizeInterval(360), 60);
  assert.equal(normalizeInterval(1440), 60);
  assert.equal(normalizeInterval(0), null);
  assert.equal(normalizeInterval(4.5), null);
  assert.equal(normalizeInterval("15"), null);
});

test("isDue ve nextRun: saat başına hizalı", () => {
  const added = T("2026-11-19T11:07:20Z");
  const q = anchorFor(15, added);
  assert.ok(!isDue(15, q, tickOf(T("2026-11-19T11:07:00Z"))), "eklendiği dakikada planlı kontrol yok");
  for (const hhmm of ["11:15", "11:30", "11:45", "12:00"]) assert.ok(isDue(15, q, tickOf(T(`2026-11-19T${hhmm}:00Z`))), hhmm);
  assert.ok(!isDue(15, q, tickOf(T("2026-11-19T11:16:00Z"))));
  assert.ok(isDue(15, q, tickOf(T("2026-11-19T11:59:45Z"))), "cron gecikmesi/erken tetik toleransı");
  assert.equal(nextRun(15, q, T("2026-11-19T11:15:10Z")) * 60_000, T("2026-11-19T11:30:00Z"));

  const four = anchorFor(4, added);
  for (const hhmm of ["11:08", "11:12", "11:56", "12:00", "12:04"]) assert.ok(isDue(4, four, tickOf(T(`2026-11-19T${hhmm}:00Z`))), hhmm);
  assert.ok(!isDue(4, four, tickOf(T("2026-11-19T11:10:00Z"))));
  assert.equal(nextRun(4, four, T("2026-11-19T11:09:00Z")) * 60_000, T("2026-11-19T11:12:00Z"));

  // 60'ı tam bölmeyen aralık: her saat başında yeniden :00
  const seven = anchorFor(7, added);
  assert.ok(isDue(7, seven, tickOf(T("2026-11-19T11:56:00Z"))));
  assert.ok(!isDue(7, seven, tickOf(T("2026-11-19T12:03:00Z"))));
  assert.ok(isDue(7, seven, tickOf(T("2026-11-19T12:00:00Z"))));
  assert.equal(nextRun(7, seven, T("2026-11-19T11:57:00Z")) * 60_000, T("2026-11-19T12:00:00Z"));

  const one = anchorFor(1, added);
  assert.ok(isDue(1, one, tickOf(T("2026-11-19T11:09:00Z"))));
  assert.equal(nextRun(60, anchorFor(60, added), T("2026-11-19T11:07:20Z")) * 60_000, T("2026-11-19T12:00:00Z"));
});

// ---------------------------------------------------------------- mesajlar

test("sessiz saatler ve süre biçimi", () => {
  const tz = "Europe/Istanbul";
  assert.equal(localTime(T("2026-11-19T20:30:00Z"), tz), "23:30");
  assert.ok(inQuietHours(T("2026-11-19T20:30:00Z"), tz, "23:00", "07:00"));
  assert.ok(inQuietHours(T("2026-11-20T03:00:00Z"), tz, "23:00", "07:00"));
  assert.ok(!inQuietHours(T("2026-11-20T05:00:00Z"), tz, "23:00", "07:00"));
  assert.ok(!inQuietHours(T("2026-11-20T05:00:00Z"), tz, null, null));
  assert.equal(formatDuration(30 * 60_000, "tr"), "30 dakika");
  assert.equal(formatDuration(95 * 60_000, "tr"), "1 saat 35 dakika");
  assert.equal(formatDuration(26 * 3_600_000, "en"), "1 day 2 hours");
});

test("normalizeUrl", () => {
  assert.equal(normalizeUrl("alpp.studio"), "https://alpp.studio/");
  assert.equal(normalizeUrl(" http://Example.com/a#x "), "http://example.com/a");
  assert.equal(normalizeUrl("localhost"), null);
  assert.equal(normalizeUrl("192.168.1.1"), null);
  assert.equal(normalizeUrl("ftp://example.com"), null);
  assert.equal(normalizeUrl("https://user:pw@example.com"), null);
});

// ---------------------------------------------------------------- APNs JWT

async function p8Pair() {
  const kp = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", kp.privateKey));
  const b64 = Buffer.from(der).toString("base64").replace(/(.{64})/g, "$1\n");
  return { pem: `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`, pub: kp.publicKey };
}

test("APNs JWT ES256 imzası doğrulanıyor", async () => {
  const { pem, pub } = await p8Pair();
  const jwt = await makeJwt(pem, "ABC123DEFG", "TEAM123456", 1_800_000_000);
  const [h, c, s] = jwt.split(".");
  const dec = (x: string) => JSON.parse(Buffer.from(x, "base64url").toString());
  assert.deepEqual(dec(h), { alg: "ES256", kid: "ABC123DEFG" });
  assert.deepEqual(dec(c), { iss: "TEAM123456", iat: 1_800_000_000 });
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pub, Buffer.from(s, "base64url"), new TextEncoder().encode(`${h}.${c}`));
  assert.ok(ok);
});

// ---------------------------------------------------------------- uçtan uca

interface Harness {
  env: Env;
  db: FakeD1;
  pushes: { token: string; host: string; headers: Record<string, string>; body: any }[];
  siteStatus: Map<string, number | "timeout">;
  fetchFn: (input: string, init?: RequestInit) => Promise<Response>;
  waits: Promise<unknown>[];
  apnsStatus: { code: number; reason?: string };
}

async function harness(): Promise<Harness> {
  resetTokenCache();
  const db = new FakeD1();
  const { pem } = await p8Pair();
  const h: Harness = {
    db, pushes: [], siteStatus: new Map(), waits: [], apnsStatus: { code: 200 },
    env: { DB: db, APNS_KEY: pem, APNS_KEY_ID: "KEYID12345", APNS_TEAM_ID: "TEAMID1234", APNS_TOPIC: "studio.alpp.monsite", INTERNAL_KEY: "k".repeat(24) },
    fetchFn: async () => new Response(null),
  };
  h.fetchFn = async (input, init) => {
    const u = new URL(input);
    if (u.hostname.endsWith("push.apple.com")) {
      const headers: Record<string, string> = {};
      new Headers(init?.headers).forEach((v, k) => { headers[k] = v; });
      h.pushes.push({ token: u.pathname.split("/").pop() as string, host: u.hostname, headers, body: JSON.parse(String(init?.body)) });
      return new Response(h.apnsStatus.reason ? JSON.stringify({ reason: h.apnsStatus.reason }) : null, { status: h.apnsStatus.code });
    }
    const s = h.siteStatus.get(u.hostname) ?? 200;
    if (s === "timeout") { const e = new Error("The operation was aborted due to timeout"); e.name = "TimeoutError"; throw e; }
    return new Response("ok", { status: s });
  };
  return h;
}

const DEV = "dev-0001-aaaa";
const SECRET = "s3cr3t_s3cr3t_s3cr3t_s3cr3t";
const AUTH = { authorization: `Bearer ${DEV}.${SECRET}` };

async function call(h: Harness, method: string, path: string, body?: unknown, nowMs = T("2026-11-19T11:07:00Z"), headers: Record<string, string> = AUTH) {
  const req = new Request(`https://api.test${path}`, {
    method, headers: { "content-type": "application/json", ...headers }, body: body === undefined ? undefined : JSON.stringify(body),
  });
  const ctx = { waitUntil: (p: Promise<unknown>) => { h.waits.push(p); } };
  const res = await handle(h.env, req, ctx, { fetchFn: h.fetchFn, retryWaitMs: 0, nowMs });
  await Promise.all(h.waits.splice(0));
  return { status: res.status, json: await res.json() as any };
}

async function tick(h: Harness, iso: string) {
  const ctx = { waitUntil: (p: Promise<unknown>) => { h.waits.push(p); } };
  const r = await scheduled(h.env, ctx, T(iso), { fetchFn: h.fetchFn, retryWaitMs: 0 });
  await Promise.all(h.waits.splice(0));
  return r;
}

test("kayıt, kimlik doğrulama ve site ekleme", async () => {
  const h = await harness();
  assert.equal((await call(h, "GET", "/v1/state", undefined, undefined, {})).status, 401);
  assert.equal((await call(h, "POST", "/v1/register", { deviceId: DEV, secret: SECRET }, undefined, {})).status, 201);
  assert.equal((await call(h, "POST", "/v1/register", { deviceId: DEV, secret: SECRET }, undefined, {})).status, 200);
  assert.equal((await call(h, "POST", "/v1/register", { deviceId: DEV, secret: "x".repeat(30) }, undefined, {})).status, 409);
  assert.equal((await call(h, "GET", "/v1/state", undefined, undefined, { authorization: `Bearer ${DEV}.${"y".repeat(30)}` })).status, 401);

  const add = await call(h, "POST", "/v1/sites", { url: "shop.example.com", intervalMin: 15 });
  assert.equal(add.status, 201);
  assert.equal(add.json.url, "https://shop.example.com/");
  assert.equal(add.json.name, "shop.example.com");
  assert.equal(add.json.nextCheckAt, T("2026-11-19T11:15:00Z"));
  assert.equal((await call(h, "POST", "/v1/sites", { url: "https://shop.example.com" })).status, 409);
  assert.equal((await call(h, "POST", "/v1/sites", { url: "not a url" })).status, 400);

  const st = await call(h, "GET", "/v1/state");
  assert.equal(st.json.sites.length, 1);
  assert.equal(st.json.sites[0].status, "up", "ilk kontrol hemen yapıldı");
  assert.equal(h.pushes.length, 0, "unknown → up bildirim göndermez");
});

test("kesinti ve düzelme: bildirimler, olaylar ve geçmiş", async () => {
  const h = await harness();
  await call(h, "POST", "/v1/register", { deviceId: DEV, secret: SECRET }, undefined, {});
  await call(h, "PUT", "/v1/device", { apnsToken: "ab".repeat(32), apnsEnv: "sandbox", lang: "tr", tz: "Europe/Istanbul", retries: 2 });
  const site = (await call(h, "POST", "/v1/sites", { url: "shop.example.com", name: "Mağaza", intervalMin: 15 })).json;

  h.siteStatus.set("shop.example.com", 503);
  const r1 = await tick(h, "2026-11-19T11:15:00Z");
  assert.equal(r1.due, 1);
  assert.equal(h.pushes.length, 1);
  const p = h.pushes[0];
  assert.equal(p.host, "api.sandbox.push.apple.com");
  assert.equal(p.headers["apns-topic"], "studio.alpp.monsite");
  assert.equal(p.headers["apns-push-type"], "alert");
  assert.match(p.headers.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  assert.equal(p.body.aps.alert.title, "Mağaza erişilemiyor");
  assert.equal(p.body.aps.alert.body, "HTTP 503 · 14:15 kontrolünde, 3 denemede yanıt alınamadı.");
  assert.equal(p.body.aps.sound, "default");
  assert.equal(p.body.siteId, site.id);

  await tick(h, "2026-11-19T11:30:00Z");
  assert.equal(h.pushes.length, 1, "kesinti sürerken tekrar bildirim yok");

  h.siteStatus.set("shop.example.com", 200);
  await tick(h, "2026-11-19T11:45:00Z");
  assert.equal(h.pushes.length, 2);
  assert.equal(h.pushes[1].body.aps.alert.title, "Mağaza tekrar erişilebilir");
  assert.equal(h.pushes[1].body.aps.alert.body, "Kesinti 30 dakika sürdü.");

  const st = (await call(h, "GET", "/v1/state", undefined, T("2026-11-19T11:50:00Z"))).json;
  const s = st.sites[0];
  assert.equal(s.status, "up");
  assert.equal(s.lastCheckAt, T("2026-11-19T11:45:00Z"));
  assert.equal(s.nextCheckAt, T("2026-11-19T12:00:00Z"));
  assert.deepEqual(s.recent.map((x: number[]) => x[1]), [200, 503, 503, 200]);
  assert.equal(st.lastCronAt, T("2026-11-19T11:45:00Z"));

  const hist = (await call(h, "GET", `/v1/sites/${site.id}/history?days=7`, undefined, T("2026-11-19T11:50:00Z"))).json;
  assert.equal(hist.checks.length, 4);
  assert.deepEqual(hist.events.map((e: any) => e.kind), ["up", "down"]);
});

test("zaman aşımı, sessiz saat, İngilizce ve geçersiz jeton", async () => {
  const h = await harness();
  await call(h, "POST", "/v1/register", { deviceId: DEV, secret: SECRET }, undefined, {});
  await call(h, "PUT", "/v1/device", { apnsToken: "cd".repeat(32), lang: "en", tz: "Europe/Istanbul", retries: 0, quietStart: "00:00", quietEnd: "23:59" });
  await call(h, "POST", "/v1/sites", { url: "api.example.com", intervalMin: 30 });
  h.siteStatus.set("api.example.com", "timeout");
  h.apnsStatus = { code: 410, reason: "Unregistered" };
  await tick(h, "2026-11-19T11:30:00Z");
  assert.equal(h.pushes.length, 1);
  const p = h.pushes[0];
  assert.equal(p.host, "api.push.apple.com");
  assert.equal(p.body.aps.alert.title, "api.example.com is down");
  assert.equal(p.body.aps.alert.body, "Timed out · 14:30 check.");
  assert.equal(p.body.aps["interruption-level"], "passive");
  assert.equal(p.body.aps.sound, undefined);
  const dev = h.db.db.prepare("SELECT apns_token FROM devices").get() as { apns_token: string | null };
  assert.equal(dev.apns_token, null, "geçersiz jeton silindi");
});

test("duraklatılan site kontrol edilmez, aralığı gelmeyen site atlanır", async () => {
  const h = await harness();
  await call(h, "POST", "/v1/register", { deviceId: DEV, secret: SECRET }, undefined, {});
  const a = (await call(h, "POST", "/v1/sites", { url: "a.example.com", intervalMin: 15 })).json;
  await call(h, "POST", "/v1/sites", { url: "b.example.com", intervalMin: 60 });
  await call(h, "PATCH", `/v1/sites/${a.id}`, { paused: true });
  assert.equal((await tick(h, "2026-11-19T11:15:00Z")).due, 0);
  assert.equal((await tick(h, "2026-11-19T12:00:00Z")).due, 1);
});

test("gruplara bölme ve kendini çağırma", async () => {
  const h = await harness();
  await call(h, "POST", "/v1/register", { deviceId: DEV, secret: SECRET }, undefined, {});
  await call(h, "PUT", "/v1/device", { retries: 2 });
  for (let i = 0; i < 25; i++) await call(h, "POST", "/v1/sites", { url: `s${i}.example.com`, intervalMin: 15 });
  let selfCalls = 0;
  h.env.SELF = {
    fetch: async (input: Request | string, init?: RequestInit) => {
      selfCalls += 1;
      const req = new Request(typeof input === "string" ? input : input.url, init);
      return handleBatch(h.env, req, { fetchFn: h.fetchFn, retryWaitMs: 0 });
    },
  };
  const before = h.db.count("runs");
  const r = await tick(h, "2026-11-19T11:15:00Z");
  assert.equal(r.due, 25);
  assert.equal(r.batches, 3, "denemeler 2 iken site başı maliyet 4 → 10'arlı gruplar");
  assert.equal(selfCalls, 3);
  assert.equal(h.db.count("runs") - before, 1, "aynı dakikadaki gruplar tek satırda birleşir");
  const st = (await call(h, "GET", "/v1/state", undefined, T("2026-11-19T11:16:00Z"))).json;
  assert.ok(st.sites.every((s: any) => s.lastCheckAt === T("2026-11-19T11:15:00Z")));

  const forbidden = await handleBatch(h.env, new Request("https://x/internal/batch", { method: "POST", body: "{}" }));
  assert.equal(forbidden.status, 403);
});

test("makeBatches maliyet hesabı", () => {
  const job = (retries: number) => ({ site: { id: "x" }, device: { retries } }) as unknown as CheckJob;
  assert.equal(makeBatches(Array.from({ length: 45 }, () => job(0))).length, 3);
  assert.equal(makeBatches(Array.from({ length: 10 }, () => job(3))).length, 2);
});

test("şimdi kontrol et, test bildirimi, geçmişi ve verileri silme", async () => {
  const h = await harness();
  await call(h, "POST", "/v1/register", { deviceId: DEV, secret: SECRET }, undefined, {});
  const site = (await call(h, "POST", "/v1/sites", { url: "c.example.com" })).json;
  assert.equal((await call(h, "POST", "/v1/push/test")).status, 409, "jeton yokken test bildirimi gönderilemez");
  await call(h, "PUT", "/v1/device", { apnsToken: "ef".repeat(32) });
  const t = await call(h, "POST", "/v1/push/test");
  assert.equal(t.status, 200);
  assert.equal(h.pushes.at(-1)?.body.aps.alert.title, "UpSite test bildirimi");

  h.siteStatus.set("c.example.com", 500);
  const now = await call(h, "POST", `/v1/sites/${site.id}/check`, undefined, T("2026-11-19T11:20:00Z"));
  assert.equal(now.json.status, "down");
  assert.equal(now.json.lastCode, 500);

  assert.equal((await call(h, "DELETE", "/v1/history")).status, 200);
  assert.equal(h.db.count("runs"), 0);
  assert.equal(h.db.count("events"), 0);
  assert.equal((await call(h, "DELETE", "/v1/device")).status, 200);
  assert.equal(h.db.count("devices"), 0);
  assert.equal(h.db.count("sites"), 0);
});
