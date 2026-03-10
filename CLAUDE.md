# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Native iOS + macOS time-tracking app. Prompts users every 30 minutes (7:30 AM–12:00 AM) to record what they were doing. Runs as a **menu bar app on macOS** (no Dock icon) and a standard app on iOS. Syncs entries across devices via CloudKit.

## Build / Test / Run

```bash
# Build (or use Xcode: Cmd+B / Cmd+R / Cmd+U)
xcodebuild -scheme TimeTracker -destination 'platform=macOS' -allowProvisioningUpdates
xcodebuild -scheme TimeTracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run tests
xcodebuild test -scheme TimeTracker -destination 'platform=macOS'
xcodebuild test -scheme TimeTracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

CloudKit requires `-allowProvisioningUpdates` for CLI builds. Xcode (Cmd+R) handles provisioning automatically.

## Architecture

**Platforms**: iOS 26.2+, macOS 15.7+ | **Frameworks**: SwiftUI, SwiftData, CloudKit, UserNotifications

- **Models/TimeEntry.swift** — `@Model` with CloudKit sync (`cloudKitDatabase: .automatic`). All properties need default values for CloudKit compatibility. No `#Unique` constraints (incompatible with CloudKit).
- **Services/SlotManager.swift** — Stateless enum generating 33 daily time slots. Pure functions, no state.
- **Services/NotificationManager.swift** — `@MainActor` singleton. Schedules 33 `UNNotificationRequest`s per day at slot end times. Handles notification taps by setting `@Published var pendingSlot`, which drives navigation. On macOS, also opens the MenuBarExtra popover programmatically via `MenuBarExtraWindow.makeKeyAndOrderFront`.
- **Views/ContentView.swift** — Platform wrapper. iOS uses `NavigationStack`; macOS uses inline `VStack` with back button, bound to `NotificationManager.pendingSlot` (not `@State`, which resets when MenuBarExtra recreates its view).
- **Views/TimelineView.swift** — Main slot list with `@Query` for SwiftData entries. Date navigation, auto-scrolls to closest open slot.
- **Views/SlotEditView.swift** — Text entry for a slot. On macOS, save clears `pendingSlot` instead of calling `dismiss()` (which closes the entire popover).
- **Views/GlassModifiers.swift** — Adaptive glass effects: `.glassEffect()` on macOS/iOS 26+, solid color fallback on older OS. Past slots use `Color.white.opacity(0.12)`, upcoming use `0.04`.

## Key Patterns

- **Logging**: Always use `os_log` (Logger) with `subsystem: "com.eugenechan.TimeTracker"`, never `print()`.
- **Platform branching**: `#if os(macOS)` / `#else` throughout. macOS is MenuBarExtra, iOS is WindowGroup.
- **Notification scheduling**: Only schedules future slots (`guard slot.end > now`). Scheduling past slots floods the system and causes throttling.
- **Testing**: Unit tests use Swift Testing (`@Test` macros). UI tests use XCTest with `accessibilityIdentifier`.
- **Entitlements**: CloudKit, push notifications, network client (for sandbox). macOS `LSUIElement = YES` hides Dock icon.

## Gotchas

- `@State` in MenuBarExtra content views resets on popover dismiss/reshow — use singleton state instead.
- CloudKit + SwiftData requires all `@Model` properties to have default values and no `#Unique` constraints.
- macOS notification icon caching is aggressive — may need `killall NotificationCenter` + clean build to update.
