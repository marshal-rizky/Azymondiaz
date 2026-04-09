import SwiftUI
import PencilKit

struct NotebookView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.colorScheme) private var colorScheme

    let notebook: Notebook
    @State private var viewModel: NotebookViewModel?
    @State private var showingShareSheet = false
    @State private var pdfData: Data?

    var body: some View {
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
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let vm = viewModel {
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
    }

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
                isDark: colorScheme == .dark
            )
            .background(Color(.secondarySystemBackground))
        } else {
            Text("No page")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

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
