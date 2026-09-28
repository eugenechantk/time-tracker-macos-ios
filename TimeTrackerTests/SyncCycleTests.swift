import Testing
import Foundation
import SwiftData
@testable import TimeTracker

/// Fake sync server: serves `remote` on GET and records every POST body.
final class FakeSyncServer: URLProtocol {
    nonisolated(unsafe) static var remote = Data("[]".utf8)
    nonisolated(unsafe) static var posts: [[RemoteTimeEntry]] = []
    nonisolated(unsafe) static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let body: Data
        if request.httpMethod == "POST" {
            let sent = (try? JSONDecoder().decode([RemoteTimeEntry].self, from: StubURLProtocol.body(of: request))) ?? []
            Self.posts.append(sent)
            body = Data(#"{"upserted":0}"#.utf8)
        } else {
            body = Self.remote
        }
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset(remote entries: [RemoteTimeEntry]) {
        lock.lock(); defer { lock.unlock() }
        remote = try! JSONEncoder().encode(entries)
        posts = []
    }

    static var postedBatches: [[RemoteTimeEntry]] {
        lock.lock(); defer { lock.unlock() }
        return posts
    }
}

/// Runs the real SyncService refresh (pull, merge, push) against FakeSyncServer and an in-memory store.
@MainActor
@Suite(.serialized)
struct SyncCycleTests {

    private func makeService() -> SyncService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeSyncServer.self]
        return SyncService(api: SyncAPIClient(
            baseURL: URL(string: "https://sync.example")!,
            token: "test-token",
            session: URLSession(configuration: config)
        ))
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: TimeEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func row(_ id: String, slot: Double, submitted: Double, text: String) -> RemoteTimeEntry {
        RemoteTimeEntry(deviceEntryId: id, slotStart: slot, slotEnd: slot + 1800, entryDescription: text, submittedAt: submitted)
    }

    /// refreshFromRemote runs in an unstructured Task; poll the store until it settles.
    private func refreshAndWait(_ service: SyncService, _ container: ModelContainer, until done: () throws -> Bool) async throws {
        service.refreshFromRemote(into: container)
        for _ in 0..<100 {
            if try done() { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(200))
    }

    @Test func freshDeviceKeepsOneRowPerSlotWhenServerHasTwo() async throws {
        // Two devices wrote the same slot under their own ids; the newer text must win locally.
        let older = row(UUID().uuidString, slot: 1_790_000_000, submitted: 100, text: "older")
        let newer = row(UUID().uuidString, slot: 1_790_000_000, submitted: 200, text: "newer")
        FakeSyncServer.reset(remote: [older, newer])
        let container = try makeContainer()

        try await refreshAndWait(makeService(), container) {
            try !ModelContext(container).fetch(FetchDescriptor<TimeEntry>()).isEmpty
        }

        let local = try ModelContext(container).fetch(FetchDescriptor<TimeEntry>())
        #expect(local.count == 1)
        #expect(local.first?.entryDescription == "newer")
    }

    @Test func largeCatchUpIsSplitIntoBatches() async throws {
        FakeSyncServer.reset(remote: [])
        let container = try makeContainer()
        let context = ModelContext(container)
        for index in 0..<2_500 {
            context.insert(TimeEntry(
                slotStart: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 1800),
                entryDescription: "entry \(index)"
            ))
        }
        try context.save()

        try await refreshAndWait(makeService(), container) {
            FakeSyncServer.postedBatches.map(\.count).reduce(0, +) >= 2_500
        }

        let batches = FakeSyncServer.postedBatches
        #expect(batches.map(\.count) == [1000, 1000, 500])
        #expect(Set(batches.flatMap { $0 }.map(\.deviceEntryId)).count == 2_500)
    }
}
