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
    private var saveWorkItem: DispatchWorkItem?

    init(notebook: Notebook, repo: PageRepository) {
        self.notebook = notebook
        self.repo = repo
    }

    var currentPage: Page? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        return pages[currentPageIndex]
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
            return
        }
        if let blob = page.drawingBlob, let restored = try? PKDrawing(data: blob) {
            currentDrawing = restored
        } else {
            currentDrawing = PKDrawing()
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
            isDark: false
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
