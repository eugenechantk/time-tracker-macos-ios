# TimeTracker - App Plan

## Overview

A multiplatform (macOS + iOS) time tracking app that prompts you every 30 minutes to record what you were doing. Runs from **7:30 AM to 12:00 AM (midnight)**, producing **33 time slots** per day.

- **macOS**: Menu bar (toolbar) app only. No Dock icon. All UI lives in a popover below the menu bar icon.
- **iOS**: Regular app with standard navigation.

---

## Data Model

### TimeEntry (SwiftData)

| Field | Type | Description |
|---|---|---|
| id | UUID | Unique identifier |
| slotStart | Date | Start of the 30-min slot (e.g. 7:30 AM) |
| entryDescription | String | What the user was doing |
| submittedAt | Date | When the entry was actually submitted |

- Unique constraint on `slotStart` - one entry per slot
- Synced via **CloudKit** (SwiftData's `ModelConfiguration` with `cloudKitDatabase: .automatic`)
- Requires CloudKit + Background Modes (remote notifications) capabilities

---

## Time Slots

- **Start**: 7:30 AM
- **End**: 12:00 AM (midnight)
- **Interval**: 30 minutes
- **Total**: 33 slots per day
- Slots: 7:30-8:00, 8:00-8:30, ..., 11:30-12:00

---

## Views

### 1. Timeline View

The main/home view. Shows all 33 slots for the selected day.

- Each row displays:
  - Time range (e.g. "7:30 AM - 8:00 AM")
  - Description if submitted, or an empty/placeholder state
  - Visual distinction between filled and empty slots
- Tapping any slot navigates to the Slot Edit View
- Slots with synced entries from other devices show normally (just like locally submitted entries)
- Ability to navigate to other days to view/edit past entries

### 2. Slot Edit View

Focused view for a single time slot.

- Shows the time range at the top
- Text field for the description
  - Pre-filled if an entry already exists (including entries synced from another device)
  - Empty if no entry yet
- Save button to submit/update the entry
- Back navigation to Timeline View

---

## Platform UI

### macOS - Menu Bar App

- Uses `MenuBarExtra` with `.menuBarExtraStyle(.window)` for a popover panel
- No Dock icon: set `LSUIElement = YES` in Info.plist (or `Application is agent (UIElement)`)
- No `WindowGroup` on macOS - everything lives inside the popover
- Both views (Timeline and Slot Edit) render inside the popover with in-popover navigation
- **Quit button** at the bottom of the popover (or in a settings/gear menu) to quit the app, since there's no Dock icon to right-click quit from

### iOS - Regular App

- Standard `WindowGroup` with `NavigationStack`
- Timeline View is the root
- Slot Edit View is pushed onto the navigation stack

---

## Notifications

### Schedule

- Notifications fire at the **end** of each slot (asking about the slot that just ended)
- First notification: **8:00 AM** (for the 7:30-8:00 slot)
- Last notification: **12:00 AM** (for the 11:30-12:00 slot)
- **33 notifications per day**
- Scheduled using `UNCalendarNotificationTrigger` (local notifications)
- Re-scheduled daily (on app launch or at end of day)

### Notification Content

- **Title**: "What were you doing?"
- **Body**: "7:30 AM - 8:00 AM" (the slot's time range)
- **userInfo**: carries `slotStart` as `TimeInterval` so the app knows which slot to open

### Notification Tap Behavior

- Tapping a notification (even hours later) opens the app to the **Slot Edit View** for that notification's slot
- The `slotStart` from `userInfo` determines which slot to show
- If the slot already has an entry (e.g. synced from another device), the text field shows the existing description
- No inline text input action - just tap to open the app

### Notification Timing Example

| Notification fires at | Asks about slot |
|---|---|
| 8:00 AM | 7:30 - 8:00 AM |
| 8:30 AM | 8:00 - 8:30 AM |
| 9:00 AM | 8:30 - 9:00 AM |
| ... | ... |
| 11:30 PM | 11:00 - 11:30 PM |
| 12:00 AM | 11:30 PM - 12:00 AM |

---

## Data Sync

- **CloudKit via SwiftData** - automatic iCloud sync with `ModelConfiguration(cloudKitDatabase: .automatic)`
- Syncs across Mac and iPhone seamlessly
- Conflict resolution: last-write-wins (CloudKit default) - acceptable for single-user app
- Requires iCloud entitlement and CloudKit container

---

## File Structure

```
TimeTracker/
  TimeTrackerApp.swift              -- App entry point
                                       #if os(macOS): MenuBarExtra (.window style)
                                       #if os(iOS): WindowGroup
  Models/
    TimeEntry.swift                 -- SwiftData model
  Services/
    SlotManager.swift               -- Generate time slots for a date, find slot for a
                                       given time, get current slot
    NotificationManager.swift       -- Request permissions, schedule daily notifications,
                                       handle notification tap (UNUserNotificationCenterDelegate),
                                       publish pendingSlot for deep-link navigation
  Views/
    TimelineView.swift              -- Day's slot list (shared across platforms)
    SlotEditView.swift              -- Submit/edit description for a single slot
    ContentView.swift               -- Platform wrapper: NavigationStack on iOS,
                                       simple nav in popover on macOS
```

---

## Design

- Use the `/ios-design-liquid-glass` skill during UI implementation to ensure the app follows Apple's current Liquid Glass design language (iOS/macOS 26+)
- Apply `.glassEffect()` and related APIs where appropriate for a native, modern look

---

## Implementation Order

1. **Data model** - `TimeEntry` with CloudKit-enabled `ModelContainer`
2. **SlotManager** - slot generation, current slot lookup
3. **Views** - TimelineView + SlotEditView (shared), ContentView (platform wrapper)
4. **App entry point** - `MenuBarExtra` on macOS, `WindowGroup` on iOS
5. **NotificationManager** - scheduling, tap handling, deep-link to Slot Edit View
6. **Xcode config** - CloudKit capability, background modes, `LSUIElement` for macOS

---

## Testing Strategy

### Unit Tests

- **SlotManager**: verify correct slot generation (33 slots, correct start/end times, edge cases around midnight)
- **TimeEntry**: model creation, uniqueness constraint on slotStart
- **NotificationManager**: verify correct number of notifications scheduled, correct userInfo payload, correct trigger times

### UI Tests

- **TimelineView**: all slots render, empty vs filled states display correctly, tapping a slot navigates to Slot Edit
- **SlotEditView**: text field pre-fills with existing description, saving creates/updates entry, back navigation works

### Device Testing

- **macOS (this Mac)**:
  - Build and run the macOS target directly on this Mac
  - Verify menu bar icon appears, popover opens/closes
  - Verify no Dock icon
  - Verify quit button works
  - Test notification delivery and tap-to-open behavior
  - Verify popover navigation between Timeline and Slot Edit views

- **iOS Simulator**:
  - Use FlowDeck / XcodeBuildMCP to build, run, and test on an iOS simulator
  - Verify full-screen timeline layout
  - Verify NavigationStack push/pop between Timeline and Slot Edit
  - Test notification permission prompt and notification delivery
  - Test tapping a notification opens the correct Slot Edit view
  - Use UI automation (screenshot, tap, type) to verify end-to-end flows

### CloudKit Sync Testing

- Requires two devices (or simulator + Mac) signed into the same iCloud account
- Submit an entry on one device, verify it appears on the other
- Edit an existing synced entry, verify the update propagates
- Note: CloudKit sync may not work on simulator; test sync behavior on physical devices if possible

---

## Xcode Project Capabilities Needed

- **iCloud** (CloudKit container)
- **Push Notifications** (for CloudKit sync)
- **Background Modes** - Remote notifications (for CloudKit sync triggers)
- **Info.plist (macOS)** - `LSUIElement = YES` (hides Dock icon)
