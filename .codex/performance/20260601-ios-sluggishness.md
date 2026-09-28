# iOS Performance Investigation: sluggishness

## Symptom

The iOS app feels sluggish during regular use, especially around launch/foreground refreshes, timeline rendering, and sync-driven updates.

## Classification

- Category: hang / swiftui / cpu
- Device scope: iOS, exact device unknown
- Build scope: local Debug baseline

## Baseline

- Metric: build health plus static hot-path audit
- Current value: pre-change `flowdeck build` passed; no device trace supplied yet
- Target value: remove deterministic main-thread work from frequent UI paths
- Measurement surface: FlowDeck build/run, code-level hot-path review

## Reproduction

1. Launch or foreground the app.
2. Let notification scheduling, Convex sync, and timeline refresh run.
3. Navigate the timeline or open a slot.

## Hypotheses

- [x] Foregrounding reschedules up to 64 local notifications every time.
- [x] Timeline fetches every stored entry and rebuilds slot indexes repeatedly.
- [x] Convex subscription updates invalidate SwiftUI views even when no local data changed.
- [x] Slot row labels allocate a new `DateFormatter` during rendering.
- [x] UI tests trigger SpringBoard notification UI and iOS 26.2 simulator FrontBoard crashes.

## Before / After

- Before: pre-change build passed.
- After: post-change build passed; unit tests passed; app launched successfully on iPhone 17 Pro simulator.
- SpringBoard finding: recent reports are `SpringBoard` `EXC_BREAKPOINT` crashes in `FBSDisplayMonitor` / `FBDisplayManager` inside iOS 26.2 UI-test simulator clones, not TimeTracker process crashes.

## Regression Protection

- [ ] Performance test added or updated
- [x] Build verification run
- [x] Unit tests run
- [x] Simulator launch checked
- [x] UI-test notification prompt removed
