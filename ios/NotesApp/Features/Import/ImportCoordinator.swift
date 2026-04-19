import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - PDF → Notebook helper

enum PDFImporter {
    static let pageSize = CGSize(width: 1024, height: 1366)

    /// Renders a single PDF page to PNG data. Call one page at a time to avoid
    /// holding all blobs in memory simultaneously for large documents.
    static func renderPage(_ page: PDFPage) -> Data {
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

// MARK: - PDF document picker (UIKit modal presentation)

/// Presents UIDocumentPickerViewController from a dedicated UIWindow that sits
/// completely outside SwiftUI's UIHostingController chain.
///
/// Root cause of all previous failures: on iPadOS, presenting
/// UIDocumentPickerViewController from ANY VC that is part of a
/// UIHostingController hierarchy (SwiftUI's `.fileImporter`, `.sheet`, embedded
/// host VC, even the root UIHostingController itself) causes the picker's file
/// grid to receive no touches — the picker appears but is completely unresponsive.
/// Creating a separate UIWindow with its own plain UIViewController as root, then
/// presenting from THAT VC, fully isolates the picker from SwiftUI and fixes
/// touch routing.
struct PDFPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPicked: (PDFDocument) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()   // invisible host — used only to access the window scene
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        let coord = context.coordinator
        if isPresented && coord.pickerWindow == nil {
            // Resolve the active window scene. Prefer the host view's scene;
            // fall back to the first foreground scene if host isn't yet in a window.
            let scene: UIWindowScene? =
                host.view.window?.windowScene ??
                UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })
            guard let scene else { return }

            // Build a dedicated transparent window. Its root VC is a plain
            // UIViewController with no SwiftUI involvement — this is what
            // allows UIDocumentPickerViewController to receive touches normally.
            let win = UIWindow(windowScene: scene)
            let rootVC = UIViewController()
            rootVC.view.backgroundColor = .clear
            win.rootViewController = rootVC
            win.windowLevel = .alert
            win.backgroundColor = .clear
            win.makeKeyAndVisible()
            coord.pickerWindow = win

