import Combine
import Foundation
import SwiftData
import SwiftUI
import os

private let logger = Logger(
    subsystem: "com.eugenechan.TimeTracker", category: "Sync"
)

/// Syncs TimeEntry data between local SwiftData and the sync API (Cloudflare Worker + Neon).
///
/// There is no push channel: devices converge whenever `refreshFromRemote` runs (launch,
/// popover open / app active, after a save). Each refresh pulls, merges, then uploads anything
/// the server is missing, so a failed upload heals on the next refresh.
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    /// Triggers a UI refresh in TimelineView when remote data arrives or local save completes.
    @Published var refreshID = UUID()

    private let api: SyncAPIClient
    private var refreshTask: Task<Void, Never>?
    private var didStart = false

    init(api: SyncAPIClient = .live) {
        self.api = api
    }

    func start(container: ModelContainer) {
        guard !didStart else { return }
        didStart = true
        logger.info("Starting sync")
        refreshFromRemote(into: container)
    }

    /// Pull, merge, and re-upload. Call when a MenuBarExtra popover becomes visible or the
    /// iOS app becomes active, since there is no realtime channel to deliver other devices' edits.
    func refreshFromRemote() {
        refreshFromRemote(into: TimeTrackerApp.sharedModelContainer)
    }

    func refreshFromRemote(into container: ModelContainer) {
        refreshTask?.cancel()
        refreshTask = Task {
            do {
                let entries = try await api.fetchEntries()
                applyRemoteEntries(entries, into: container)
                try await pushUnsyncedEntries(comparedTo: entries, from: container)
            } catch is CancellationError {
                logger.debug("Sync refresh cancelled")
            } catch let error as URLError where error.code == .cancelled {
                logger.debug("Sync refresh cancelled")
            } catch {
                logger.error("Failed to refresh from sync API: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Push a local TimeEntry. Fire-and-forget: if this fails, the next `refreshFromRemote`
    /// re-pushes the entry because the server copy is missing or older.
    func pushEntry(_ entry: TimeEntry) {
        let remote = Self.remoteRepresentation(of: entry)

        Task {
            do {
                try await api.upsert([remote])
                logger.info("Pushed entry: \(remote.deviceEntryId, privacy: .public)")
            } catch {
                logger.error("Failed to push entry: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Upload local entries the server is missing or holds an older version of.
    /// Runs after every pull so entries saved while offline (or while the backend was down) catch up.
    private func pushUnsyncedEntries(comparedTo remoteEntries: [RemoteTimeEntry], from container: ModelContainer) async throws {
        let localEntries = try ModelContext(container)
            .fetch(FetchDescriptor<TimeEntry>())
            .map(Self.remoteRepresentation(of:))
        let pending = Self.entriesNeedingPush(local: localEntries, remote: remoteEntries)
        guard !pending.isEmpty else { return }

        // The Worker caps a request at 5000 rows; stay well under it.
        for batch in Self.batches(of: pending, size: Self.pushBatchSize) {
            try await api.upsert(batch)
        }
        logger.info("Pushed \(pending.count) unsynced entries")
    }

    static let pushBatchSize = 1000

    static func batches(of entries: [RemoteTimeEntry], size: Int) -> [[RemoteTimeEntry]] {
        stride(from: 0, to: entries.count, by: size).map {
            Array(entries[$0..<min($0 + size, entries.count)])
        }
    }

    /// Local entries with no server counterpart, or whose server counterpart is older.
    /// The counterpart is the row with the same id, else the newest row for the same slot
    /// (another device may have written that slot under its own id).
    static func entriesNeedingPush(
        local: [RemoteTimeEntry],
        remote: [RemoteTimeEntry]
    ) -> [RemoteTimeEntry] {
        // Timestamps round-trip through Date and Postgres doubles; ignore sub-millisecond drift.
        let tolerance = 0.001
        let remoteById = Dictionary(remote.map { ($0.deviceEntryId, $0) }, uniquingKeysWith: { $0.submittedAt >= $1.submittedAt ? $0 : $1 })
        let remoteBySlot = Dictionary(remote.map { ($0.slotStart, $0) }, uniquingKeysWith: { $0.submittedAt >= $1.submittedAt ? $0 : $1 })

        return local.filter { entry in
            guard let counterpart = remoteById[entry.deviceEntryId] ?? remoteBySlot[entry.slotStart] else {
                return true
            }
            return entry.submittedAt > counterpart.submittedAt + tolerance
        }
    }

    static func remoteRepresentation(of entry: TimeEntry) -> RemoteTimeEntry {
        RemoteTimeEntry(
            deviceEntryId: entry.id.uuidString,
            slotStart: entry.slotStart.timeIntervalSince1970,
            slotEnd: normalizedSlotEnd(for: entry).timeIntervalSince1970,
            entryDescription: entry.entryDescription,
            submittedAt: entry.submittedAt.timeIntervalSince1970
        )
    }

    private func applyRemoteEntries(_ entries: [RemoteTimeEntry], into container: ModelContainer) {
        if mergeRemoteEntries(entries, into: container) {
            refreshID = UUID()
        }
    }

    /// Merge remote entries into local SwiftData.
    private func mergeRemoteEntries(_ remoteEntries: [RemoteTimeEntry], into container: ModelContainer) -> Bool {
        guard !remoteEntries.isEmpty else { return false }

        let context = ModelContext(container)

        do {
            let descriptor = FetchDescriptor<TimeEntry>()
            let localEntries = try context.fetch(descriptor)
            let localById = Dictionary(grouping: localEntries, by: { $0.id.uuidString })
                .compactMapValues(\.first)

            var localBySlotStart = Dictionary(
                grouping: localEntries,
                by: { $0.slotStart.timeIntervalSince1970 }
            ).compactMapValues { $0.sorted { $0.submittedAt > $1.submittedAt }.first }

            var didChange = false

            for remote in remoteEntries {
                let remoteSubmitted = Date(timeIntervalSince1970: remote.submittedAt)

                if let local = localById[remote.deviceEntryId] {
                    if remoteSubmitted > local.submittedAt {
                        local.slotEnd = slotEndDate(for: remote)
                        local.entryDescription = remote.entryDescription
                        local.submittedAt = remoteSubmitted
                        didChange = true
                        logger.debug("Updated local entry from remote: \(remote.deviceEntryId)")
                    }
                } else if let local = localBySlotStart[remote.slotStart] {
                    if remoteSubmitted > local.submittedAt {
                        local.slotEnd = slotEndDate(for: remote)
                        local.entryDescription = remote.entryDescription
                        local.submittedAt = remoteSubmitted
                        didChange = true
                        logger.debug("Updated local slot entry from remote: \(remote.deviceEntryId)")
                    }
                } else {
                    let newEntry = TimeEntry(
                        slotStart: Date(timeIntervalSince1970: remote.slotStart),
                        slotEnd: slotEndDate(for: remote),
                        entryDescription: remote.entryDescription,
                        submittedAt: remoteSubmitted
                    )
                    if let uuid = UUID(uuidString: remote.deviceEntryId) {
                        newEntry.id = uuid
                    }
                    context.insert(newEntry)
                    // The server can hold two rows for one slot (written by different devices).
                    // Register the insert so the next row for this slot updates it instead of
                    // inserting a duplicate.
                    localBySlotStart[remote.slotStart] = newEntry
                    didChange = true
                    logger.debug("Inserted remote entry locally: \(remote.deviceEntryId)")
                }
            }

            if didChange {
                try context.save()
            }
            return didChange
        } catch {
            logger.error("Failed to merge remote entries: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func slotEndDate(for remote: RemoteTimeEntry) -> Date {
        let fallback = remote.slotStart + TimeInterval(SlotManager.slotDurationMinutes * 60)
        return Date(timeIntervalSince1970: remote.slotEnd ?? fallback)
    }

    private static func normalizedSlotEnd(for entry: TimeEntry) -> Date {
        if entry.slotEnd > entry.slotStart {
            return entry.slotEnd
        }
        return entry.slotStart.addingTimeInterval(TimeInterval(SlotManager.slotDurationMinutes * 60))
    }
}
