# Feature: neon-sync-migration

## User Story

As Eugene, I want entries I log on my Mac to show up on my iPhone (and vice versa) so that I have one timeline regardless of which device prompted me. The current backend (Supabase free project) paused itself and can't be restored without freeing a slot, so move sync to Neon (free plan: 100 projects, compute sleeps after 5 min idle and wakes on request, never needs a manual restore).

## User Flow

1. Eugene logs an entry on the Mac (menu bar popover, or notification tap).
2. The Mac saves locally, then uploads it to the sync API.
3. Eugene opens TimeTracker on the iPhone.
4. The iPhone pulls all entries, merges them, and the Mac's entry is shown in the timeline.
5. If an upload ever fails (offline, backend asleep/down), the next pull re-uploads anything the server is missing or has an older copy of.

## Architecture

```
iPhone app ─┐                      ┌─ Neon Postgres (project: timetracker, free)
            ├─ HTTPS + Bearer ──> Cloudflare Worker (sync-api) ─ SQL over HTTP
Mac app ────┘                      └─ secrets: DATABASE_URL, APP_TOKEN
```

- `GET  /entries` → all rows as a JSON array (same shape as the old Supabase rows).
- `POST /entries` → JSON array upsert on `device_entry_id`; an older `submitted_at` never overwrites a newer one.
- The app calls the API only on launch, popover open / app becoming active, and after a save. No polling — keeps Neon compute well inside 100 CU-hours/month.

## Success Criteria

- [x] SC1: Neon project `timetracker` exists on the free plan with a `time_entries` table matching the app's schema — **Verify by:** `psql "$DATABASE_URL" -c '\d time_entries'` shows the 5 columns + primary key.
- [x] SC2: The Worker rejects requests without the right token — **Verify by:** Worker unit test `rejects missing/wrong token`; live `curl` without token → 401.
- [x] SC3: `GET /entries` returns all rows as a JSON array matching `RemoteTimeEntry` — **Verify by:** Worker unit test; live `curl` → 200 + JSON array.
- [x] SC4: `POST /entries` upserts a batch and never lets an older write clobber a newer one — **Verify by:** Worker unit test on SQL + live round-trip: POST newer, POST older for same id, GET shows newer text.
- [x] SC5: The app has no Supabase dependency left — **Verify by:** `git grep -n "import Supabase"` → empty; `Package.resolved` has no `supabase-swift`; macOS and iOS builds succeed.
- [x] SC6: The app's pull + reconcile runs against the Worker, with request building and decoding covered by tests — **Verify by:** `SyncAPIClientTests` (stubbed URLProtocol) + `SupabaseSyncReconcileTests` renamed to cover `RemoteTimeEntry`.
- [x] SC7: Mac backfill — after installing the new Mac build, every local Mac entry is in Neon — **Verify by:** local SwiftData row count (sqlite3 on the store) == Neon `count(*)` for Mac ids; log line `Pushed N unsynced entries`.
- [x] SC8: An entry saved on the Mac shows up on iOS after the iOS app becomes active — **Verify by:** E2E on this session's iOS simulator pointed at the same Worker: save on Mac → launch sim app → entry text visible in timeline (screenshot).
- [x] SC9: No secret lands in the public repo — **Verify by:** `git check-ignore` on the secrets file; `git grep` for the token and connection string → empty.

## Platform & Stack

- **Platform:** iOS 26.2+ / macOS 15.7+ app; Cloudflare Worker backend
- **Language:** Swift; TypeScript (Worker)
- **Key frameworks:** SwiftUI, SwiftData, URLSession; `@neondatabase/serverless`, Wrangler, Vitest

## Steps to Verify

1. Worker: `cd sync-api && pnpm test`; `wrangler deploy`; curl probes for SC2–SC4.
2. App: FlowDeck build for macOS + iOS; unit tests (note: XCTest runner is currently wedged on this Mac, see improvement log; fall back to executing pure logic directly if it still hangs).
3. Mac: `scripts/install-mac.sh`, open popover, check logs + Neon count (SC7).
4. iOS sim: run app on session sim, confirm Mac entry visible (SC8).

## Implementation Phases

### Phase 1: Backend
- Scope: `sync-api/` Worker + schema + tests; Neon project + table; Worker deploy with secrets.
- Covers: SC1–SC4.
- Gate: Worker tests green; live curl probes recorded.

