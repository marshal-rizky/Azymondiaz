import SwiftUI
import PencilKit

enum ActiveTool: Equatable {
    case pen, pencil, marker, eraser, lasso
}

struct NotebookView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    let notebook: Notebook
    /// The session ID this pane is associated with. Passed by SplitNotebookView.
    var sessionID: UUID? = nil
    /// Called when the user taps SPLIT. Nil = split already active (hide the button).
    var onSplit: (() -> Void)? = nil
    /// Set to false in split-screen panes — the parent SplitNotebookView owns the tab bar.
    var showTabBar: Bool = true
    @State private var viewModel: NotebookViewModel?
    @State private var showingShareSheet = false
    @State private var pdfData: Data?

    // Tool state
    @State private var activeTool: ActiveTool = .pen
    @State private var activeColor: Color = AppColors.textPrimary
    @State private var activeSize: CGFloat = 2
    @State private var canvasUndoManager: UndoManager? = nil

    // UI state
    @State private var showingPages = false

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
        .navigationBarHidden(true)
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
            if showTabBar { tabBarRow }
            navBar
            toolbar2
            ZStack(alignment: .top) {
                canvasStack
                // Undo/redo — top left
                HStack {
                    undoRedoPill
                        .padding(.top, 14)
                        .padding(.leading, 14)
                    Spacer()
                    // AI + Chat — top right
                    aiChatPill
                        .padding(.top, 14)
                        .padding(.trailing, 14)
                }
                // Floating tool pill or AI banner — centered
                Group {
                    if aiSelectionMode {
                        aiBanner
                            .padding(.horizontal, 56)
                    } else {
                        toolPill
                    }
                }
                .padding(.top, 14)
                .frame(maxWidth: .infinity)
                // Pages slide-in panel
                if showingPages {
                    pagesPanelOverlay
                        .transition(.move(edge: .leading))
                }
            }
        }
        .background(AppColors.bg.ignoresSafeArea())
    }

    // MARK: - Nav bar (row 1)

    private var navBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 34, height: 34)
            }

            HStack(spacing: 6) {
                Text(notebook.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.chip)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))

            Spacer()

            if let vm = viewModel {
                Button { exportPDF(vm: vm) } label: {
                    Text("Export PDF")
                        .font(AppFonts.caption).fontWeight(.semibold)
                        .foregroundStyle(AppColors.gold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.gold.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppColors.gold.opacity(0.2), lineWidth: 0.5))
                }
            }

            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 30, height: 30)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(AppColors.navBar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1)
        }
    }

    // MARK: - Toolbar row 2

    private var toolbar2: some View {
        HStack(spacing: 2) {
            tb2Btn(icon: "sidebar.left", isActive: showingPages) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingPages.toggle()
                }
            }
            tb2Btn(icon: "magnifyingglass") {}
            tb2Btn(icon: "arrow.uturn.backward",
                   disabled: !(canvasUndoManager?.canUndo ?? false)) {
                canvasUndoManager?.undo()
            }
            tb2Btn(icon: "arrow.uturn.forward",
                   disabled: !(canvasUndoManager?.canRedo ?? false)) {
                canvasUndoManager?.redo()
            }
            if let vm = viewModel {
                tb2Btn(
                    icon: vm.currentPageIsDark ? "sun.min" : "moon",
                    isActive: vm.currentPageIsDark
                ) {
                    vm.toggleCurrentPageTheme()
                }
            }

            tb2Sep

            tb2Btn(icon: "sparkles", isActive: aiSelectionMode) { aiSelectionMode = true }
            tb2Btn(icon: "bubble.left.and.bubble.right", isActive: showingChat) { showingChat.toggle() }

            Spacer()

            if container.aiRouter.activeLabel == "groq" {
                routingBadge(text: "Groq fallback")
            } else if !container.aiRouter.isConfigured {
                routingBadge(text: "AI offline")
            }

            tb2Sep

            if let vm = viewModel {
                Menu {
                    Button("Line")  { vm.addPage(template: .line) }
                    Button("Grid")  { vm.addPage(template: .grid) }
                    Button("Blank") { vm.addPage(template: .blank) }
                    Button("Cornell") { vm.addPage(template: .cornell) }
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 30, height: 30)
                }
                tb2Btn(icon: "trash", role: .destructive) { vm.deleteCurrentPage() }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(AppColors.navBar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func tb2Btn(
        icon: String,
        isActive: Bool = false,
        disabled: Bool = false,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(
                    disabled ? AppColors.textTertiary :
                    isActive  ? AppColors.gold : AppColors.textSecondary
                )
                .frame(width: 30, height: 30)
                .background(isActive ? AppColors.gold.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .disabled(disabled)
    }

    private var tb2Sep: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private func routingBadge(text: String) -> some View {
        Text(text)
            .font(AppFonts.micro).fontWeight(.semibold)
            .foregroundStyle(AppColors.gold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppColors.gold.opacity(0.1))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AppColors.gold.opacity(0.2), lineWidth: 0.5))
    }

    // MARK: - Tab bar row

    @ViewBuilder
    private var tabBarRow: some View {
        NotebookTabBar(
            sessions: container.sessions.sessions,
            activeSessionID: Binding(
                get: { sessionID ?? container.sessions.activeSessionID },
                set: { container.sessions.activeSessionID = $0 }
            ),
            onClose: { id in container.sessions.close(sessionID: id) },
            onAdd: { /* handled by SplitNotebookView in Task 7 */ },
            onSplit: onSplit
        )
    }

    // MARK: - Floating tool pill

    private let toolSizes: [CGFloat] = [1.5, 3, 6]

    private var toolPill: some View {
        HStack(spacing: 3) {
            toolPillBtn(icon: "pencil.tip",  tool: .pen)
            toolPillBtn(icon: "pencil",       tool: .pencil)
            toolPillBtn(icon: "highlighter",  tool: .marker)
            toolPillBtn(icon: "eraser",       tool: .eraser)
            toolPillBtn(icon: "lasso",        tool: .lasso)
                .popover(isPresented: $showingLassoMenu) {
                    LassoMenuView(
                        onSelect: { action in Task { await runTransform(action: action) } },
                        onDismiss: { showingLassoMenu = false }
                    )
                    .presentationCompactAdaptation(.popover)
                }

            pillSep

            if activeTool != .eraser && activeTool != .lasso {
                ForEach(toolSizes, id: \.self) { size in
                    let isActive = activeSize == size
                    Circle()
                        .fill(isActive ? AppColors.textPrimary : AppColors.textSecondary)
                        .frame(width: max(4, size * 2.2), height: max(4, size * 2.2))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(isActive ? AppColors.gold : Color.clear, lineWidth: 1.5)
                                .padding(-4)
                        )
                        .onTapGesture { activeSize = size }
                }
                pillSep
            }

            if activeTool != .eraser && activeTool != .lasso {
                let palette: [Color] = [
                    AppColors.textPrimary,
                    AppColors.gold,
                    Color(hex: "#5C6BC0")!,
                    Color(hex: "#E53935")!,
                    Color(hex: "#26A69A")!
                ]
                ForEach(palette, id: \.self) { color in
                    let isActive = activeColor == color
                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(isActive ? AppColors.gold : Color.clear, lineWidth: 2)
                                .padding(-3)
                        )
                        .onTapGesture { activeColor = color }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .background(AppColors.surface2.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }

    @ViewBuilder
    private func toolPillBtn(icon: String, tool: ActiveTool) -> some View {
        let isActive = activeTool == tool
        Button { activeTool = tool } label: {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isActive ? Color.black : AppColors.textSecondary)
                .frame(width: 34, height: 34)
                .background(
                    isActive
                    ? AnyView(AppColors.goldGradient.clipShape(RoundedRectangle(cornerRadius: 9)))
                    : AnyView(Color.clear)
                )
        }
    }

    private var pillSep: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 3)
    }

    // MARK: - AI banner (replaces tool pill when active)

    private var aiBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13))
                .foregroundStyle(.black)
            Text("Drag with finger to select a region")
                .font(AppFonts.caption).fontWeight(.semibold)
                .foregroundStyle(.black)
            Spacer()
            Button("Cancel") { aiSelectionMode = false }
                .font(AppFonts.caption).fontWeight(.medium)
                .foregroundStyle(.black.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppColors.goldGradient)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: AppColors.gold.opacity(0.3), radius: 8, y: 3)
    }

    // MARK: - Undo / Redo pill

    private var undoRedoPill: some View {
        HStack(spacing: 2) {
            Button { canvasUndoManager?.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        (canvasUndoManager?.canUndo ?? false)
                        ? AppColors.textSecondary : AppColors.textTertiary
                    )
                    .frame(width: 32, height: 30)
            }
            .disabled(!(canvasUndoManager?.canUndo ?? false))

            Button { canvasUndoManager?.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        (canvasUndoManager?.canRedo ?? false)
                        ? AppColors.textSecondary : AppColors.textTertiary
                    )
                    .frame(width: 32, height: 30)
            }
            .disabled(!(canvasUndoManager?.canRedo ?? false))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .background(AppColors.surface2.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }

    // MARK: - AI + Chat pill

    private var aiChatPill: some View {
        VStack(spacing: 2) {
            Button { aiSelectionMode = true } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(aiSelectionMode ? AppColors.gold : AppColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(aiSelectionMode ? AppColors.gold.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 20, height: 0.5)
            Button { showingChat.toggle() } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 14))
                    .foregroundStyle(showingChat ? AppColors.gold : AppColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(showingChat ? AppColors.gold.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .background(AppColors.surface2.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }

    // MARK: - Canvas stack

    private var canvasStack: some View {
        Group {
            if let vm = viewModel {
                canvasArea(vm: vm)
            } else {
                ProgressView()
                    .tint(AppColors.gold)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.bg)
    }

    // MARK: - Pages panel overlay

    private var pagesPanelOverlay: some View {
        HStack(spacing: 0) {
            if let vm = viewModel {
                VStack(spacing: 0) {
                    HStack {
                        Text("Pages")
                            .font(AppFonts.bodyBold)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingPages = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(AppColors.surface3)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColors.surface)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(AppColors.border).frame(height: 0.5)
                    }

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(vm.pages.enumerated()), id: \.element.id) { idx, page in
                                Button { vm.selectPage(index: idx) } label: {
                                    pageStripThumb(page: page, isSelected: idx == vm.currentPageIndex)
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                vm.addPage(template: vm.currentPage?.template ?? .blank)
                            } label: {
                                RoundedRectangle(cornerRadius: AppRadius.thumb)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                    .foregroundStyle(AppColors.border2)
                                    .aspectRatio(3.0/4.0, contentMode: .fit)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.system(size: 18, weight: .light))
                                            .foregroundStyle(AppColors.gold)
                                    )
                            }
                        }
                        .padding(10)
                    }
                }
                .frame(width: 130)
                .background(AppColors.surface)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(AppColors.border).frame(width: 0.5)
                }
            }
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Page strip thumb (reused in pages panel)

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

    // MARK: - Canvas area

    private let pageSize = CGSize(width: 1024, height: 1366)

    private var currentPKTool: PKTool {
        let uiColor = UIColor(activeColor)
        switch activeTool {
        case .pen:     return PKInkingTool(.pen,    color: uiColor, width: activeSize)
        case .pencil:  return PKInkingTool(.pencil, color: uiColor, width: activeSize)
        case .marker:  return PKInkingTool(.marker, color: uiColor.withAlphaComponent(0.5), width: activeSize * 5)
        case .eraser:  return PKEraserTool(.bitmap)
        case .lasso:   return PKLassoTool()
        }
    }

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
                isDark: vm.currentPageIsDark,
                aiSelectionMode: $aiSelectionMode,
                onAIRegionSelected: { rect in
                    lassoSelectionBounds = rect
                    showingLassoMenu = true
                },
                activeTool: currentPKTool,
                undoManager: $canvasUndoManager
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
