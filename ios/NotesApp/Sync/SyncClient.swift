import Foundation
import GRDB

final class SyncClient {
    private let baseURL: URL
    private let session: URLSession
    private let writer: any DatabaseWriter

    init(baseURL: URL, writer: any DatabaseWriter, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.writer = writer
        self.session = session
    }

    struct PushResponse: Decodable { let acceptedAt: Date? }

    func push() async throws -> Date {
        let lastSync = try writer.read { db in
            try Date.fetchOne(db, sql: "SELECT last_sync_at FROM sync_state WHERE id = 1")
        }
        let diff = try SyncDiff.compute(writer: writer, since: lastSync)

        var req = URLRequest(url: baseURL.appendingPathComponent("/sync/push"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        req.httpBody = try encoder.encode(diff)

        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIError.http((response as? HTTPURLResponse)?.statusCode ?? -1, "sync push failed")
        }
        let now = Date()
        try writer.write { db in
            try db.execute(sql: "UPDATE sync_state SET last_sync_at = ? WHERE id = 1", arguments: [now])
        }
        return now
    }
}
