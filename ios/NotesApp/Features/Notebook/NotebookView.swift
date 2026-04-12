import SwiftUI
import PencilKit

struct NotebookView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.colorScheme) private var colorScheme

    let notebook: Notebook
    @State private var viewModel: NotebookViewModel?
    @State private var showingShareSheet = false
    @State private var pdfData: Data?

    // AI state
    @State private var showingLassoMenu = false
    @State private var showingTransformResult: TransformResponse? = nil
    @State private var transformInFlight = false
    @State private var transformError: String? = nil
    @State private var showingChat = false

    var body: some View {
        HStack(spacing: 0) {
            mainContent
            if showingChat, let vm = viewModel, let page = vm.currentPage {
                Divider()
                ChatPanelView(
                    viewModel: ChatViewModel(
                        page: page,
                        notebookPages: vm.pages,
                        repo: container.aiMessages,
                        router: container.aiRouter
                    ),
                    onClose: { showingChat = false }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let vm = viewModel {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingChat.toggle()
                    } label: {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingLassoMenu = true
                    } label: {
                        Label("AI", systemImage: "sparkles")
                    }
                    .disabled(transformInFlight)
                    .popover(isPresented: $showingLassoMenu) {
                        LassoMenuView(
                            onSelect: { action in Task { await runTransform(action: action) } },
                            onDismiss: { showingLassoMenu = false }
                        )
                        .presentationCompactAdaptation(.popover)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Line") { vm.addPage(template: .line) }
                        Button("Grid") { vm.addPage(template: .grid) }
                        Button("Blank") { vm.addPage(template: .blank) }
                    } label: {
                        Label("Add page", systemImage: "plus.square")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportPDF(vm: vm)
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        vm.deleteCurrentPage()
                    } label: {
                        Label("Delete page", systemImage: "trash")
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                let vm = NotebookViewModel(notebook: notebook, repo: container.pages)
                vm.load()
                viewModel = vm
            }
        }
        .onDisappear {
            viewModel?.flushSave()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let data = pdfData {
                ShareSheet(items: [PDFActivityItem(data: data, title: notebook.title)])
            }
        }
        .sheet(item: Binding(
            get: { showingTransformResult.map { IdentifiableResponse(wrapped: $0) } },
            set: { showingTransformResult = $0?.wrapped }
        )) { item in
            TransformResultView(
                response: item.wrapped,
                onInsertBelow: { text in
                    UIPasteboard.general.string = text
                    showingTransformResult = nil
                },
                onReplace: { text in
                    UIPasteboard.general.string = text
                    showingTransformResult = nil
                },
                onDismiss: { showingTransformResult = nil }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("AI error", isPresented: Binding(
            get: { transformError != nil },
            set: { if !$0 { transformError = nil } }
        ), actions: {
            Button("OK") { transformError = nil }
        }, message: {
            Text(transformError ?? "")
        })
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            if !container.aiRouter.isConfigured {
                Text("AI offline — configure in Settings")
                    .font(.caption)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
            } else if container.aiRouter.activeLabel == "groq" {
                Text("Using Groq fallback")
                    .font(.caption)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.2))
            }
            HStack(spacing: 0) {
                if let vm = viewModel {
                    pageStrip(vm: vm)
                        .frame(width: 140)
                        .background(Color(.secondarySystemBackground))
                    Divider()
                    canvasArea(vm: vm)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Page strip

    private func pageStrip(vm: NotebookViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(vm.pages.enumerated()), id: \.element.id) { index, page in
                    Button {
                        vm.selectPage(index: index)
                    } label: {
                        pageStripThumb(page: page, isSelected: index == vm.currentPageIndex)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private func pageStripThumb(page: Page, isSelected: Bool) -> some View {
        VStack(spacing: 4) {
            Group {
                if let blob = page.thumbnailBlob, let img = UIImage(data: blob) {
                    Image(uiImage: img).resizable().scaledToFit()
                } else {
                    Rectangle().fill(Color(.systemBackground))
                }
            }
            .aspectRatio(3.0/4.0, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                            lineWidth: isSelected ? 2 : 1)
            )
            Text("\(page.pageIndex + 1)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private let pageSize = CGSize(width: 1024, height: 1366)

    // MARK: - Canvas area

    @ViewBuilder
    private func canvasArea(vm: NotebookViewModel) -> some View {
        if let page = vm.currentPage {
            CanvasView(
                drawing: Binding(
                    get: { vm.currentDrawing },
                    set: { vm.currentDrawing = $0 }
                ),
                allowsFingerDrawing: false,
                template: page.template,
                pageSize: pageSize,
                isDark: false  // Page is always white; dark mode applies to chrome, not paper
            )
            .background(Color(.secondarySystemBackground))
        } else {
            Text("No page")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - AI transform

    private struct IdentifiableResponse: Identifiable {
        let id = UUID()
        let wrapped: TransformResponse
    }

    @MainActor
    private func runTransform(action: AIAction) async {
        guard let vm = viewModel else { return }
        vm.flushSave()
        let drawing = vm.currentDrawing
        let bounds = drawing.bounds.isEmpty
            ? CGRect(origin: .zero, size: pageSize)
            : drawing.bounds.insetBy(dx: -10, dy: -10)
        let base64 = LassoRasterizer.rasterize(selection: drawing, bounds: bounds)
        guard !base64.isEmpty else {
            transformError = "Nothing to transform — draw something first."
            return
        }
        transformInFlight = true
        defer { transformInFlight = false }
        do {
            let response = try await container.aiRouter.transform(
                TransformRequest(action: action, imageBase64: base64, contextText: nil)
            )
            showingTransformResult = response
        } catch {
            transformError = error.localizedDescription
        }
    }

    // MARK: - PDF export

    private func exportPDF(vm: NotebookViewModel) {
        vm.flushSave()
        let pageSize = CGSize(width: 1024, height: 1366)
        let renderables: [RenderablePage] = vm.pages.map { p in
            let drawing = (p.drawingBlob.flatMap { try? PKDrawing(data: $0) }) ?? PKDrawing()
            return RenderablePage(drawing: drawing, template: p.template, size: pageSize)
        }
        pdfData = PDFExporter.export(pages: renderables, isDark: false)
        showingShareSheet = pdfData != nil
    }
}

// MARK: - UIKit share sheet bridge

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private final class PDFActivityItem: NSObject, UIActivityItemSource {
    let data: Data
    let title: String
    init(data: Data, title: String) {
        self.data = data
        self.title = title
    }
    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        "\(title).pdf"
    }
    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType type: UIActivity.ActivityType?) -> Any? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(title).pdf")
        try? data.write(to: url)
        return url
    }
}
