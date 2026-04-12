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

    // MARK: - Server-compatible request structs (matches server/src/notes_server/models.py)

    private struct PageSnapshot: Encodable {
        let id: String
        let notebook_id: String
        let index: Int
        let template: String
        let drawing_blob_base64: String
        let thumbnail_blob_base64: String?
        let updated_at: TimeInterval
    }

    private struct NotebookSnapshot: Encodable {
        let id: String
        let title: String
        let cover_color: String
        let updated_at: TimeInterval
        let pages: [PageSnapshot]
    }

    private struct PushPayload: Encodable {
        let notebooks: [NotebookSnapshot]
        let since_timestamp: TimeInterval
    }

    // MARK: - Push

    func push() async throws -> Date {
        let lastSync = try await writer.read { db in
            try Date.fetchOne(db, sql: "SELECT last_sync_at FROM sync_state WHERE id = 1")
        }

        // Collect IDs of notebooks that need syncing (changed notebook or changed page)
        let notebookIds: Set<String> = try await writer.read { db in
            let cutoff = lastSync ?? Date(timeIntervalSince1970: 0)
            var ids = Set<String>()
            try Notebook.filter(Column("updated_at") > cutoff).fetchAll(db).forEach { ids.insert($0.id) }
            try Page.filter(Column("updated_at") > cutoff).fetchAll(db).forEach { ids.insert($0.notebookId) }
            return ids
        }

        guard !notebookIds.isEmpty else {
            // Nothing changed — just bump the timestamp
            let now = Date()
            try await writer.write { db in
                try db.execute(sql: "UPDATE sync_state SET last_sync_at = ? WHERE id = 1", arguments: [now])
            }
            return now
        }

        // Build full snapshots: for each changed notebook, include ALL its current pages
        let snapshots: [NotebookSnapshot] = try await writer.read { db in
            try notebookIds.sorted().compactMap { nbId -> NotebookSnapshot? in
                guard let nb = try Notebook.fetchOne(db, key: nbId) else { return nil }
                let pages = try Page
                    .filter(Column("notebook_id") == nbId)
                    .order(Column("page_index"))
                    .fetchAll(db)
                let pageSnaps = pages.map { p in
                    PageSnapshot(
                        id: p.id,
                        notebook_id: p.notebookId,
                        index: p.pageIndex,
                        template: p.template.rawValue,
                        drawing_blob_base64: p.drawingBlob?.base64EncodedString() ?? "",
                        thumbnail_blob_base64: p.thumbnailBlob?.base64EncodedString(),
                        updated_at: p.updatedAt.timeIntervalSince1970
                    )
                }
                return NotebookSnapshot(
                    id: nb.id,
                    title: nb.title,
                    cover_color: nb.coverColor,
                    updated_at: nb.updatedAt.timeIntervalSince1970,
                    pages: pageSnaps
                )
            }
        }

        let payload = PushPayload(
            notebooks: snapshots,
            since_timestamp: lastSync?.timeIntervalSince1970 ?? 0
        )

        var req = URLRequest(url: baseURL.appendingPathComponent("/sync/push"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIError.http((response as? HTTPURLResponse)?.statusCode ?? -1, "sync push failed")
        }

        let now = Date()
        try await writer.write { db in
            try db.execute(sql: "UPDATE sync_state SET last_sync_at = ? WHERE id = 1", arguments: [now])
        }
        return now
    }
}
