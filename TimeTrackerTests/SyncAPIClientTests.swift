import Testing
import Foundation
@testable import TimeTracker

/// Answers every request from `handler` so the client can be tested without a network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        do {
            let (status, data) = try Self.handler?(request) ?? (500, Data())
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// URLSession moves `httpBody` into a stream before it reaches the protocol.
    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@MainActor
@Suite(.serialized)
struct SyncAPIClientTests {

    private func makeClient() -> SyncAPIClient {
        StubURLProtocol.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return SyncAPIClient(
            baseURL: URL(string: "https://sync.example")!,
            token: "test-token",
            session: URLSession(configuration: config)
        )
    }

    @Test func fetchSendsAuthorizedGetAndDecodesSnakeCase() async throws {
        let client = makeClient()
        StubURLProtocol.handler = { _ in
            (200, Data("""
            [{"device_entry_id":"mac-1","slot_start":1790000000,"slot_end":1790001800,
              "entry_description":"deep work","submitted_at":1790001900.5}]
            """.utf8))
        }

        let entries = try await client.fetchEntries()

        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://sync.example/entries")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(entries == [RemoteTimeEntry(
            deviceEntryId: "mac-1",
            slotStart: 1_790_000_000,
            slotEnd: 1_790_001_800,
            entryDescription: "deep work",
            submittedAt: 1_790_001_900.5
        )])
    }

    @Test func upsertPostsSnakeCaseJSONArray() async throws {
        let client = makeClient()
        StubURLProtocol.handler = { _ in (200, Data(#"{"upserted":1}"#.utf8)) }
        let entry = RemoteTimeEntry(
            deviceEntryId: "mac-1", slotStart: 10, slotEnd: 1810, entryDescription: "email", submittedAt: 20
        )

        try await client.upsert([entry])

        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        let sent = try JSONSerialization.jsonObject(with: StubURLProtocol.body(of: request)) as? [[String: Any]]
        #expect(sent?.first?["device_entry_id"] as? String == "mac-1")
        #expect(sent?.first?["entry_description"] as? String == "email")
        #expect(sent?.first?["submitted_at"] as? Double == 20)
    }

    @Test func upsertOfNothingMakesNoRequest() async throws {
        let client = makeClient()
        try await client.upsert([])
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test func nonSuccessStatusThrowsWithStatus() async {
        let client = makeClient()
        StubURLProtocol.handler = { _ in (401, Data(#"{"error":"unauthorized"}"#.utf8)) }

        await #expect {
            try await client.fetchEntries()
        } throws: { error in
            guard case SyncAPIError.badStatus(let status, _) = error else { return false }
            return status == 401
        }
    }
}
