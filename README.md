# TimeTracker

A native iOS and macOS app that helps you track how you spend your time throughout the day.

## How It Works

TimeTracker divides your day into **30-minute slots** from 7:30 AM to midnight (33 slots total). At the end of each slot, you receive a notification asking "What were you doing?" — tap it to log your activity.

### Features

- **Automatic reminders** — notifications fire at the end of every 30-minute slot
- **Menu bar app on macOS** — lives in your menu bar, no Dock icon clutter
- **Full-screen app on iOS** — standard iPhone app experience
- **CloudKit sync** — entries sync automatically across all your devices
- **Date navigation** — browse past days to review or fill in missed slots
- **Auto-scroll** — opens to the closest unfilled slot so you can log quickly

### Slot States

- **Filled** (green checkmark) — you've logged what you were doing
- **Past unfilled** — tap to fill in retroactively
- **Upcoming** — greyed out, not yet tappable

## Requirements

- macOS 15.7+ / iOS 26.2+
- Xcode 26+
- Apple Developer account (for CloudKit)

## Setup

1. Open `TimeTracker.xcodeproj` in Xcode
2. Select your development team under Signing & Capabilities
3. Ensure iCloud (CloudKit) and Push Notifications capabilities are enabled
4. Build and run (Cmd+R)

On macOS, the app appears as a clock icon in your menu bar. On iOS, it launches as a regular app.
