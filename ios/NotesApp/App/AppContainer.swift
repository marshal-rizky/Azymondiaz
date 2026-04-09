import Foundation
import SwiftUI

/// Single composition root. Holds the long-lived database and repositories so
/// views can reach them via `@Environment(AppContainer.self)`.
@Observable
final class AppContainer {
    let database: AppDatabase
    let notebooks: NotebookRepository
    let pages: PageRepository

    init(database: AppDatabase) {
        self.database = database
        self.notebooks = NotebookRepository(pool: database.pool)
        self.pages = PageRepository(pool: database.pool)
    }

    static func makeDefault() -> AppContainer {
        do {
            let db = try AppDatabase.makeDefault()
            return AppContainer(database: db)
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }
}
