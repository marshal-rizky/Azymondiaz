import Foundation
import PencilKit
import SwiftUI

@Observable
final class NotebookViewModel {
    let notebook: Notebook
    private(set) var pages: [Page] = []
    var currentPageIndex: Int = 0
    var currentDrawing = PKDrawing() {
        didSet { scheduleSave() }
    }
    var errorMessage: String?

    private let repo: PageRepository
    private(set) var currentMediaItems: [PageMediaItem] = []
    private let mediaRepo: PageMediaRepository
    private var saveWorkItem: DispatchWorkItem?

    init(notebook: Notebook, repo: PageRepository, mediaRepo: PageMediaRepository) {
        self.notebook = notebook
        self.repo = repo
        self.mediaRepo = mediaRepo
    }

    var currentPage: Page? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        return pages[currentPageIndex]
    }

    var currentPageIsDark: Bool {
        currentPage?.theme == "dark"
    }

    func load() {
        do {
            pages = try repo.fetchAll(notebookId: notebook.id)
            if pages.isEmpty {
                _ = try repo.append(notebookId: notebook.id, template: .line)
                pages = try repo.fetchAll(notebookId: notebook.id)
            }
            currentPageIndex = 0
            loadDrawingForCurrentPage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reload pages after a bulk import; jump to the first newly added page
    /// so imported content is immediately visible.
    func reloadAfterImport(previousPageCount: Int) {
        do {
            pages = try repo.fetchAll(notebookId: notebook.id)
            currentPageIndex = pages.count > previousPageCount
                ? previousPageCount          // first new page
                : max(0, pages.count - 1)    // fallback if nothing was added
            loadDrawingForCurrentPage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectPage(index: Int) {
        flushSave()
        currentPageIndex = max(0, min(index, pages.count - 1))
        loadDrawingForCurrentPage()
    }

    func addPage(template: PageTemplateKind) {
        flushSave()
        do {
            _ = try repo.append(notebookId: notebook.id, template: template)
            pages = try repo.fetchAll(notebookId: notebook.id)
            currentPageIndex = pages.count - 1
            loadDrawingForCurrentPage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCurrentPage() {
        guard let page = currentPage else { return }
        saveWorkItem?.cancel()
        do {
            try repo.delete(id: page.id)
            pages = try repo.fetchAll(notebookId: notebook.id)
            if pages.isEmpty {
                _ = try repo.append(notebookId: notebook.id, template: .line)
                pages = try repo.fetchAll(notebookId: notebook.id)
            }
            currentPageIndex = min(currentPageIndex, pages.count - 1)
            loadDrawingForCurrentPage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleCurrentPageTheme() {
        guard let page = currentPage,
              let idx = pages.firstIndex(where: { $0.id == page.id }) else { return }
        let newTheme = page.theme == "dark" ? "light" : "dark"
        do {
            try repo.updateTheme(pageId: page.id, theme: newTheme)
            pages[idx].theme = newTheme
            // Note: mutate pages[idx] synchronously on main thread before any
            // in-flight saveWorkItem fires — persistCurrentDrawing() reads the
            // updated theme from pages[currentPageIndex], so ordering is correct.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateMedia(_ item: PageMediaItem) {
        try? mediaRepo.update(item)
        if let idx = currentMediaItems.firstIndex(where: { $0.id == item.id }) {
            currentMediaItems[idx] = item
        }
    }

    func deleteMedia(id: String) {
        try? mediaRepo.delete(id: id)
        currentMediaItems.removeAll { $0.id == id }
    }

    func addMedia(_ item: PageMediaItem) {
        try? mediaRepo.insert(item)
        currentMediaItems.append(item)
    }

    /// Force-write the current drawing immediately. Call on background / dismiss.
    func flushSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        persistCurrentDrawing()
    }

    // MARK: - Private

    private func loadDrawingForCurrentPage() {
        guard let page = currentPage else {
            currentDrawing = PKDrawing()
            currentMediaItems = []
            return
        }
        if let blob = page.drawingBlob, let restored = try? PKDrawing(data: blob) {
            currentDrawing = restored
        } else {
            currentDrawing = PKDrawing()
        }
        if let page = currentPage {
            currentMediaItems = (try? mediaRepo.fetchAll(pageId: page.id)) ?? []
        } else {
            currentMediaItems = []
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistCurrentDrawing()
        }
        saveWorkItem = work
        // Debounce: coalesce fast pen strokes into one write.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func persistCurrentDrawing() {
        guard let page = currentPage else { return }
        let drawing = currentDrawing
        let data = drawing.dataRepresentation()
        let thumbSize = CGSize(width: 1024, height: 1366)
        let thumb = ThumbnailRenderer.render(
            drawing: drawing,
            template: page.template,
            pageSize: thumbSize,
            thumbnailWidth: 160,
            isDark: page.theme == "dark"
        )
        do {
            try repo.updateDrawing(pageId: page.id, drawing: data, thumbnail: thumb)
            if let refreshed = try repo.fetch(id: page.id),
               let idx = pages.firstIndex(where: { $0.id == page.id }) {
                pages[idx] = refreshed
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
