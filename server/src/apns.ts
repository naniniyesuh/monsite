// Apple Push Notification service: JWT (ES256) ile kimlik doğrulama ve bildirim gönderme.

type FetchFn = (input: string, init?: RequestInit) => Promise<Response>;

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlString(s: string): string {
  return b64url(new TextEncoder().encode(s));
}

export function pemToPkcs8(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export async function makeJwt(p8: string, keyId: string, teamId: string, nowSec: number): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(p8),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const header = b64urlString(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = b64urlString(JSON.stringify({ iss: teamId, iat: nowSec }));
  const input = `${header}.${claims}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
  return `${input}.${b64url(new Uint8Array(sig))}`;
}

// Apple, jetonun 20–60 dakika arasında yenilenmesini istiyor.
let cached: { jwt: string; at: number; kid: string } | null = null;

export async function providerToken(p8: string, keyId: string, teamId: string, nowSec: number): Promise<string> {
  if (cached && cached.kid === keyId && nowSec - cached.at < 40 * 60) return cached.jwt;
  const jwt = await makeJwt(p8, keyId, teamId, nowSec);
  cached = { jwt, at: nowSec, kid: keyId };
  return jwt;
}

export function resetTokenCache(): void {
  cached = null;
}

export interface PushMessage {
  title: string;
  body: string;
  /** Sessiz saatlerde sessiz ve dikkat dağıtmayan bildirim */
  quiet: boolean;
  threadId?: string;
  data?: Record<string, string>;
}

export interface PushConfig {
  p8: string;
  keyId: string;
  teamId: string;
  topic: string;
}

export type PushOutcome = "sent" | "invalid-token" | "failed";

export async function sendPush(
  cfg: PushConfig,
  token: string,
  env: string,
  msg: PushMessage,
  nowSec: number,
  fetchFn: FetchFn = fetch,
): Promise<{ outcome: PushOutcome; status: number; reason?: string }> {
  const host = env === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const aps: Record<string, unknown> = {
    alert: { title: msg.title, body: msg.body },
    "interruption-level": msg.quiet ? "passive" : "active",
  };
  if (!msg.quiet) aps.sound = "default";
  if (msg.threadId) aps["thread-id"] = msg.threadId;
  const payload = { aps, ...(msg.data ?? {}) };
  try {
    const jwt = await providerToken(cfg.p8, cfg.keyId, cfg.teamId, nowSec);
    const res = await fetchFn(`${host}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": cfg.topic,
        "apns-push-type": "alert",
        "apns-priority": msg.quiet ? "5" : "10",
        "apns-expiration": String(nowSec + 3600),
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    if (res.status === 200) return { outcome: "sent", status: 200 };
    let reason: string | undefined;
    try { reason = ((await res.json()) as { reason?: string }).reason; } catch { /* yok say */ }
    if (res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered" || reason === "DeviceTokenNotForTopic") {
      return { outcome: "invalid-token", status: res.status, reason };
    }
    if (res.status === 403 && reason === "ExpiredProviderToken") resetTokenCache();
    return { outcome: "failed", status: res.status, reason };
  } catch (e) {
    return { outcome: "failed", status: 0, reason: String((e as Error)?.message ?? e) };
  }
}
