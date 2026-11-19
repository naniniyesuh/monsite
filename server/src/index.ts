import { handle } from "./api.ts";
import { handleBatch, scheduled } from "./cron.ts";
import type { Ctx, Env } from "./types.ts";

export default {
  async fetch(req: Request, env: Env, ctx: Ctx): Promise<Response> {
    const url = new URL(req.url);
    try {
      if (url.pathname === "/internal/batch" && req.method === "POST") return await handleBatch(env, req);
      return await handle(env, req, ctx);
    } catch (e) {
      console.error("request failed", e);
      return Response.json({ error: "server" }, { status: 500 });
    }
  },

  async scheduled(controller: { scheduledTime: number }, env: Env, ctx: Ctx): Promise<void> {
    const r = await scheduled(env, ctx, controller.scheduledTime);
    console.log(`tick ${new Date(controller.scheduledTime).toISOString()}: ${r.due} site, ${r.batches} grup`);
  },
};
