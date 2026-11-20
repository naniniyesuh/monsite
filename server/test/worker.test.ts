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

test("aralık doğrulama: hazır seçenekler, eski uzun aralıklar 60'a iner", () => {
  for (const n of [2, 3, 5, 15, 30, 60]) assert.equal(normalizeInterval(n), n);
  assert.equal(normalizeInterval(360), 60);
  assert.equal(normalizeInterval(1440), 60);
  for (const n of [0, 1, 4, 7, 10, 4.5]) assert.equal(normalizeInterval(n), null, String(n));
  assert.equal(normalizeInterval("15"), null);
});

test("isDue ve nextRun: saat başına hizalı", () => {
  const added = T("2026-11-19T11:07:20Z");
  const q = anchorFor(15, added);
  assert.ok(!isDue(15, q, tickOf(T("2026-11-19T11:00:00Z"))), "eklenmeden önce planlı kontrol yok");
  for (const hhmm of ["11:15", "11:30", "11:45", "12:00"]) assert.ok(isDue(15, q, tickOf(T(`2026-11-19T${hhmm}:00Z`))), hhmm);
  assert.ok(!isDue(15, q, tickOf(T("2026-11-19T11:16:00Z"))));
  assert.ok(isDue(15, q, tickOf(T("2026-11-19T11:59:45Z"))), "cron gecikmesi/erken tetik toleransı");
  assert.equal(nextRun(15, q, T("2026-11-19T11:15:10Z")) * 60_000, T("2026-11-19T11:30:00Z"));

  const three = anchorFor(3, added);
  for (const hhmm of ["11:09", "11:12", "11:57", "12:00", "12:03"]) assert.ok(isDue(3, three, tickOf(T(`2026-11-19T${hhmm}:00Z`))), hhmm);
  assert.ok(!isDue(3, three, tickOf(T("2026-11-19T11:10:00Z"))));
  assert.equal(nextRun(3, three, T("2026-11-19T11:10:00Z")) * 60_000, T("2026-11-19T11:12:00Z"));

  const two = anchorFor(2, added);
  assert.ok(isDue(2, two, tickOf(T("2026-11-19T11:08:00Z"))));
  assert.ok(!isDue(2, two, tickOf(T("2026-11-19T11:09:00Z"))));
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
  apnsByHost?: Record<string, { code: number; reason?: string }>;
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
      const st = h.apnsByHost?.[u.hostname] ?? h.apnsStatus;
      return new Response(st.reason ? JSON.stringify({ reason: st.reason }) : null, { status: st.code });
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
  const job = (retries: number, members = 1) => ({ site: { id: "x" }, pkg: { retries }, members }) as unknown as CheckJob;
  assert.equal(makeBatches(Array.from({ length: 45 }, () => job(0))).length, 3);
  assert.equal(makeBatches(Array.from({ length: 10 }, () => job(3))).length, 2);
  assert.equal(makeBatches(Array.from({ length: 4 }, () => job(2, 20))).length, 4, "kalabalık pakette her site kendi grubunda");
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

test("yanlış ortamdaki jeton: diğer ortam denenir, jeton silinmez, sonuç kaydedilir", async () => {
  const h = await harness();
  await call(h, "POST", "/v1/register", { deviceId: DEV, secret: SECRET }, undefined, {});
  // Uygulama "production" dedi ama jeton aslında Xcode (sandbox) jetonu
  await call(h, "PUT", "/v1/device", { apnsToken: "ef".repeat(32), apnsEnv: "production", retries: 0 });
  await call(h, "POST", "/v1/sites", { url: "api.example.com", intervalMin: 5 });
  h.siteStatus.set("api.example.com", 503);
  h.apnsByHost = { "api.push.apple.com": { code: 400, reason: "BadDeviceToken" } };
  await tick(h, "2026-11-19T11:15:00Z");
  assert.deepEqual(h.pushes.map((p) => p.host), ["api.push.apple.com", "api.sandbox.push.apple.com"]);
  const dev = h.db.db.prepare("SELECT apns_token, apns_env, push_result FROM devices").get() as any;
  assert.equal(dev.apns_token, "ef".repeat(32));
  assert.equal(dev.apns_env, "sandbox");
  assert.equal(dev.push_result, "sent");
  const st = (await call(h, "GET", "/v1/state", undefined, T("2026-11-19T11:16:00Z"))).json;
  assert.equal(st.lastPush.result, "sent");

  // Anahtar hatası gibi bir sorun kaydedilir ve Ayarlar'da görünür
  h.apnsByHost = undefined;
  h.apnsStatus = { code: 403, reason: "InvalidProviderToken" };
  const r = await call(h, "POST", "/v1/push/test", {}, T("2026-11-19T11:20:00Z"));
  assert.equal(r.status, 200);
  assert.equal(r.json.reason, "InvalidProviderToken");
  h.env.MIN_APP_BUILD = "4";
  const st2 = (await call(h, "GET", "/v1/state", undefined, T("2026-11-19T11:21:00Z"))).json;
  assert.equal(st2.minBuild, 4);
  assert.equal(st2.lastPush.result, "403 InvalidProviderToken");
});

// ---------------------------------------------------------------- paketler

const DEV2 = "dev-0002-bbbb";
const AUTH2 = { authorization: `Bearer ${DEV2}.${SECRET}` };

test("paket: oluştur, anahtarla katıl, ortak kontrol, kişisel bildirim tercihi", async () => {
  const h = await harness();
  await call(h, "POST", "/v1/register", { deviceId: DEV, secret: SECRET }, undefined, {});
  await call(h, "POST", "/v1/register", { deviceId: DEV2, secret: SECRET }, undefined, {});
  await call(h, "PUT", "/v1/device", { apnsToken: "aa".repeat(32), lang: "tr" });
  await call(h, "PUT", "/v1/device", { apnsToken: "bb".repeat(32), lang: "en" }, undefined, AUTH2);

  const pkg = (await call(h, "POST", "/v1/packages", { name: "Ekip" })).json;
  assert.equal(pkg.name, "Ekip");
  assert.equal(pkg.isOwner, true);
  assert.match(pkg.key, /^[2-9A-HJ-NP-Z]{12}$/);

  const site = (await call(h, "POST", "/v1/sites", { packageId: pkg.id, url: "shop.example.com", intervalMin: 15 })).json;
  assert.equal(site.packageId, pkg.id);

  // Yanlış anahtar, sonra tireli/küçük harfli doğru anahtar
  assert.equal((await call(h, "POST", "/v1/packages/join", { key: "XXXX-XXXX-XXXX" }, undefined, AUTH2)).status, 404);
  const pretty = pkg.key.toLowerCase().replace(/(.{4})(?=.)/g, "$1-");
  const joined = await call(h, "POST", "/v1/packages/join", { key: pretty }, undefined, AUTH2);
  assert.equal(joined.status, 200);
  assert.equal(joined.json.members, 2);
  assert.equal(joined.json.isOwner, false);
  assert.equal((await call(h, "POST", "/v1/packages/join", { key: pkg.key }, undefined, AUTH2)).status, 409);

  // İkinci üyenin eklediği site ilk üyede de görünür
  await call(h, "POST", "/v1/sites", { packageId: pkg.id, url: "api.example.com", intervalMin: 15 }, undefined, AUTH2);
  const st1 = (await call(h, "GET", "/v1/state")).json;
  assert.equal(st1.packages.length, 1);
  assert.equal(st1.packages[0].members, 2);
  assert.deepEqual(st1.sites.map((x: any) => x.url).sort(), ["https://api.example.com/", "https://shop.example.com/"]);

  // İkinci üye bu sitenin kesinti bildirimini kapatır; ilki açık bırakır
  await call(h, "PATCH", `/v1/sites/${site.id}`, { notifyDown: false }, undefined, AUTH2);
  const st2 = (await call(h, "GET", "/v1/state", undefined, undefined, AUTH2)).json;
  assert.equal(st2.sites.find((x: any) => x.id === site.id).notifyDown, false);
  assert.equal((await call(h, "GET", "/v1/state")).json.sites.find((x: any) => x.id === site.id).notifyDown, true);

  // Ortak kontrol: iki site, iki üye → tek tur, site başına bir kontrol
  h.siteStatus.set("shop.example.com", 503);
  h.siteStatus.set("api.example.com", 503);
  const before = h.db.count("runs");
  const r = await tick(h, "2026-11-19T11:15:00Z");
  assert.equal(r.due, 2);
  assert.equal(h.db.count("runs") - before, 1);
  // shop: yalnızca 1. üye; api: iki üye (ikincisi İngilizce)
  const titles = h.pushes.map((p) => `${p.token.slice(0, 2)}:${p.body.aps.alert.title}`).sort();
  assert.deepEqual(titles, ["aa:api.example.com erişilemiyor", "aa:shop.example.com erişilemiyor", "bb:api.example.com is down"]);

  // Paket ayarları ortak: tekrar deneme sayısı
  const patched = (await call(h, "PATCH", `/v1/packages/${pkg.id}`, { retries: 0, timeoutS: 99, name: "Web ekibi" }, undefined, AUTH2)).json;
  assert.equal(patched.retries, 0);
  assert.equal(patched.timeoutS, 30);
  assert.equal(patched.name, "Web ekibi");

  // Anahtarı yalnızca sahibi yeniler; eski anahtar geçersiz olur
  assert.equal((await call(h, "POST", `/v1/packages/${pkg.id}/key`, {}, undefined, AUTH2)).status, 403);
  const rotated = (await call(h, "POST", `/v1/packages/${pkg.id}/key`, {})).json;
  assert.notEqual(rotated.key, pkg.key);

  // Sahibi ayrılınca sahiplik diğer üyeye geçer; siteler kalır
  assert.equal((await call(h, "POST", `/v1/packages/${pkg.id}/leave`, {})).status, 200);
  const st3 = (await call(h, "GET", "/v1/state", undefined, undefined, AUTH2)).json;
  assert.equal(st3.packages[0].isOwner, true);
  assert.equal(st3.packages[0].members, 1);
  assert.equal(st3.sites.length, 2);
  assert.equal((await call(h, "GET", "/v1/state")).json.packages.length, 0);

  // Uygulamasını silen son üye: paket ve siteler gider
  assert.equal((await call(h, "DELETE", "/v1/device", undefined, undefined, AUTH2)).status, 200);
  assert.equal(h.db.count("packages"), 0);
  assert.equal(h.db.count("sites"), 0);
});

test("paket sınırları ve yönetici ekranı", async () => {
  const h = await harness();
  h.env.MAX_PACKAGES_PER_DEVICE = "2";
  h.env.MAX_MEMBERS = "1";
  await call(h, "POST", "/v1/register", { deviceId: DEV, secret: SECRET }, undefined, {});
  await call(h, "POST", "/v1/register", { deviceId: DEV2, secret: SECRET }, undefined, {});
  const a = (await call(h, "POST", "/v1/packages", { name: "A" })).json;
  await call(h, "POST", "/v1/packages", {});
  assert.equal((await call(h, "POST", "/v1/packages", { name: "C" })).status, 403);
  assert.equal((await call(h, "POST", "/v1/packages/join", { key: a.key }, undefined, AUTH2)).status, 403, "üye sınırı");
  await call(h, "POST", "/v1/sites", { packageId: a.id, url: "alpp.studio" });

  assert.equal((await call(h, "GET", "/v1/admin")).status, 403);
  h.env.ADMIN_DEVICE_IDS = `x, ${DEV}`;
  assert.equal((await call(h, "GET", "/v1/state")).json.isAdmin, true);
  const adm = (await call(h, "GET", "/v1/admin")).json;
  assert.equal(adm.totals.packages, 2);
  assert.equal(adm.totals.devices, 2);
  assert.deepEqual(adm.packages.map((p: any) => p.name).sort(), ["A", "Sitelerim"]);
  assert.equal(adm.packages.find((p: any) => p.name === "A").sites[0].url, "https://alpp.studio/");
  assert.deepEqual(adm.log.map((l: any) => l.kind), ["created", "created"]);

  assert.equal((await call(h, "DELETE", `/v1/packages/${a.id}`)).status, 200);
  const adm2 = (await call(h, "GET", "/v1/admin")).json;
  assert.equal(adm2.log[0].kind, "deleted");
  assert.equal(adm2.log[0].text, "A");
});

test("geçiş 0003: mevcut siteler kişisel pakete taşınır, geçmiş ve tercihler korunur", async () => {
  const db = new FakeD1({ before: "0003" });
  db.db.exec(`
    INSERT INTO devices (id, secret_hash, lang, retries, timeout_s, created_at, last_seen) VALUES ('d1', 'h', 'tr', 1, 20, 1, 1), ('d2', 'h', 'en', 2, 15, 2, 2), ('d3', 'h', 'tr', 2, 15, 3, 3);
    INSERT INTO sites (id, device_id, url, name, interval_min, anchor_min, notify_down, notify_up, created_at) VALUES
      ('s1', 'd1', 'https://a.com/', 'a', 15, 0, 1, 0, 1), ('s2', 'd1', 'https://b.com/', 'b', 5, 0, 1, 1, 1), ('s3', 'd2', 'https://c.com/', 'c', 60, 0, 1, 1, 1);
    INSERT INTO runs (device_id, at_min, data) VALUES ('d1', 100, '{"s1":200,"s2":503}'), ('d2', 100, '{"s3":200}');
  `);
  db.migrate((f) => f >= "0003");
  const pk = db.db.prepare("SELECT id, name, owner_id, retries, timeout_s, length(join_key) AS kl FROM packages ORDER BY id").all() as any[];
  assert.deepEqual(pk.map((p) => [p.id, p.name, p.owner_id, p.retries, p.timeout_s, p.kl]), [
    ["p-d1", "Sitelerim", "d1", 1, 20, 12], ["p-d2", "My sites", "d2", 2, 15, 12],
  ], "sitesi olmayan d3 için paket yok");
  assert.equal(db.count("members"), 2);
  assert.deepEqual((db.db.prepare("SELECT package_id FROM sites ORDER BY id").all() as any[]).map((r) => r.package_id), ["p-d1", "p-d1", "p-d2"]);
  assert.deepEqual(db.db.prepare("SELECT site_id, notify_down, notify_up FROM site_prefs").all().map((r: any) => ({ ...r })), [{ site_id: "s1", notify_down: 1, notify_up: 0 }]);
  assert.deepEqual((db.db.prepare("SELECT package_id FROM runs ORDER BY package_id").all() as any[]).map((r) => r.package_id), ["p-d1", "p-d2"]);
  assert.equal(db.count("admin_log"), 2);
  // Cihaz silinince ortak paketteki siteleri artık otomatik silinmez (CASCADE kalktı)
  db.db.exec("DELETE FROM devices WHERE id = 'd1'");
  assert.equal(db.count("sites"), 3);
});
