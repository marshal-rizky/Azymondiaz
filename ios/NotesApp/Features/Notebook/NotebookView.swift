import SwiftUI
import PencilKit

struct NotebookView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.colorScheme) private var colorScheme

    let notebook: Notebook
    @State private var viewModel: NotebookViewModel?
    @State private var showingShareSheet = false
    @State private var pdfData: Data?

    // Tool picker state (replaces PKToolPicker)
    @State private var activePenType: PKInkingTool.InkType = .pen
    @State private var activeColor: Color = AppColors.textPrimary

    // AI state
    @State private var showingLassoMenu = false
    @State private var showingTransformResult: TransformResponse? = nil
    @State private var transformInFlight = false
    @State private var transformError: String? = nil
    @State private var showingChat = false
    @State private var chatVM: ChatViewModel? = nil
    @State private var aiSelectionMode = false
    @State private var lassoSelectionBounds: CGRect? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            mainContent
            if showingChat, let cvm = chatVM {
                ChatPanelView(viewModel: cvm, onClose: { showingChat = false })
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showingChat)
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.surface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportPDF(vm: viewModel!)
                } label: {
                    Text("Export PDF")
                        .font(AppFonts.caption).fontWeight(.semibold)
                        .foregroundStyle(AppColors.gold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.surface3)
                        .clipShape(Capsule())
                }
                .disabled(viewModel == nil)
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
        .onChange(of: showingChat) { _, isShowing in
            if isShowing {
                if chatVM == nil { rebuildChatVM() }
            } else {
                chatVM = nil
            }
        }
        .onChange(of: viewModel?.currentPageIndex) { _, _ in
            aiSelectionMode = false
            lassoSelectionBounds = nil
            if showingChat { rebuildChatVM() }
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
                onDismiss: { showingTransformResult = nil },
                onSendToChat: { text in
                    showingTransformResult = nil
                    rebuildChatVM(injectedMessage: text)
                    withAnimation { showingChat = true }
                }
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
            actionBar
            if aiSelectionMode {
                aiBanner
            } else if container.aiRouter.activeLabel == "groq" {
                routingBadge(text: "Groq fallback")
            } else if !container.aiRouter.isConfigured {
                routingBadge(text: "AI offline — configure in Settings")
            }
            HStack(spacing: 0) {
                if let vm = viewModel {
                    pageStrip(vm: vm)
                        .frame(width: 88)
                        .background(AppColors.surface)
                    Divider().background(AppColors.border)
                    canvasArea(vm: vm)
                } else {
                    ProgressView().tint(AppColors.gold)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 3) {
            // Undo / Redo
            abBtn(icon: "arrow.uturn.backward") { /* TODO: undo */ }
            abBtn(icon: "arrow.uturn.forward")  { /* TODO: redo */ }
            abSep

            // Tools
            abToolBtn(icon: "pencil.tip",  penType: .pen)
            abToolBtn(icon: "pencil",       penType: .pencil)
            abToolBtn(icon: "squareshape.dotted.squareshape", penType: nil)  // eraser stub
            abBtn(icon: "lasso") { /* TODO: lasso */ }
            abSep

            // Colors
            ForEach([AppColors.textPrimary, AppColors.gold,
                     Color(hex: "#5C6BC0")!, Color(hex: "#26A69A")!], id: \.self) { color in
                colorDot(color)
            }
            abSep

            // AI + Chat
            abBtn(icon: "sparkles", isActive: aiSelectionMode) {
                aiSelectionMode = true
            }
            .popover(isPresented: $showingLassoMenu) {
                LassoMenuView(
                    onSelect: { action in Task { await runTransform(action: action) } },
                    onDismiss: { showingLassoMenu = false }
                )
                .presentationCompactAdaptation(.popover)
            }
            abBtn(icon: "bubble.left.and.bubble.right", isActive: showingChat) {
                showingChat.toggle()
            }

            Spacer()

            // Page actions
            if let vm = viewModel {
                Menu {
                    Button("Line")  { vm.addPage(template: .line) }
                    Button("Grid")  { vm.addPage(template: .grid) }
                    Button("Blank") { vm.addPage(template: .blank) }
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 30, height: 30)
                }
                abBtn(icon: "trash", role: .destructive) { vm.deleteCurrentPage() }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(AppColors.surface2)
        .overlay(alignment: .bottom) { Divider().background(AppColors.border) }
    }

    @ViewBuilder
    private func abBtn(icon: String,
                       isActive: Bool = false,
                       role: ButtonRole? = nil,
                       action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isActive ? AppColors.gold : AppColors.textSecondary)
                .frame(width: 30, height: 30)
                .background(isActive ? AppColors.gold.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    @ViewBuilder
    private func abToolBtn(icon: String, penType: PKInkingTool.InkType?) -> some View {
        let isActive = penType != nil && activePenType == penType
        Button {
            if let pt = penType {
                activePenType = pt
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isActive ? .black : AppColors.textSecondary)
                .frame(width: 30, height: 30)
                .background(isActive
                            ? AppColors.goldGradient
                            : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    @ViewBuilder
    private func colorDot(_ color: Color) -> some View {
        let isActive = activeColor == color
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(isActive ? AppColors.gold : Color.clear, lineWidth: 2).padding(-2))
            .onTapGesture { activeColor = color }
    }

    private var abSep: some View {
        Rectangle()
            .fill(AppColors.border2)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }

    private var aiBanner: some View {
        HStack {
            Image(systemName: "sparkles").foregroundStyle(.black)
            Text("Drag with finger to select a region for AI")
                .font(AppFonts.caption).fontWeight(.semibold)
                .foregroundStyle(.black)
            Spacer()
            Button("Cancel") { aiSelectionMode = false }
                .font(AppFonts.caption)
                .foregroundStyle(.black.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(AppColors.goldGradient)
    }

    private func routingBadge(text: String) -> some View {
        HStack {
            Spacer()
            Text(text)
                .font(AppFonts.micro).fontWeight(.semibold)
                .foregroundStyle(AppColors.gold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppColors.gold.opacity(0.1))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AppColors.gold.opacity(0.2), lineWidth: 0.5))
            Spacer()
        }
        .padding(.vertical, 4)
        .background(AppColors.surface)
    }

    // MARK: - Active tool

    private var currentPKTool: PKTool {
        let uiColor = UIColor(activeColor)
        switch activePenType {
        case .pen:     return PKInkingTool(.pen,    color: uiColor, width: 2)
        case .pencil:  return PKInkingTool(.pencil, color: uiColor, width: 2)
        case .marker:  return PKInkingTool(.marker, color: uiColor, width: 10)
        default:       return PKInkingTool(.pen,    color: uiColor, width: 2)
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
            .padding(8)
        }
    }

    private func pageStripThumb(page: Page, isSelected: Bool) -> some View {
        VStack(spacing: 3) {
            Group {
                if let blob = page.thumbnailBlob, let img = UIImage(data: blob) {
                    Image(uiImage: img).resizable().scaledToFit()
                } else {
                    Rectangle().fill(AppColors.surface3)
                }
            }
            .aspectRatio(3.0/4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.thumb))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.thumb)
                    .stroke(isSelected ? AppColors.gold : AppColors.border,
                            lineWidth: isSelected ? 2 : 0.5)
            )
            .shadow(color: isSelected ? AppColors.gold.opacity(0.25) : .black.opacity(0.3),
                    radius: isSelected ? 4 : 2, y: 1)
            Text("\(page.pageIndex + 1)")
                .font(AppFonts.micro)
                .foregroundStyle(AppColors.textTertiary)
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
                isDark: false,
                aiSelectionMode: $aiSelectionMode,
                onAIRegionSelected: { rect in
                    lassoSelectionBounds = rect
                    showingLassoMenu = true
                },
                activeTool: currentPKTool
            )
            .background(AppColors.canvasPaper)
        } else {
            Text("No page")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - AI transform

    private struct IdentifiableResponse: Identifiable {
        let id = UUID()
        let wrapped: TransformResponse
    }

    @MainActor
    private func rebuildChatVM(lassoBase64: String? = nil, injectedMessage: String? = nil) {
        guard let vm = viewModel, let page = vm.currentPage else { return }
        chatVM = ChatViewModel(
            page: page,
            notebookPages: vm.pages,
            repo: container.aiMessages,
            router: container.aiRouter,
            overrideContextBase64: lassoBase64,
            injectedAssistantMessage: injectedMessage
        )
    }

    @MainActor
    private func runTransform(action: AIAction) async {
        guard let vm = viewModel else { return }
        vm.flushSave()
        let drawing = vm.currentDrawing
        let bounds: CGRect
        if let sel = lassoSelectionBounds, sel.width > 5, sel.height > 5 {
            bounds = sel
        } else if drawing.bounds.isEmpty {
            bounds = CGRect(origin: .zero, size: pageSize)
        } else {
            bounds = drawing.bounds.insetBy(dx: -10, dy: -10)
        }
        lassoSelectionBounds = nil
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
