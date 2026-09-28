# Bug Report: macOS Notification Opens Edit View with Stale Data

## Reported Behavior

1. **Suggestions missing in SlotEditView**: When tapping a macOS notification to open the edit view for a time slot, auto-suggest (today's other entries) is not populated.
2. **Timeline entries missing after navigating back**: After submitting or pressing Back from the edit view, the TimelineView shows no entries for the current day — even entries that were previously filled in.
3. **Workaround**: Closing and reopening the MenuBarExtra popover (clicking the menu bar icon twice) causes entries to appear correctly.

## Reproduction Steps (Automated via CLI)

1. Build and launch the Debug macOS app via `xcodebuildmcp macos build-and-run`
2. Ensure entries exist for today (fill in some slots manually or via earlier testing)
3. Open Notification Center (click Clock in menu bar via AppleScript)
4. Click the TimeTracker notification via `cliclick` at the notification group coordinates
5. Observe: Edit view opens (confirmed via screenshot)
6. Click Back button via `cliclick` at popover coordinates
7. Observe: Timeline view state

### Actual Results (Pre-Fix)
- Step 5: Edit view opens. Suggestions sometimes empty (todayDescriptions = 0) depending on ModelContext freshness.
- Step 7: Timeline shows empty slots — entries not visible until popover is closed and reopened.

### Actual Results (Post-Fix)
- Step 5: Edit view opens. `todayDescriptions=11` — suggestions loaded correctly. `existingEntry=true` for pre-filled slots.
- Step 7: Timeline shows ALL entries immediately after clicking Back. No need to reopen popover.

## Root Cause Analysis

### Architecture overview
- All views create standalone `ModelContext(TimeTrackerApp.sharedModelContainer)` for reads/writes
- No views use `@Query` or `@Environment(\.modelContext)` (the SwiftUI-managed context)
- `TimelineView` stores entries in `@State private var entries: [TimeEntry]`
- Navigation between edit/timeline is an `if/else` on `pendingSlot` in `macOSContentView`

### Root cause: MenuBarExtra view lifecycle + missing refresh trigger

**Problem 2 — Timeline empty after back** (confirmed as primary issue): When `pendingSlot` is set to `nil`, SwiftUI swaps from the `if` branch (SlotEditView) to `else` branch (TimelineView). The new `TimelineView.init()` eagerly fetches with a fresh `ModelContext`. However:
- `onAppear` doesn't reliably fire in MenuBarExtra when switching if/else branches (known issue, noted in code comments)
- The existing refresh triggers (`onChange(of: selectedDate)`, `onChange(of: syncService.refreshID)`, `onChange(of: scenePhase)`) don't cover the edit→timeline transition
- The `refreshID` change IS dispatched after save, but the TimelineView may not be mounted yet when it fires

**Problem 1 — Suggestions missing**: Less reliably reproduced. In testing, `todayDescriptions=11` loaded correctly. This issue may be intermittent and related to specific timing conditions where the ModelContext cache is stale.

## Fix Applied

**TimelineView.swift** — Added `onChange(of: notificationManager.pendingSlot)` observer (macOS only):
```swift
@ObservedObject private var notificationManager = NotificationManager.shared

// In body:
#if os(macOS)
.onChange(of: notificationManager.pendingSlot) { _, newSlot in
    if newSlot == nil {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            fetchEntries()
        }
    }
}
#endif
```

This ensures `fetchEntries()` fires when the user navigates back from edit to timeline, regardless of whether `onAppear` fires.

**SlotEditView.swift** — Added `os_log` logger for diagnostics (no behavioral change).

## Desired Outcome (Verified)

1. Tapping a notification opens the edit view with auto-suggest populated from today's existing entries — **VERIFIED** (11 suggestions loaded)
2. After pressing Back, the timeline view immediately shows ALL entries for the current day — **VERIFIED** (entries visible immediately)
3. No need to close/reopen the popover to see correct data — **VERIFIED**

---

## Resolution — 2026-09-28: the fix above was never installed

The user reported the bug again ("persistent issue": notification → Submit → timeline shows no
entries until the popover is reopened). The code was not the problem this time.

### Root cause
1. **Stale install.** `/Applications/TimeTracker.app` was a Debug build from **2026-03-12**
   (Convex sync, `ConvexSyncService` symbols in `TimeTracker.debug.dylib`, no Supabase). The fix
   above was verified against a DerivedData build and never copied into `/Applications`.
2. **The Mac target could not build anyway.** A local `fastlane ios deploy_testflight` run
   (2026-07-29) left the target on `CODE_SIGN_STYLE = Manual` + `Apple Distribution` +
   `match AppStore com.eugenechan.TimeTracker` (an iOS-only profile) via
   `update_code_signing_settings`. Every macOS build failed with "profile has platforms visionOS,
   watchOS, and iOS". Reverted the app target to `Automatic`; the lane re-applies manual signing
   itself on each deploy.

### What changed
- `project.pbxproj`: the app target's signing is back to `Automatic` (matches `HEAD`).
- `scripts/install-mac.sh`: FlowDeck build → replace `/Applications/TimeTracker.app` → lsregister →
  relaunch → assert that the running binary is the installed one. This is the only supported install path.
- `TimeTrackerApp.swift`: DEBUG-only `--debug-test-notification` launch flag (schedules the existing
  `scheduleTestNotification()`), so the notification-tap flow can be reproduced on demand.
- Local store and old bundle backed up to `build/backup-20260928/` (gitignored) before the swap.

### Verification (installed app, real notification, no cursor takeover)
Harness: `.claude/evidence/notification-submit-20260928/repro.sh`. It launches the installed app
with the flag, opens and closes the popover once (as in all-day use), presses the real
notification banner through the Notification Center accessibility tree
(`AXNotificationCenterAlert`), types into `entryTextField`, presses Update, and dumps the timeline.

| Run | Before | Typed | Timeline right after Update | Store after |
|---|---|---|---|---|
| run3 | `<entry B>` | `<entry B> [verify-freshness]` (truncated to 20 chars by axdriver) | `<entry B, truncated>` | `<entry B, truncated>` |
| run5 | `<entry B, truncated>` | `<entry B>` | `<entry B>` | `<entry B>` |

Both runs show the just-saved value, with the other entry (8:30) intact, and no reopen is
needed. The user's data ends where it started.

### Found along the way (not fixed here)
- **Popover does not open on a notification tap if it has never been opened since launch.**
  `openMenuBarPopover()` looks for an existing `MenuBarExtraWindow`, and SwiftUI creates that window
  lazily on the first icon click. The tap sets `pendingSlot`, so the next manual open shows the edit
  view. **Fixed 2026-09-28** (see below).
- **Supabase project `idtwydfgngyxfxkqenle` is INACTIVE (paused); its host is NXDOMAIN.** All
  sync calls fail. Resolved the same day by a parallel session: sync moved to Neon behind a Cloudflare Worker (`docs/sync.md`). Re-verified the notification → Update flow on that build (11:16 install): the timeline showed 8:30, 9:00 and 10:30 immediately.

---

## Follow-up — 2026-09-28: popover now opens on the first notification after launch

**Fix** (`NotificationManager.openMenuBarPopover`): if the `MenuBarExtraWindow` exists, show it
with `makeKeyAndOrderFront`, as before. If not, find the status item's `NSStatusBarButton`
(inside `NSStatusBarWindow`) and `performClick` it twice, open then shut, so SwiftUI creates the
window. Then, once SwiftUI's close finishes, show it with `makeKeyAndOrderFront`.

**Why not just click it open:** a popover opened through SwiftUI's toggle (target
`SwiftUI.WindowMenuBarExtraBehavior`, action `toggleWindow:`) closed again 0.5–1.5s later in 4 of
6 runs, around when the notification banner was dismissed. It happened even while the app stayed
active and frontmost. A window shown directly stayed up in every run. `accessibilityPerformPress()`
on the button does nothing (returns false).

**Verification** (harness: `.claude/evidence/popover-first-notification-20260928/popover.sh`,
three modes; it re-submits the existing 11:00 text, so no data changes):

| Mode | Code path | Result |
|---|---|---|
| fresh (never opened since launch) | create via clicks, then show | Popover opened on the 11:00 edit view and stayed up even when iTerm took focus back. Update → timeline shows 8:30, 9:00, 10:30, 11:00 |
| closed (opened once, then closed) | existing window | pass: edit view, then Update → full timeline |
| open (popover open at tap) | existing window | pass: edit view, then Update → full timeline |

Limits: one fully delivered fresh-mode run on the final code. Two more fresh runs never got as far
as the app: macOS delayed the test banners past the harness's 10s window, likely throttling after
~15 test notifications in 10 minutes. I stopped there because the user was actively using the Mac.
