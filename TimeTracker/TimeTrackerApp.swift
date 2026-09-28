//
//  TimeTrackerApp.swift
//  TimeTracker
//
//  Created by Eugene Chan on 3/9/26.
//

import SwiftUI
import SwiftData
import os
#if canImport(SQLite3)
import SQLite3
#endif

private let logger = Logger(
    subsystem: "com.eugenechan.TimeTracker", category: "App"
)

@main
struct TimeTrackerApp: App {
    @StateObject private var notificationManager = NotificationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    static let isUITesting = CommandLine.arguments.contains("--uitesting")
    /// Also true when this process is the host for unit tests. The test host shares the app's
    /// bundle id (and on macOS its real on-disk store), so it must never migrate or sync.
    static let isRunningTests = isUITesting
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static let sharedModelContainer: ModelContainer = {
        if !isRunningTests {
            migrateLegacyPersistentStoreIfNeeded()
        }

        let schema = Schema([
            TimeEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isRunningTests
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    private static func migrateLegacyPersistentStoreIfNeeded() {
        #if canImport(SQLite3)
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }

        let storeURL = applicationSupportURL.appendingPathComponent("default.store")
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database else {
            logger.error("Failed to open SwiftData store for legacy migration")
            return
        }
        defer { sqlite3_close(database) }

        guard sqliteTableExists(database, tableName: "ZTIMEENTRY") else {
            return
        }

        var migrationStatements: [String] = []
        if !sqliteColumnExists(database, tableName: "ZTIMEENTRY", columnName: "ZSLOTEND") {
            migrationStatements.append("alter table ZTIMEENTRY add column ZSLOTEND timestamp")
        }
        migrationStatements.append(
            """
            update ZTIMEENTRY
            set ZSLOTEND = ZSLOTSTART + \(SlotManager.slotDurationMinutes * 60)
            where ZSLOTEND is null or ZSLOTEND <= ZSLOTSTART
            """
        )

        let migrationSQL = migrationStatements.joined(separator: ";\n") + ";"

        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, migrationSQL, nil, nil, &errorMessage) == SQLITE_OK {
            logger.info("Repaired legacy SwiftData store ZSLOTEND values")
        } else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            logger.error("Failed to migrate legacy SwiftData store: \(message)")
            sqlite3_free(errorMessage)
        }
        #endif
    }

    #if canImport(SQLite3)
    private static func sqliteTableExists(_ database: OpaquePointer, tableName: String) -> Bool {
        sqliteSingleInt(
            database,
            sql: "select count(*) from sqlite_master where type = 'table' and name = ?",
            value: tableName
        ) > 0
    }

    private static func sqliteColumnExists(
        _ database: OpaquePointer,
        tableName: String,
        columnName: String
    ) -> Bool {
        guard tableName == "ZTIMEENTRY" else { return false }
        return sqliteSingleInt(
            database,
            sql: "select count(*) from pragma_table_info('ZTIMEENTRY') where name = ?",
            value: columnName
        ) > 0
    }

    private static func sqliteSingleInt(
        _ database: OpaquePointer,
        sql: String,
        value: String
    ) -> Int {
        sqliteSingleInt(database, sql: sql, values: [value])
    }

    private static func sqliteSingleInt(
        _ database: OpaquePointer,
        sql: String,
        values: [String]
    ) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return 0
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, sqliteTransient)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static let sqliteTransient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )
    #endif

    var body: some Scene {
        #if os(macOS)
        MenuBarExtra("TimeTracker", systemImage: "clock.fill") {
            ContentView()
                .modelContainer(TimeTrackerApp.sharedModelContainer)
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .modelContainer(TimeTrackerApp.sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && !TimeTrackerApp.isRunningTests {
                logger.info("App became active — refreshing sync and rescheduling notifications")
                SyncService.shared.refreshFromRemote()
                Task {
                    await NotificationManager.shared.scheduleAllNotifications()
                }
            }
        }
        #endif
    }

    init() {
        if !Self.isRunningTests {
            NotificationManager.shared.setup()
            Task {
                let granted = await NotificationManager.shared.requestAuthorization()
                if granted {
                    await NotificationManager.shared.scheduleAllNotifications()
                }
                #if DEBUG
                // Lets the notification-tap flow be exercised on demand:
                // `open -a TimeTracker --args --debug-test-notification`
                if granted && CommandLine.arguments.contains("--debug-test-notification") {
                    await NotificationManager.shared.scheduleTestNotification()
                }
                #endif
            }
            // Pull, merge and re-upload entries via the sync API
            SyncService.shared.start(container: TimeTrackerApp.sharedModelContainer)
        } else {
            logger.info("Test mode — skipping notifications and sync")
        }

        #if os(macOS)
        // Reschedule notifications when Mac wakes from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            logger.info("Mac woke from sleep — rescheduling notifications")
            Task {
                await NotificationManager.shared.scheduleAllNotifications()
            }
        }
        #endif
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
