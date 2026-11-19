import type { CheckResult } from "./types.ts";

export const USER_AGENT = "UpSite/2.0 (+https://alpp.studio/upsite/)";

type FetchFn = (input: string, init?: RequestInit) => Promise<Response>;

export function classifyError(e: unknown): string {
  const msg = String((e as { message?: string })?.message ?? e).toLowerCase();
  const name = String((e as { name?: string })?.name ?? "");
  if (name === "TimeoutError" || name === "AbortError" || msg.includes("timeout") || msg.includes("timed out")) return "timeout";
  if (msg.includes("dns") || msg.includes("getaddrinfo") || msg.includes("not resolve") || msg.includes("enotfound")) return "dns";
  if (msg.includes("ssl") || msg.includes("tls") || msg.includes("certificate") || msg.includes("handshake")) return "tls";
  return "connect";
}

/**
 * Siteyi bir kez yoklar. Yönlendirmeler izlenir; son yanıt 200–299 ise erişilebilir.
 * Gövde okunmaz, yalnızca durum koduna bakılır.
 */
export async function probe(url: string, timeoutMs: number, fetchFn: FetchFn = fetch): Promise<CheckResult> {
  try {
    const res = await fetchFn(url, {
      method: "GET",
      redirect: "follow",
      headers: { "user-agent": USER_AGENT, accept: "text/html,*/*;q=0.8", "cache-control": "no-cache" },
      signal: AbortSignal.timeout(timeoutMs),
    });
    try { await res.body?.cancel(); } catch { /* yok say */ }
    const ok = res.status >= 200 && res.status < 300;
    return { ok, code: res.status, error: ok ? null : "http", attempts: 1 };
  } catch (e) {
    return { ok: false, code: null, error: classifyError(e), attempts: 1 };
  }
}

/** Başarısız olursa `retries` kez daha dener (yanlış alarm koruması). */
export async function checkWithRetries(
  url: string,
  timeoutMs: number,
  retries: number,
  fetchFn: FetchFn = fetch,
  waitMs = 2000,
): Promise<CheckResult> {
  let last = await probe(url, timeoutMs, fetchFn);
  let attempts = 1;
  while (!last.ok && attempts <= retries) {
    if (waitMs > 0) await new Promise((r) => setTimeout(r, waitMs));
    last = await probe(url, timeoutMs, fetchFn);
    attempts += 1;
  }
  return { ...last, attempts };
}
