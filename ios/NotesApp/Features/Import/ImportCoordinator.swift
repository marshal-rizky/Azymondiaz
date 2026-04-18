import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - PDF → Notebook helper

enum PDFImporter {
    static let pageSize = CGSize(width: 1024, height: 1366)

    /// Renders each page of a PDF to PNG data.
    static func renderPages(from doc: PDFDocument) -> [Data] {
        (0..<doc.pageCount).compactMap { i -> Data? in
            guard let page = doc.page(at: i) else { return nil }
            let renderer = UIGraphicsImageRenderer(size: pageSize)
            return renderer.pngData { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: pageSize))
                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: pageSize.height)
                cg.scaleBy(x: 1, y: -1)
                let mediaBounds = page.bounds(for: .mediaBox)
                let scale = min(pageSize.width / mediaBounds.width,
                                pageSize.height / mediaBounds.height)
                cg.scaleBy(x: scale, y: scale)
                let offsetX = (pageSize.width / scale - mediaBounds.width) / 2
                let offsetY = (pageSize.height / scale - mediaBounds.height) / 2
                cg.translateBy(x: offsetX, y: offsetY)
                page.draw(with: .mediaBox, to: cg)
                cg.restoreGState()
            }
        }
    }
}

// MARK: - PDF document picker

struct PDFDocumentPicker: UIViewControllerRepresentable {
    var onPicked: (PDFDocument) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: PDFDocumentPicker
        init(_ parent: PDFDocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first,
                  url.startAccessingSecurityScopedResource(),
                  let doc = PDFDocument(url: url) else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            parent.onPicked(doc)
        }
    }
}

// MARK: - Photo picker (insert image)

struct PhotoItemPicker: UIViewControllerRepresentable {
    var onPicked: (Data) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoItemPicker
        init(_ parent: PhotoItemPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }
            result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                DispatchQueue.main.async { self.parent.onPicked(data) }
            }
        }
    }
}

// MARK: - Import action sheet trigger view

struct ImportButton: View {
    @Environment(AppContainer.self) private var container

    enum ImportContext {
        case library
        case notebook(Notebook, String?)  // notebook + optional current pageId
    }

    let mode: ImportContext
    var onNewNotebookCreated: ((Notebook) -> Void)? = nil
    var onMediaInserted: ((PageMediaItem) -> Void)? = nil

    @State private var showingActionSheet = false
    @State private var showingPDFPicker = false
    @State private var showingPhotoPicker = false
    @State private var showingProgress = false
    @State private var isForExistingNotebook = false

    var body: some View {
        Button {
            showingActionSheet = true
        } label: {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 30, height: 30)
        }
        .confirmationDialog("Import", isPresented: $showingActionSheet) {
            Button("PDF → New Notebook") {
                isForExistingNotebook = false
                showingPDFPicker = true
            }
            if case .notebook = mode {
                Button("PDF → Add pages here") {
                    isForExistingNotebook = true
                    showingPDFPicker = true
                }
                Button("Insert Image on this page") {
                    showingPhotoPicker = true
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingPDFPicker) {
            PDFDocumentPicker { doc in
                showingPDFPicker = false
                showingProgress = true
                Task.detached {
                    await importPDF(doc: doc)
                    await MainActor.run { showingProgress = false }
                }
            }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            PhotoItemPicker { imageData in
                insertImage(data: imageData)
            }
        }
        .overlay {
            if showingProgress {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(AppColors.gold)
                        Text("Importing…")
                            .font(AppFonts.caption)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .padding(24)
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                }
            }
        }
    }

    // MARK: - Import logic

    @MainActor
    private func importPDF(doc: PDFDocument) async {
        let blobs = await Task.detached(priority: .userInitiated) {
            PDFImporter.renderPages(from: doc)
        }.value
        let title = doc.documentURL?.deletingPathExtension().lastPathComponent ?? "Imported"

        if isForExistingNotebook, case .notebook(let nb, _) = mode {
            for blob in blobs {
                guard let page = try? container.pages.append(notebookId: nb.id, template: .blank) else { continue }
                let item = PageMediaItem(
                    id: UUID().uuidString, pageId: page.id, sortIndex: 0,
                    imageBlob: blob, x: 0, y: 0, width: 1, height: 1,
                    createdAt: Date()
                )
                try? container.pageMedia.insert(item)
            }
        } else {
            guard let nb = try? container.notebooks.create(title: title, coverColor: "#4A90E2") else { return }
            for blob in blobs {
                guard let page = try? container.pages.append(notebookId: nb.id, template: .blank) else { continue }
                let item = PageMediaItem(
                    id: UUID().uuidString, pageId: page.id, sortIndex: 0,
                    imageBlob: blob, x: 0, y: 0, width: 1, height: 1,
                    createdAt: Date()
                )
                try? container.pageMedia.insert(item)
            }
            onNewNotebookCreated?(nb)
        }
    }

    private func insertImage(data: Data) {
        guard case .notebook(_, let pageId) = mode, let pageId else { return }
        let item = PageMediaItem(
            id: UUID().uuidString, pageId: pageId, sortIndex: 0,
            imageBlob: data, x: 0.1, y: 0.1, width: 0.5, height: 0.5,
            createdAt: Date()
        )
        try? container.pageMedia.insert(item)
        onMediaInserted?(item)
    }
}
