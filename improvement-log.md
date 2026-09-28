# Improvement Log

## Tracker

- [x] 2026-03-18 — FlowDeck used despite no license, wasting time on failed commands -> remember to skip FlowDeck when license is missing
- [x] 2026-03-18 — Used xcodebuildmcp-cli skill instead of xcodebuildmcp skill when user requested /xcodebuildmcp -> use correct skill name
- [x] 2026-03-18 — No improvement-log.md created at session start -> added Session Start Checklist to global CLAUDE.md
- [x] 2026-03-18 — No MEMORY.md or memory files exist for this project -> initialized memory system
- [x] 2026-03-18 — No general solution for clicking macOS notifications in testing -> created /macos-test skill with cliclick-based workflow
- [x] 2026-03-18 — Added excessive debug code to app instead of building reusable tooling -> corrected approach: reverted debug code, created skill instead
- [ ] 2026-03-18 — Notification stale data bug: timeline empty after back navigation -> fix applied (onChange pendingSlot), needs user verification in production use

## Log

### 2026-03-18 — FlowDeck used despite no license
**What happened:** Invoked `/flowdeck` skill which requires a paid license. The command failed with `NO_LICENSE` error, wasting a round-trip.
**Root cause:** Did not check license status before invoking FlowDeck. User then had to redirect to xcodebuildmcp.
**Fix:** Save feedback memory: skip FlowDeck for this user (no license), default to xcodebuildmcp for all Apple platform tasks.
**Status:** Addressed (feedback memory saved)

### 2026-03-18 — Wrong xcodebuildmcp skill invoked
**What happened:** User said "use /xcodebuildmcp". I invoked `xcodebuildmcp-cli` skill first, which the user rejected, then had to be told again.
**Root cause:** Two similarly named skills exist (`xcodebuildmcp` and `xcodebuildmcp-cli`). Chose the wrong one.
**Fix:** Save feedback memory: when user says `/xcodebuildmcp`, use the `xcodebuildmcp` skill (not `xcodebuildmcp-cli`).
**Status:** Addressed (feedback memory saved)

### 2026-03-18 — No improvement-log.md at session start
**What happened:** User had to ask why there was no improvement log. It should have been created proactively.
**Root cause:** First session in this project, no prior improvement log existed, and I didn't create one proactively.
**Fix:** Always check for improvement-log.md at the start of meaningful sessions. Create if missing.
**Status:** Addressed (this file)

### 2026-03-18 — Added excessive debug code instead of reusable tooling
**What happened:** When trying to reproduce the notification bug, I added auto-trigger code, distributed notification listeners, and debug buttons to the app source code. User correctly pushed back.
**Root cause:** Solving an infrastructure problem (clicking notifications) inside the app instead of building external tooling.
**Fix:** Reverted all debug code. Created `/macos-test` skill with `click_notification.sh` script using `cliclick` for real mouse clicks on macOS notifications.
**Status:** Addressed

### 2026-03-18 — Created /macos-test skill
**What happened:** No existing skill for testing native macOS apps or interacting with Notification Center.
**Root cause:** Gap in the skill library for macOS-specific testing workflows.
**Fix:** Created `~/.claude/skills/macos-test/` with SKILL.md (full docs) and `click_notification.sh` (reusable notification click script).
**Status:** Addressed

### 2026-03-18 — Notification stale data bug fixed
**What happened:** TimelineView showed empty entries after navigating back from SlotEditView opened via notification tap.
**Root cause:** MenuBarExtra doesn't reliably fire `onAppear` when switching if/else branches. No refresh trigger existed for the edit→timeline transition.
**Fix:** Added `onChange(of: notificationManager.pendingSlot)` in TimelineView (macOS only) to trigger `fetchEntries()` when pendingSlot becomes nil.
**Status:** Fix applied, verified via automated test. Needs user confirmation in real usage.
