import { neon } from "@neondatabase/serverless";

export interface Env {
  DATABASE_URL: string;
  APP_TOKEN: string;
}

/** One row of `time_entries`, in the JSON shape the app sends and receives. Times are Unix epoch seconds. */
export type RemoteTimeEntry = {
  device_entry_id: string;
  slot_start: number;
  slot_end: number | null;
  entry_description: string;
  submitted_at: number;
};

/** Runs one parameterized statement and returns its rows. Injected so the handler is testable without a database. */
export type Query = (text: string, params: unknown[]) => Promise<Record<string, unknown>[]>;

export const MAX_BATCH = 5000;
const SLOT_SECONDS = 1800;

export const SELECT_SQL = `
select device_entry_id, slot_start, slot_end, entry_description, submitted_at
from time_entries
order by slot_start`;

// The WHERE on the conflict branch is what keeps a stale device from overwriting a newer edit.
export const UPSERT_SQL = `
insert into time_entries (device_entry_id, slot_start, slot_end, entry_description, submitted_at)
select device_entry_id, slot_start, coalesce(slot_end, slot_start + ${SLOT_SECONDS}), entry_description, submitted_at
from json_to_recordset($1::json) as r(
  device_entry_id text,
  slot_start double precision,
  slot_end double precision,
  entry_description text,
  submitted_at double precision
)
on conflict (device_entry_id) do update set
  slot_start = excluded.slot_start,
  slot_end = excluded.slot_end,
  entry_description = excluded.entry_description,
  submitted_at = excluded.submitted_at
where excluded.submitted_at > time_entries.submitted_at
returning device_entry_id`;

export async function handle(request: Request, env: Env, query: Query): Promise<Response> {
  // Auth first, so unauthenticated callers learn nothing about routes.
  if (!isAuthorized(request, env.APP_TOKEN)) {
    return json({ error: "unauthorized" }, 401);
  }

  const { pathname } = new URL(request.url);
  if (pathname !== "/entries") {
    return json({ error: "not found" }, 404);
  }

  if (request.method === "GET") {
    return json(await query(SELECT_SQL, []));
  }

  if (request.method === "POST") {
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return json({ error: "body must be JSON" }, 400);
    }
    const parsed = parseEntries(body);
    if (typeof parsed === "string") {
      return json({ error: parsed }, 400);
    }
    const entries = newestPerId(parsed);
    if (entries.length === 0) {
      return json({ upserted: 0 });
    }
    const rows = await query(UPSERT_SQL, [JSON.stringify(entries)]);
    return json({ upserted: rows.length });
  }

  return json({ error: "method not allowed" }, 405);
}

/** Constant-time comparison of the bearer token. An unset APP_TOKEN rejects everything. */
export function isAuthorized(request: Request, token: string | undefined): boolean {
  if (!token) return false;
  const header = request.headers.get("authorization") ?? "";
  const expected = `Bearer ${token}`;
  if (header.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) {
    diff |= header.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

/** Validates a POST body. Returns the entries, or an error message. */
export function parseEntries(body: unknown): RemoteTimeEntry[] | string {
  if (!Array.isArray(body)) return "body must be a JSON array";
  if (body.length > MAX_BATCH) return `at most ${MAX_BATCH} entries per request`;

  const entries: RemoteTimeEntry[] = [];
  for (const [index, item] of body.entries()) {
    const e = item as Partial<RemoteTimeEntry> | null;
    const valid =
      typeof e === "object" && e !== null &&
      typeof e.device_entry_id === "string" && e.device_entry_id.length > 0 &&
      isFiniteNumber(e.slot_start) &&
      (e.slot_end === undefined || e.slot_end === null || isFiniteNumber(e.slot_end)) &&
      typeof e.entry_description === "string" &&
      isFiniteNumber(e.submitted_at);
    if (!valid) return `entry ${index} is malformed`;
    entries.push({
      device_entry_id: e.device_entry_id!,
      slot_start: e.slot_start!,
      slot_end: e.slot_end ?? null,
      entry_description: e.entry_description!,
      submitted_at: e.submitted_at!,
    });
  }
  return entries;
}

/** Postgres rejects an upsert that touches the same row twice, so keep only the newest entry per id. */
export function newestPerId(entries: RemoteTimeEntry[]): RemoteTimeEntry[] {
  const byId = new Map<string, RemoteTimeEntry>();
  for (const entry of entries) {
    const existing = byId.get(entry.device_entry_id);
    if (!existing || entry.submitted_at > existing.submitted_at) {
      byId.set(entry.device_entry_id, entry);
    }
  }
  return [...byId.values()];
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const sql = neon(env.DATABASE_URL);
    try {
      return await handle(request, env, (text, params) => sql.query(text, params));
    } catch (error) {
      console.error("sync-api database error", error);
      return json({ error: "database error" }, 502);
    }
  },
} satisfies ExportedHandler<Env>;