### Phase 2: App client
- Scope: replace `supabase-swift` with a URLSession client; rename `SupabaseTimeEntry` → `RemoteTimeEntry`; drop Realtime; gitignored secrets file + CI step.
- Covers: SC5, SC6, SC9.
- Gate: builds green for both platforms; client + reconcile tests pass.

### Phase 3: Rollout
- Scope: install Mac build; iOS sim E2E; TestFlight build for the iPhone.
- Covers: SC7, SC8.
- Gate: evidence recorded for both.

## Decision Log

- **Cloudflare Worker in front of Neon, not Neon's Data API.** The Data API needs Neon Auth to mint anonymous JWTs, and Neon discourages anonymous write grants. A Worker keeps the connection string server-side, uses plain HTTPS from the app, and lets us drop `supabase-swift` and its dependency tree. Cost: one more deployable (~80 lines).
- **No Realtime.** Neon has no realtime channel. The app already refreshes on launch, popover open, app-active and after save; that covers a 30-minute cadence. Polling was rejected because it would keep Neon compute awake 24/7 (0.25 CU × 720 h = 180 CU-h, above the 100 CU-h free allowance).
- **Migrate data via device backfill, not a Supabase export.** The reconcile push uploads every local entry the server lacks, so an empty Neon table fills itself from each device. The Mac ran a Convex-era build until 2026-09-28 09:48, so Supabase only ever held iPhone entries, which the iPhone still has locally. The paused Supabase project keeps a restorable backup for 90 days as a safety net.
- **Token in a gitignored Swift file, written from a GitHub secret in CI.** The repo is public, so a checked-in token would expose every entry to anyone.
- **Neon region `aws-ap-southeast-1` (Singapore)**, closest to Eugene (UTC+8).

## Verification Evidence

| SC | Status | Command / action | Observed |
|---|---|---|---|
| SC1 | pass | `neonctl projects create --name timetracker --region-id aws-ap-southeast-1` (personal org `org-mute-unit-15777333`, free); `psql -f schema.sql`; `\d time_entries` | Project `orange-scene-05465142`, Postgres 18. Table has the 5 columns, PK on `device_entry_id`, index on `slot_start`. |
| SC2–SC4 (live) | pass | `wrangler deploy` → `https://timetracker-sync.<subdomain>.workers.dev`; secrets `APP_TOKEN`, `DATABASE_URL` set via stdin; curl probes | No token → 401; wrong token → 401; GET → 200 `[]`; POST newer → `{"upserted":1}`; POST older same id → `{"upserted":0}` and GET still shows "newer"; null `slot_end` stored as `slot_start+1800`. Probe rows deleted afterwards (0 rows left). |
| SC7 | pass | Baseline: Mac store 635 rows / 619 distinct ids / 616 slots (2026-03-10 → 2026-09-28). `scripts/install-mac.sh` (built 11:16:21). Log: `11:16:24 Pushed 635 unsynced entries`. Strict diff local-newest-per-id vs Neon | Neon 619 rows / 616 slots, same range. Missing 0, text mismatch 0, timestamp mismatch 0, extra 0. The 16 extra local rows are duplicate-id copies (14 groups); Worker keeps newest per id. |
| SC8 | pass | `flowdeck run` on session sim (fresh, no local data) → screenshot today | Shows all three of today's Mac entries: 8:30 "<entry A>", 9:00 "<entry B>", 10:30 "<entry C>". Evidence: `.claude/feature/evidence/sc8-ios-timeline-mac-entries.png`. Reverse direction (iOS→Mac) not exercised to avoid writing test data into the production timeline; it uses the same push/reconcile path verified on the Mac. |
| SC8 (Mac UI save path) | pass | Parallel session: notification tap → Update on the 10:30 slot in the installed 11:16 build (same text). Then `psql` on Neon | Timeline showed 8:30/9:00/10:30 right after submit (no view regression). Neon 10:30 row `submitted_at` = 11:20:45 HKT (after install), text "<entry C>", total rows still 619, so it updated in place. |
| SC2–SC4 (unit half) | pass | `cd sync-api && pnpm test` | 18/18 pass: 401 on missing/wrong/unset token and before routing; GET returns select rows; POST sends one JSON param, dedupes ids keeping newest, 400 on 6 malformed bodies, empty batch skips DB; 404/405. `pnpm typecheck` clean; `wrangler deploy --dry-run` bundles 54 KiB gzip. |
| SC5 | build half pass | `git grep 'import Supabase'` → 0; `grep -rli supabase` over app, tests, pbxproj → 0; Package.resolved removed (no packages left); FlowDeck macOS "Test Build Succeeded"; FlowDeck iOS sim build exit 0 | Supabase fully removed; both platforms compile incl. test target. |
| SC6 | pass (direct execution) | XCTest runner hangs on this Mac (see Bugs). Compiled real `SyncAPIClient.swift` + `entriesNeedingPush` extracted from `SyncService.swift` + the test file's `StubURLProtocol` with `swiftc`, ran the same cases | 15/15 PASS (6 reconcile, 9 client: method, URL, bearer, snake_case decode incl. null slot_end, POST body/content-type, empty upsert no request, 401 → `badStatus(401)`). |
| SC9 | pass | `git check-ignore` on `SyncSecrets.swift` and `sync-api/.dev.vars`; `git grep --untracked "$APP_TOKEN"` | Both ignored; token found in 0 non-ignored files. |

