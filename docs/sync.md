# Sync

How TimeTracker keeps entries consistent between the Mac and the iPhone.

## Shape

```
iPhone app ─┐                          ┌─ Neon Postgres  (project "timetracker", free plan)
            ├─ HTTPS, Bearer token ──> Cloudflare Worker "timetracker-sync"  (sync-api/)
Mac app ────┘                          └─ secrets: DATABASE_URL, APP_TOKEN
```

Each device keeps a full local copy in SwiftData. The server holds the union of all devices' entries in one table, `time_entries` (`sync-api/schema.sql`). Times are Unix epoch seconds.

## API

Both routes need `Authorization: Bearer <APP_TOKEN>`; anything else gets 401 before routing.

| Route | Behaviour |
|---|---|
| `GET /entries` | Every row, ordered by `slot_start`. |
| `POST /entries` | JSON array, up to 5000 rows. Upserts on `device_entry_id`; a row only overwrites the stored one if its `submitted_at` is newer. Duplicate ids in one batch keep the newest. Returns `{"upserted": n}`. |

## When a device syncs

There is no push channel. A device syncs:

- on launch (`SyncService.start`)
- when the macOS popover opens / the iOS app becomes active (`refreshFromRemote`)
- right after a save (`pushEntry`, fast path)

`refreshFromRemote` does three things in order:

1. **Pull** every row.
2. **Merge** into SwiftData: match by id, else by slot start; the newer `submitted_at` wins.
3. **Reconcile**: upload every local entry the server lacks or holds an older copy of (`SyncService.entriesNeedingPush`, 1 ms tolerance for Date/double round-trips), in batches of 1000 (`SyncService.pushBatchSize`; the Worker caps a request at 5000).

Step 3 is what makes sync self-healing: a failed `pushEntry`, an offline device, or a backend outage only delays an entry until the next refresh. It is also how data migrates to a new backend: point the apps at an empty table and each device backfills it.

The merge matches by id first, then by slot start, and registers each insert under its slot, so two server rows for one slot (written by different devices) become one local row holding the newer text.

The unit-test host never syncs: `TimeTrackerApp.isRunningTests` (UI-test flag or `XCTestConfigurationFilePath`) skips sync and the legacy store migration and uses an in-memory store, because on macOS the test host shares the app's bundle id and real store.

Polling is deliberately absent. Neon's free plan allows 100 CU-hours a month and suspends compute after 5 idle minutes; a poll loop would keep it awake around the clock (~180 CU-hours).

## Secrets

The repo is public, so nothing secret is committed:

| Secret | Where it lives |
|---|---|
| `DATABASE_URL` (Neon, pooled) | Worker secret (`wrangler secret put`) |
| `APP_TOKEN` | Worker secret, `sync-api/.dev.vars`, and the app's `TimeTracker/Services/SyncSecrets.swift` |
| Worker base URL | `sync-api/.dev.vars` and `SyncSecrets.swift` |

`SyncSecrets.swift` and `.dev.vars` are gitignored. Regenerate the Swift file with `scripts/write-sync-secrets.sh`. Rotating the token means updating the Worker secret, regenerating the Swift file, and shipping both app builds.

## Operating it

```bash
cd sync-api
pnpm install
pnpm test                      # handler unit tests (no database)
wrangler deploy                # deploy the Worker
psql "$DATABASE_URL" -f schema.sql   # once, on a new Neon project
```

Probe the live API:

```bash
set -a; . sync-api/.dev.vars; set +a
curl -s "$SYNC_API_BASE_URL/entries" -H "Authorization: Bearer $APP_TOKEN" | head -c 300
```

## History

CloudKit (v1) → Convex (March 2026) → Supabase (June 2026) → Neon + Worker (September 2026). Supabase was dropped because its free project paused itself and could not be restored without freeing one of the account's two free project slots.
