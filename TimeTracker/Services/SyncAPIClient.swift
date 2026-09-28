import Foundation

/// One row of the sync API's `time_entries` table. Times are Unix epoch seconds.
struct RemoteTimeEntry: Codable, Equatable {
    let deviceEntryId: String
    let slotStart: Double
    let slotEnd: Double?
    let entryDescription: String
    let submittedAt: Double

    enum CodingKeys: String, CodingKey {
        case deviceEntryId = "device_entry_id"
        case slotStart = "slot_start"
        case slotEnd = "slot_end"
        case entryDescription = "entry_description"
        case submittedAt = "submitted_at"
    }
}

enum SyncAPIError: LocalizedError {
    case badStatus(Int, body: String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let status, let body):
            return "Sync API returned HTTP \(status): \(body.prefix(200))"
        }
    }
}

/// HTTP client for the TimeTracker sync Worker (`sync-api/`), which fronts the Neon database.
struct SyncAPIClient {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    static let live = SyncAPIClient(
        baseURL: URL(string: SyncSecrets.baseURL)!,
        token: SyncSecrets.apiToken
    )

    func fetchEntries() async throws -> [RemoteTimeEntry] {
        let data = try await send(makeRequest(method: "GET"))
        return try JSONDecoder().decode([RemoteTimeEntry].self, from: data)
    }

    /// Upserts by `deviceEntryId`. The server ignores any entry older than the copy it already has.
    func upsert(_ entries: [RemoteTimeEntry]) async throws {
        guard !entries.isEmpty else { return }
        var request = makeRequest(method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(entries)
        _ = try await send(request)
    }

    func makeRequest(method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "entries"))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Neon compute cold-starts after 5 idle minutes; allow for that on the first request.
        request.timeoutInterval = 30
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw SyncAPIError.badStatus(status, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }
}
