// Testler için Cloudflare D1 taklidi (Node'un yerleşik SQLite'ı ile).
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import type { D1Database, D1Result, D1Statement } from "../src/types.ts";

function norm(v: unknown): unknown {
  if (v === undefined) return null;
  if (typeof v === "boolean") return v ? 1 : 0;
  return v;
}

class Stmt implements D1Statement {
  private db: DatabaseSync;
  private sql: string;
  private values: unknown[] = [];
  constructor(db: DatabaseSync, sql: string) { this.db = db; this.sql = sql; }
  bind(...values: unknown[]): D1Statement {
    const s = new Stmt(this.db, this.sql);
    s.values = values.map(norm);
    return s;
  }
  async first<T>(): Promise<T | null> {
    const row = this.db.prepare(this.sql).get(...(this.values as never[]));
    return (row ? { ...row } : null) as T | null;
  }
  async all<T>(): Promise<D1Result<T>> {
    const rows = this.db.prepare(this.sql).all(...(this.values as never[]));
    return { results: rows.map((r) => ({ ...r })) as T[] };
  }
  async run(): Promise<unknown> {
    return this.db.prepare(this.sql).run(...(this.values as never[]));
  }
  exec(): void {
    this.db.prepare(this.sql).run(...(this.values as never[]));
  }
}

export class FakeD1 implements D1Database {
  db: DatabaseSync;
  constructor() {
    this.db = new DatabaseSync(":memory:");
    const sql = readFileSync(new URL("../migrations/0001_init.sql", import.meta.url), "utf8");
    this.db.exec(sql);
  }
  prepare(sql: string): D1Statement {
    return new Stmt(this.db, sql);
  }
  async batch(statements: D1Statement[]): Promise<unknown[]> {
    this.db.exec("BEGIN");
    try {
      for (const s of statements) (s as Stmt).exec();
      this.db.exec("COMMIT");
    } catch (e) {
      this.db.exec("ROLLBACK");
      throw e;
    }
    return statements.map(() => ({}));
  }
  count(table: string): number {
    return (this.db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number }).n;
  }
}
