//
//  TimeTrackerApp.swift
//  TimeTracker
//
//  Created by Eugene Chan on 3/9/26.
//

import SwiftUI
import SwiftData

@main
struct TimeTrackerApp: App {
    @StateObject private var notificationManager = NotificationManager.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TimeEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
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
    }
}