            // Use .import mode: the system downloads+copies the file locally before
            // calling the delegate. This avoids the iCloud open-in-place coordination
            // that forOpeningContentTypes requires — that coordination fails silently
            // for iCloud files in our presentation context, so Recents updates but
            // no selection checkmark ever appears.
            let picker = UIDocumentPickerViewController(documentTypes: ["com.adobe.pdf"], in: .import)
            picker.delegate = coord
            picker.allowsMultipleSelection = false
            coord.presentedPicker = picker
            rootVC.present(picker, animated: true)

        } else if !isPresented && coord.pickerWindow != nil {
            coord.dismissPicker()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: PDFPickerPresenter
        var pickerWindow: UIWindow?
        weak var presentedPicker: UIDocumentPickerViewController?

        init(_ parent: PDFPickerPresenter) { self.parent = parent }

        func dismissPicker() {
            presentedPicker?.dismiss(animated: true)
            presentedPicker = nil
            // Hiding the window resigns key status, restoring the app's main window.
            pickerWindow?.isHidden = true
            pickerWindow = nil
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            // In .import mode the system already copied the file to a local inbox
            // path — no security-scoped access or manual copy needed.
            guard let url = urls.first, let doc = PDFDocument(url: url) else {
                dismissPicker()
                parent.isPresented = false
                return
            }
            dismissPicker()
            parent.isPresented = false
            parent.onPicked(doc)
            // Don't delete url here — importPDF renders pages asynchronously via
            // Task.detached; PDFDocument page data is lazily loaded from the file.
            // The system cleans the Documents/Inbox on next launch.
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            dismissPicker()
            parent.isPresented = false
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
            // Use a concrete type from the provider's registered identifiers —
            // the abstract "public.image" supertype fails silently on most pickers.
            let typeId = result.itemProvider.registeredTypeIdentifiers
                .first { UTType($0)?.conforms(to: .image) == true }
                ?? UTType.jpeg.identifier
            result.itemProvider.loadDataRepresentation(forTypeIdentifier: typeId) { data, _ in
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
    var onImportCompleted: (() -> Void)? = nil
    var onMediaInserted: ((PageMediaItem) -> Void)? = nil

    @State private var showingActionSheet = false
    @State private var showingPDFPicker = false
    @State private var showingPhotoPicker = false
    @State private var showingProgress = false
    @State private var isForExistingNotebook = false
    // On iPad, confirmationDialog is a UIPopoverPresentationController. Presenting
    // a second sheet before its dismissal animation completes causes UIKit to drop
    // the presentation silently. Store intent here; onChange fires after SwiftUI
    // commits the state change, then asyncAfter waits for the UIKit animation.
    @State private var pendingPicker: PendingPicker = .none

    private enum PendingPicker { case none, pdf, photo }

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
                pendingPicker = .pdf
            }
            if case .notebook = mode {
                Button("PDF → Add pages here") {
                    isForExistingNotebook = true
                    pendingPicker = .pdf
                }
                Button("Insert Image on this page") {
                    pendingPicker = .photo
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        // Wait for the confirmation dialog's dismissal animation to finish before
        // presenting the file/photo picker. 0.35 s covers iPad popover animation.
        .onChange(of: showingActionSheet) { _, isShowing in
            guard !isShowing else { return }
            let pending = pendingPicker
            pendingPicker = .none
            guard pending != .none else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                switch pending {
                case .pdf:   showingPDFPicker   = true
                case .photo: showingPhotoPicker = true
                case .none:  break
                }
            }
        }
        // Present UIDocumentPickerViewController modally via an invisible host VC.
        // SwiftUI's .fileImporter and .sheet both embed the picker as a child VC,
        // which breaks file-tap registration on iPadOS.
        .background(
            PDFPickerPresenter(isPresented: $showingPDFPicker) { doc in
                showingProgress = true
                let forExisting = isForExistingNotebook
                Task { @MainActor in
                    await importPDF(doc: doc, forExistingNotebook: forExisting)
                    showingProgress = false
                }
            }
            .frame(width: 0, height: 0)
        )
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
    private func importPDF(doc: PDFDocument, forExistingNotebook: Bool) async {
        let pageCount = doc.pageCount
        let title = doc.documentURL?.deletingPathExtension().lastPathComponent ?? "Imported"

        if forExistingNotebook, case .notebook(let nb, _) = mode {
            // Append pages one at a time — render + write + release to avoid
            // holding all PNG blobs in memory simultaneously.
            for i in 0..<pageCount {
                guard let pdfPage = doc.page(at: i) else { continue }
                let blob = await Task.detached(priority: .userInitiated) {
                    PDFImporter.renderPage(pdfPage)
                }.value
                guard let page = try? container.pages.append(notebookId: nb.id, template: .blank) else { continue }
                let item = PageMediaItem(
                    id: UUID().uuidString, pageId: page.id, sortIndex: 0,
                    imageBlob: blob, x: 0, y: 0, width: 1, height: 1,
                    createdAt: Date()
                )
                try? container.pageMedia.insert(item)
            }
            onImportCompleted?()
        } else {
            guard let nb = try? container.notebooks.create(title: title, coverColor: "#4A90E2") else { return }
            for i in 0..<pageCount {
                guard let pdfPage = doc.page(at: i) else { continue }
                let blob = await Task.detached(priority: .userInitiated) {
                    PDFImporter.renderPage(pdfPage)
                }.value
                guard let page = try? container.pages.append(notebookId: nb.id, template: .blank) else { continue }
                let item = PageMediaItem(
                    id: UUID().uuidString, pageId: page.id, sortIndex: 0,
                    imageBlob: blob, x: 0, y: 0, width: 1, height: 1,
                    createdAt: Date()
                )
                try? container.pageMedia.insert(item)
            }
            onNewNotebookCreated?(nb)
            onImportCompleted?()
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
