# Feature: Supabase Migration

## User Story

As the app owner, I want TimeTracker to sync time entries through Supabase instead of Convex so that iPhone and Mac data refresh reliably and the backend is easier to operate.

## User Flow

1. User enters or edits a time entry on iPhone or Mac.
2. The app saves the entry locally for immediate UI feedback.
3. The app upserts the entry to Supabase.
4. The other device receives the change through realtime or picks it up on explicit refresh/open.
5. Timeline and slot edit views read fresh local data after remote merges.

## Success Criteria

- [x] App no longer depends on Convex for time-entry sync.
- [x] Supabase table schema is documented and migration-ready.
- [x] Local SwiftData remains the offline/cache source used by the UI.
- [x] Remote upsert preserves current conflict behavior: latest `submittedAt` wins for the same device id or same slot.
- [x] Mac popover refresh can force a remote pull so phone entries show without quitting/reopening.
- [x] Build and relevant tests pass.

## Test Strategy

- Swift unit tests for sync merge conflict behavior where practical.
- Build verification through FlowDeck.
- Runtime verification still requires applying the Supabase migration to the remote database.

## Tests

- Existing `SlotManagerTests` must keep passing.
- Add focused tests if sync merge logic is extracted into a pure helper.

## Implementation Details

- Supabase Swift package: `https://github.com/supabase/supabase-swift.git`.
- Supabase project URL: `https://idtwydfgngyxfxkqenle.supabase.co`.
- Current Supabase docs say Swift uses `SupabaseClient(projectURL:key:)`, table calls through `.from(...).select()/upsert()`, and Postgres Changes require enabling the table in the `supabase_realtime` publication.
- Preserve existing unauthenticated shared-device behavior for this migration phase.
- Migrations live in `supabase/migrations/` and should be applied in filename order.

## Residual Risks

- Full remote runtime verification requires applying `supabase/migrations/0001_create_time_entries.sql` in Supabase.
- Production security should not ship as unrestricted anonymous CRUD unless that is an intentional private-only app decision.

## Bugs

- Mac MenuBarExtra can re-read stale SwiftData if realtime missed a phone update; migration must include an explicit remote pull on popover open/back.
