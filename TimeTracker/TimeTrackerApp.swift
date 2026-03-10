//
//  TimeTrackerApp.swift
//  TimeTracker
//
//  Created by Eugene Chan on 3/9/26.
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(
    subsystem: "com.eugenechan.TimeTracker", category: "App"
)

@main
struct TimeTrackerApp: App {
    @StateObject private var notificationManager = NotificationManager.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TimeEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        #if os(macOS)
        MenuBarExtra("TimeTracker", systemImage: "clock.fill") {
            ContentView()
                .modelContainer(sharedModelContainer)
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .modelContainer(sharedModelContainer)
        #endif
    }

    init() {
        NotificationManager.shared.setup()
        Task {
            let granted = await NotificationManager.shared.requestAuthorization()
            if granted {
                await NotificationManager.shared.scheduleNotifications(for: .now)
            }
        }
        // Start Convex real-time sync
        ConvexSyncService.shared.start(container: sharedModelContainer)
    }

    #if os(iOS)
    private func handleDeepLink(_ url: URL) {
        // Handle timetracker://slot/{timestamp}
        guard url.scheme == "timetracker",
              url.host == "slot",
              let timestampStr = url.pathComponents.dropFirst().first,
              let timestamp = TimeInterval(timestampStr) else {
            logger.warning("Invalid deep link: \(url.absoluteString)")
            return
        }

        let slotStartDate = Date(timeIntervalSince1970: timestamp)
        let slots = SlotManager.slotsForDate(slotStartDate)
        if let slot = slots.first(where: { abs($0.start.timeIntervalSince(slotStartDate)) < 1 }) {
            logger.info("Deep link navigating to slot: \(slot.label)")
            notificationManager.pendingSlot = slot
        }
    }
    #endif
}
