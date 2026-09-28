import { describe, expect, it, vi } from "vitest";
import { handle, MAX_BATCH, SELECT_SQL, UPSERT_SQL, type Env, type Query, type RemoteTimeEntry } from "./index";

const env: Env = { DATABASE_URL: "postgres://unused", APP_TOKEN: "secret-token" };

function request(method: string, path = "/entries", opts: { token?: string | null; body?: unknown } = {}) {
  const headers: Record<string, string> = {};
  const token = opts.token === undefined ? env.APP_TOKEN : opts.token;
  if (token !== null) headers.authorization = `Bearer ${token}`;
  return new Request(`https://sync.example${path}`, {
    method,
    headers,
    body: opts.body === undefined ? undefined : typeof opts.body === "string" ? opts.body : JSON.stringify(opts.body),
  });
}

function entry(overrides: Partial<RemoteTimeEntry> = {}): RemoteTimeEntry {
  return {
    device_entry_id: "mac-1",
    slot_start: 1_790_000_000,
    slot_end: 1_790_001_800,
    entry_description: "deep work",
    submitted_at: 1_790_001_900,
    ...overrides,
  };
}

describe("auth", () => {
  it("rejects a missing token", async () => {
    const query = vi.fn<Query>();
    const res = await handle(request("GET", "/entries", { token: null }), env, query);
    expect(res.status).toBe(401);
    expect(query).not.toHaveBeenCalled();
  });

  it("rejects a wrong token", async () => {
    const res = await handle(request("GET", "/entries", { token: "secret-tokeX" }), env, vi.fn<Query>());
    expect(res.status).toBe(401);
  });

  it("rejects everything when APP_TOKEN is unset", async () => {
    const res = await handle(request("GET", "/entries", { token: "" }), { ...env, APP_TOKEN: "" }, vi.fn<Query>());
    expect(res.status).toBe(401);
  });

  it("checks auth before routing", async () => {
    const res = await handle(request("GET", "/secret-path", { token: null }), env, vi.fn<Query>());
    expect(res.status).toBe(401);
  });
});

describe("GET /entries", () => {
  it("returns every row from the select", async () => {
    const rows = [entry(), entry({ device_entry_id: "phone-1" })];
    const query = vi.fn<Query>().mockResolvedValue(rows);
    const res = await handle(request("GET"), env, query);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual(rows);
    expect(query).toHaveBeenCalledWith(SELECT_SQL, []);
  });
});

describe("POST /entries", () => {
  it("upserts the batch as one JSON parameter and reports affected rows", async () => {
    const batch = [entry(), entry({ device_entry_id: "mac-2", slot_start: 1_790_001_800 })];
    const query = vi.fn<Query>().mockResolvedValue([{ device_entry_id: "mac-1" }, { device_entry_id: "mac-2" }]);
    const res = await handle(request("POST", "/entries", { body: batch }), env, query);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ upserted: 2 });
    expect(query).toHaveBeenCalledWith(UPSERT_SQL, [JSON.stringify(batch)]);
  });

  it("keeps only the newest entry when an id repeats in one batch", async () => {
    const older = entry({ submitted_at: 100, entry_description: "old" });
    const newer = entry({ submitted_at: 200, entry_description: "new" });
    const query = vi.fn<Query>().mockResolvedValue([{ device_entry_id: "mac-1" }]);
    await handle(request("POST", "/entries", { body: [newer, older] }), env, query);
    expect(JSON.parse(query.mock.calls[0][1][0] as string)).toEqual([newer]);
  });

  it("guards the conflict update so older writes never win", () => {
    expect(UPSERT_SQL).toMatch(/on conflict \(device_entry_id\) do update/);
    expect(UPSERT_SQL).toMatch(/where excluded\.submitted_at > time_entries\.submitted_at/);
  });

  it("accepts a missing slot_end", async () => {
    const { slot_end: _, ...withoutEnd } = entry();
    const query = vi.fn<Query>().mockResolvedValue([{ device_entry_id: "mac-1" }]);
    const res = await handle(request("POST", "/entries", { body: [withoutEnd] }), env, query);
    expect(res.status).toBe(200);
    expect(JSON.parse(query.mock.calls[0][1][0] as string)[0].slot_end).toBeNull();
  });

  it("skips the database for an empty batch", async () => {
    const query = vi.fn<Query>();
    const res = await handle(request("POST", "/entries", { body: [] }), env, query);
    expect(await res.json()).toEqual({ upserted: 0 });
    expect(query).not.toHaveBeenCalled();
  });

  it.each([
    ["not JSON", "{nope"],
    ["not an array", { device_entry_id: "x" }],
    ["missing id", [{ ...entry(), device_entry_id: "" }]],
    ["string timestamp", [{ ...entry(), submitted_at: "1790001900" }]],
    ["non-finite slot", [{ ...entry(), slot_start: null }]],
    ["too many", Array.from({ length: MAX_BATCH + 1 }, (_, i) => entry({ device_entry_id: `id-${i}` }))],
  ])("rejects a malformed body (%s)", async (_name, body) => {
    const query = vi.fn<Query>();
    const res = await handle(request("POST", "/entries", { body }), env, query);
    expect(res.status).toBe(400);
    expect(query).not.toHaveBeenCalled();
  });
});

describe("routing", () => {
  it("404s unknown paths", async () => {
    expect((await handle(request("GET", "/other"), env, vi.fn<Query>())).status).toBe(404);
  });

  it("405s other methods", async () => {
    expect((await handle(request("DELETE"), env, vi.fn<Query>())).status).toBe(405);
  });
});
