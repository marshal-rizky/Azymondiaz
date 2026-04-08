import Foundation
import SwiftUI

@Observable
final class LibraryViewModel {
    private(set) var notebooks: [Notebook] = []
    var errorMessage: String?

    private let repo: NotebookRepository

    init(repo: NotebookRepository) {
        self.repo = repo
    }

    func reload() {
        do {
            notebooks = try repo.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createNotebook(title: String) {
        let color = Self.randomCoverColor()
        do {
            _ = try repo.create(title: title, coverColor: color)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ notebook: Notebook) {
        do {
            try repo.delete(id: notebook.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func randomCoverColor() -> String {
        let palette = ["#4A90E2", "#F5A623", "#7ED321", "#D0021B", "#9013FE", "#50E3C2"]
        return palette.randomElement() ?? "#4A90E2"
    }
}
