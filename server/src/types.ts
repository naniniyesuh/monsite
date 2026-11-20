// Cloudflare D1'in kullandığımız kısmı (testlerde aynı arayüzü SQLite ile taklit ediyoruz).
export interface D1Result<T = Record<string, unknown>> {
  results: T[];
}

export interface D1Statement {
  bind(...values: unknown[]): D1Statement;
  first<T = Record<string, unknown>>(): Promise<T | null>;
  all<T = Record<string, unknown>>(): Promise<D1Result<T>>;
  run(): Promise<unknown>;
}

export interface D1Database {
  prepare(sql: string): D1Statement;
  batch(statements: D1Statement[]): Promise<unknown[]>;
}

export interface ServiceBinding {
  fetch(input: Request | string, init?: RequestInit): Promise<Response>;
}

export interface Env {
  DB: D1Database;
  SELF?: ServiceBinding;
  APNS_KEY?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_TOPIC: string;
  INTERNAL_KEY?: string;
  MAX_SITES_PER_DEVICE?: string;
  MAX_DEVICES?: string;
  MIN_APP_BUILD?: string;
}

export interface Ctx {
  waitUntil(p: Promise<unknown>): void;
}

export type Status = "unknown" | "up" | "down";

export interface DeviceRow {
  id: string;
  secret_hash: string;
  apns_token: string | null;
  apns_env: string;
  lang: string;
  tz: string;
  retries: number;
  timeout_s: number;
  quiet_start: string | null;
  quiet_end: string | null;
  created_at: number;
  last_seen: number;
  push_at?: number | null;
  push_result?: string | null;
}

export interface SiteRow {
  id: string;
  device_id: string;
  url: string;
  name: string;
  interval_min: number;
  anchor_min: number;
  notify_down: number;
  notify_up: number;
  paused: number;
  status: Status;
  status_since: number | null;
  last_code: number | null;
  last_error: string | null;
  created_at: number;
}

/** Bir kontrol grubundaki tek site: site bilgisi + cihaz ayarları. */
export interface CheckJob {
  site: SiteRow;
  device: DeviceRow;
}

export interface CheckResult {
  ok: boolean;
  /** HTTP durum kodu; bağlantı kurulamadıysa null */
  code: number | null;
  /** Kısa hata türü: timeout | connect | dns | tls | http */
  error: string | null;
  attempts: number;
}
