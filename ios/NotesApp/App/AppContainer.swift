import Foundation
import SwiftUI

/// Single composition root. Holds the long-lived database and repositories so
/// views can reach them via `@Environment(AppContainer.self)`.
@Observable
final class AppContainer {
    let database: AppDatabase
    let notebooks: NotebookRepository
    let folders: FolderRepository
    let pages: PageRepository
    let aiMessages: AIMessageRepository
    var aiRouter: AIRouter
    var syncClient: SyncClient?
    var syncScheduler: SyncScheduler?

    init(database: AppDatabase) {
        self.database = database
        self.notebooks = NotebookRepository(writer: database.writer)
        self.folders = FolderRepository(writer: database.writer)
        self.pages = PageRepository(writer: database.writer)
        self.aiMessages = AIMessageRepository(writer: database.writer)
        self.aiRouter = AIRouter.bootstrap()
        // Defer sync setup — needs reloadAI() after init finishes
    }

    static func makeDefault() -> AppContainer {
        do {
            let db = try AppDatabase.makeDefault()
            let container = AppContainer(database: db)
            container.reloadAI()
            return container
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }

    /// Call after the user changes PC URL or keys in Settings.
    func reloadAI() {
        self.aiRouter = AIRouter.bootstrap()
        if let urlString = try? KeychainStore.shared.getPCServerURL(),
           !urlString.isEmpty,
           let url = URL(string: urlString) {
            let client = SyncClient(baseURL: url, writer: database.writer)
            self.syncClient = client
            let sched = SyncScheduler(client: client)
            sched.start()
            self.syncScheduler = sched
        } else {
            self.syncScheduler?.stop()
            self.syncClient = nil
            self.syncScheduler = nil
        }
    }
}
