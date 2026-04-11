import Foundation
import SwiftUI

/// Single composition root. Holds the long-lived database and repositories so
/// views can reach them via `@Environment(AppContainer.self)`.
@Observable
final class AppContainer {
    let database: AppDatabase
    let notebooks: NotebookRepository
    let pages: PageRepository
    let aiMessages: AIMessageRepository
    var aiRouter: AIRouter

    init(database: AppDatabase) {
        self.database = database
        self.notebooks = NotebookRepository(writer: database.writer)
        self.pages = PageRepository(writer: database.writer)
        self.aiMessages = AIMessageRepository(writer: database.writer)
        self.aiRouter = AIRouter.bootstrap()
    }

    static func makeDefault() -> AppContainer {
        do {
            let db = try AppDatabase.makeDefault()
            return AppContainer(database: db)
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }

    /// Call after the user changes PC URL or keys in Settings.
    func reloadAI() {
        self.aiRouter = AIRouter.bootstrap()
    }
}
