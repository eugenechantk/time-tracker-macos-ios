import Testing
import Foundation
@testable import TimeTracker

@MainActor
struct SyncReconcileTests {

    private func row(
        _ id: String,
        slot: Double = 1_000_000,
        submitted: Double,
        text: String = "work"
    ) -> RemoteTimeEntry {
        RemoteTimeEntry(
            deviceEntryId: id,
            slotStart: slot,
            slotEnd: slot + 1800,
            entryDescription: text,
            submittedAt: submitted
        )
    }

    @Test func localEntryMissingFromServerIsPushed() {
        let local = [row("mac-1", submitted: 100)]
        let pending = SyncService.entriesNeedingPush(local: local, remote: [])
        #expect(pending == local)
    }

    @Test func localEntryAlreadyOnServerIsNotPushed() {
        let local = [row("mac-1", submitted: 100)]
        let pending = SyncService.entriesNeedingPush(local: local, remote: local)
        #expect(pending.isEmpty)
    }

    @Test func localEntryNewerThanServerCopyIsPushed() {
        let local = [row("mac-1", submitted: 200, text: "edited")]
        let remote = [row("mac-1", submitted: 100)]
        let pending = SyncService.entriesNeedingPush(local: local, remote: remote)
        #expect(pending == local)
    }

    @Test func localEntryOlderThanServerCopyIsNotPushed() {
        let local = [row("mac-1", submitted: 100)]
        let remote = [row("mac-1", submitted: 200, text: "newer from phone")]
        #expect(SyncService.entriesNeedingPush(local: local, remote: remote).isEmpty)
    }

    @Test func sameSlotWrittenByOtherDeviceCountsAsCounterpart() {
        // After merge, the local entry carries the phone's text and timestamp under the Mac's id.
        let local = [row("mac-1", submitted: 200)]
        let remote = [row("phone-1", submitted: 200)]
        #expect(SyncService.entriesNeedingPush(local: local, remote: remote).isEmpty)
    }

    @Test func subMillisecondTimestampDriftDoesNotRepush() {
        let local = [row("mac-1", submitted: 1_790_000_000.123_456_7)]
        let remote = [row("mac-1", submitted: 1_790_000_000.123_456_6)]
        #expect(SyncService.entriesNeedingPush(local: local, remote: remote).isEmpty)
    }

    @Test func batchesSplitWithoutLosingOrDuplicating() {
        let entries = (0..<2_345).map { row("id-\($0)", slot: Double($0), submitted: 1) }
        let batches = SyncService.batches(of: entries, size: 1000)
        #expect(batches.map(\.count) == [1000, 1000, 345])
        #expect(batches.flatMap { $0 } == entries)
        #expect(SyncService.batches(of: [], size: 1000).isEmpty)
    }

    @Test func remoteRepresentationRoundTripsTimeEntry() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let entry = TimeEntry(slotStart: start, entryDescription: "deep work")
        let remote = SyncService.remoteRepresentation(of: entry)
        #expect(remote.deviceEntryId == entry.id.uuidString)
        #expect(remote.slotStart == start.timeIntervalSince1970)
        #expect(remote.slotEnd == start.timeIntervalSince1970 + 1800)
        #expect(remote.entryDescription == "deep work")
    }
}
