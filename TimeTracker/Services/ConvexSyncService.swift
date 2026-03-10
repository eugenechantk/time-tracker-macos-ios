import Combine
import ConvexMobile
import SwiftData
import SwiftUI
import os

private let logger = Logger(
    subsystem: "com.eugenechan.TimeTracker", category: "ConvexSync"
)

let convex = ConvexClient(deploymentUrl: "https://superb-curlew-997.convex.cloud")

/// Codable struct matching the Convex timeEntries schema
struct ConvexTimeEntry: Codable {
    let _id: String
    let deviceEntryId: String
    let slotStart: Double
    let entryDescription: String
    let submittedAt: Double
}

/// Syncs TimeEntry data between local SwiftData and Convex cloud.
/// Subscribes to real-time updates and pushes local changes.
@MainActor
final class ConvexSyncService: ObservableObject {
    static let shared = ConvexSyncService()

    @Published var remoteEntries: [ConvexTimeEntry] = []
    /// Triggers a UI refresh in TimelineView when remote data arrives or local save completes
    @Published var refreshID = UUID()

    private var subscriptionTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?

    func start(container: ModelContainer) {
        guard subscriptionTask == nil else { return }
        logger.info("Starting Convex sync subscription")

        subscriptionTask = Task {
            let publisher = convex.subscribe(to: "timeEntries:list", yielding: [ConvexTimeEntry].self)
                .replaceError(with: [])
                .receive(on: DispatchQueue.main)

            for await entries in publisher.values {
                logger.debug("Received \(entries.count) entries from Convex")
                self.remoteEntries = entries
                self.mergeRemoteEntries(entries, into: container)
            }
        }
    }

    func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    /// Push a local TimeEntry to Convex
    func pushEntry(_ entry: TimeEntry) {
        Task {
            do {
                let _: String? = try await convex.mutation("timeEntries:upsert", with: [
                    "deviceEntryId": entry.id.uuidString,
                    "slotStart": entry.slotStart.timeIntervalSince1970,
                    "entryDescription": entry.entryDescription,
                    "submittedAt": entry.submittedAt.timeIntervalSince1970
                ])
                logger.info("Pushed entry to Convex: \(entry.id.uuidString)")
            } catch {
                logger.error("Failed to push entry to Convex: \(error.localizedDescription)")
            }
        }
    }

    /// Merge remote Convex entries into local SwiftData
    private func mergeRemoteEntries(_ remoteEntries: [ConvexTimeEntry], into container: ModelContainer) {
        let context = ModelContext(container)

        do {
            let descriptor = FetchDescriptor<TimeEntry>()
            let localEntries = try context.fetch(descriptor)
            // Use grouping to safely handle potential duplicates
            let localById = Dictionary(grouping: localEntries, by: { $0.id.uuidString })
                .compactMapValues(\.first)

            // Also index by slotStart for matching entries created on other devices
            let localBySlotStart = Dictionary(
                grouping: localEntries,
                by: { $0.slotStart.timeIntervalSince1970 }
            ).compactMapValues { $0.sorted { $0.submittedAt > $1.submittedAt }.first }

            for remote in remoteEntries {
                let remoteSubmitted = Date(timeIntervalSince1970: remote.submittedAt)

                if let local = localById[remote.deviceEntryId] {
                    // Same entry (same UUID) — update if remote is newer
                    if remoteSubmitted > local.submittedAt {
                        local.entryDescription = remote.entryDescription
                        local.submittedAt = remoteSubmitted
                        logger.debug("Updated local entry from remote: \(remote.deviceEntryId)")
                    }
                } else if let local = localBySlotStart[remote.slotStart] {
                    // Same slot but different UUID (entry from another device) — update if newer
                    if remoteSubmitted > local.submittedAt {
                        local.entryDescription = remote.entryDescription
                        local.submittedAt = remoteSubmitted
                        logger.debug("Updated local slot entry from remote device: \(remote.deviceEntryId)")
                    }
                } else {
                    // Truly new entry — insert
                    let newEntry = TimeEntry(
                        slotStart: Date(timeIntervalSince1970: remote.slotStart),
                        entryDescription: remote.entryDescription,
                        submittedAt: remoteSubmitted
                    )
                    if let uuid = UUID(uuidString: remote.deviceEntryId) {
                        newEntry.id = uuid
                    }
                    context.insert(newEntry)
                    logger.debug("Inserted remote entry locally: \(remote.deviceEntryId)")
                }
            }

            try context.save()

            // Trigger UI refresh
            self.refreshID = UUID()
        } catch {
            logger.error("Failed to merge remote entries: \(error.localizedDescription)")
        }
    }
}
