// ios/NotesApp/Features/Library/LibraryViewModel.swift
import Foundation
import SwiftUI

@Observable
final class LibraryViewModel {
    private(set) var folders: [Folder] = []
    private(set) var notebooks: [Notebook] = []
    var errorMessage: String?

    /// The folder this view is scoped to. nil = Library root.
    let currentFolderID: String?

    private let notebookRepo: NotebookRepository
    private let folderRepo: FolderRepository

    init(notebookRepo: NotebookRepository,
         folderRepo: FolderRepository,
         currentFolderID: String? = nil) {
        self.notebookRepo = notebookRepo
        self.folderRepo = folderRepo
        self.currentFolderID = currentFolderID
    }

    func reload() {
        do {
            folders   = try folderRepo.fetchChildren(of: currentFolderID)
            notebooks = try notebookRepo.fetchAll(folderID: currentFolderID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createNotebook(title: String, coverColor: String) {
        do {
            _ = try notebookRepo.create(title: title,
                                        coverColor: coverColor,
                                        folderID: currentFolderID)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createFolder(title: String) {
        do {
            _ = try folderRepo.create(title: title, parentFolderID: currentFolderID)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ notebook: Notebook) {
        do {
            try notebookRepo.delete(id: notebook.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ folder: Folder) {
        do {
            try folderRepo.delete(id: folder.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 8 dark cover gradient presets stored as "START|END".
    static let coverPalette: [String] = [
        "#2A1F08|#1A1205",  // dark amber
        "#C9A84C|#A87C28",  // full gold
        "#1A1A2A|#0D0D1A",  // dark navy
        "#0A1A18|#051210",  // dark teal
        "#1A0A1A|#0D050D",  // dark plum
        "#1A0808|#0D0404",  // dark crimson
        "#0A1A0A|#051205",  // dark forest
        "#0F0F18|#080810",  // dark slate
    ]
}