## Bugs

- **XCTest runner wedged on this Mac (environment, not code).** `test-without-building` never launches a test host on "My Mac" or on the slim session simulator; hangs at 0% CPU until timeout. Reproduced by the parallel session too. Tried: waiting out another session's run, separate DerivedData, `-disableAutomaticPackageResolution`, iOS sim, quitting the installed same-bundle-id app. Open hypotheses: slim sims lack the XCTest daemons; a wedged `testmanagerd`/DTServiceHub on macOS. Worked around with direct execution (SC6). Needs a look when no other session is testing.

## Independent Audit

**Verdict: PASS** (verification-auditor, 11:41). Report: `.claude/feature/evidence/audit/20260928-112023-verification-audit/evidence.md`. Caveats: SC6 was proven with a SwiftPM harness over the real sources rather than Xcode's test runner. SC7 holds per distinct id (Mac 636 rows / 620 ids → Neon 620), since Neon's primary key allows one row per id.

Defects the audit raised, and what happened to each:

| # | Defect | Fix | Verified by |
|---|---|---|---|
| 1 | The unit-test host (same bundle id) would run the legacy store migration and a live sync against the real Mac store and production | `TimeTrackerApp.isRunningTests` = UI-test flag OR `XCTestConfigurationFilePath`; it gates the migration, uses an in-memory store, and skips sync and notifications | Full-app build succeeded: parallel session's `install-mac.sh` at 11:56:02 (6 builds since 11:49, all green). `nm` on the installed `TimeTracker.debug.dylib` shows 6 `isRunningTests` and 5 `pushBatchSize` symbols. Neon 620 rows, 0 sync errors in the Mac log since 11:49 |
| 2 | Catch-up push was one request; >5000 pending would fail forever | `SyncService.batches(of:size:)`, 1000 per request | `batchesSplitWithoutLosingOrDuplicating`, `largeCatchUpIsSplitIntoBatches` (2500 → [1000,1000,500]) |
| 3 | A fresh device inserted two local rows when the server had two rows for one slot | Merge registers each insert in `localBySlotStart` | `freshDeviceKeepsOneRowPerSlotWhenServerHasTwo`, which fails without the fix (`local.count → 2`) and passes with it |
| 4 | Evidence screenshots with real entries were under an un-ignored `.claude/` in a public repo | `.gitignore`: `.claude/feature/evidence/`, `.claude/evidence/` | `git check-ignore -v` |
| 5 | The shared token ships inside the app binary | By design (single-user app); rotation steps in `docs/sync.md` | n/a |

Harness run after fixes: `swift test` → 18/18 pass (SyncReconcileTests 8, SyncAPIClientTests 4, SyncCycleTests 2, auditor's AuditSyncCycleTests 4).

Existing duplicates: Neon holds 3 slots with two rows each (pre-existing data). The fix stops new local duplicates but doesn't collapse those rows on the server. The simulator already has local duplicates from before the fix.

## Follow-ups

- **CI TestFlight builds need `SyncSecrets.swift`.** The shared `testflight-deploy` workflow template has no per-app pre-build hook, so a CI run would fail to compile. Local `fastlane ios deploy_testflight` works. Fix belongs in the template (e.g. run `scripts/ci-prebuild.sh` if present, with repo secrets passed through), then `scaffold sync --all`.
