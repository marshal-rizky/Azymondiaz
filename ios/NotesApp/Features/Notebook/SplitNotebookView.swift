import SwiftUI

@Observable
final class SplitState {
    var isSplit: Bool = false
    var leftSessionID: UUID?
    var rightSessionID: UUID?
    var splitRatio: CGFloat = 0.5
    var focusedPane: Pane = .left

    enum Pane { case left, right }
}

struct SplitNotebookView: View {
    let initialNotebook: Notebook
    @Environment(AppContainer.self) private var container
    @State private var splitState = SplitState()
    @State private var showingRightTabSheet = false
    @State private var showingAddTabSheet = false
    @Environment(\.dismiss) private var dismiss

    private var sessions: OpenSessionsManager { container.sessions }

    var body: some View {
        GeometryReader { geo in
            if splitState.isSplit,
               let leftID = splitState.leftSessionID,
               let rightID = splitState.rightSessionID,
               let leftSession = sessions.session(id: leftID),
               let rightSession = sessions.session(id: rightID) {
                splitLayout(geo: geo, leftSession: leftSession, rightSession: rightSession)
            } else if let leftID = splitState.leftSessionID,
                      let leftSession = sessions.session(id: leftID) {
                NotebookView(
                    notebook: leftSession.notebook,
                    sessionID: leftID,
                    onSplit: { showingRightTabSheet = true },
                    onAdd: { showingAddTabSheet = true }
                )
            } else {
                ProgressView().tint(AppColors.gold)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            guard splitState.leftSessionID == nil else { return }
            let session = sessions.open(initialNotebook)
            splitState.leftSessionID = session.id
        }
        .onDisappear {
            if let id = splitState.leftSessionID  { sessions.close(sessionID: id) }
            if let id = splitState.rightSessionID { sessions.close(sessionID: id) }
        }
        .sheet(isPresented: $showingRightTabSheet) {
            NotebookPickerSheet { selectedNotebook in
                let s = sessions.open(selectedNotebook)
                splitState.rightSessionID = s.id
                splitState.isSplit = true
                showingRightTabSheet = false
            }
        }
        .sheet(isPresented: $showingAddTabSheet) {
            NotebookPickerSheet { selectedNotebook in
                sessions.open(selectedNotebook)
                showingAddTabSheet = false
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private func splitLayout(geo: GeometryProxy,
                             leftSession: NotebookSession,
                             rightSession: NotebookSession) -> some View {
        let isLandscape = geo.size.width >= 768
        let dividerThickness: CGFloat = 4

        if isLandscape {
            HStack(spacing: 0) {
                NotebookView(
                    notebook: leftSession.notebook,
                    sessionID: splitState.leftSessionID,
                    showTabBar: false
                )
                .frame(width: geo.size.width * splitState.splitRatio - dividerThickness / 2)
                .contentShape(Rectangle())
                .onTapGesture { splitState.focusedPane = .left }

                divider(geo: geo, isLandscape: true)

                NotebookView(
                    notebook: rightSession.notebook,
                    sessionID: splitState.rightSessionID,
                    showTabBar: false
                )
                .frame(width: geo.size.width * (1 - splitState.splitRatio) - dividerThickness / 2)
                .overlay(alignment: .topTrailing) { unsplitButton }
                .contentShape(Rectangle())
                .onTapGesture { splitState.focusedPane = .right }
                .opacity(splitState.focusedPane == .right ? 1 : 0.97)
            }
        } else {
            VStack(spacing: 0) {
                NotebookView(
                    notebook: leftSession.notebook,
                    sessionID: splitState.leftSessionID,
                    showTabBar: false
                )
                .frame(height: geo.size.height * splitState.splitRatio - dividerThickness / 2)

                divider(geo: geo, isLandscape: false)

                NotebookView(
                    notebook: rightSession.notebook,
                    sessionID: splitState.rightSessionID,
                    showTabBar: false
                )
                .frame(height: geo.size.height * (1 - splitState.splitRatio) - dividerThickness / 2)
                .overlay(alignment: .topTrailing) { unsplitButton }
            }
        }
    }

    private func divider(geo: GeometryProxy, isLandscape: Bool) -> some View {
        let totalSize = isLandscape ? geo.size.width : geo.size.height
        return ZStack {
            Rectangle()
                .fill(AppColors.gold)
                .frame(
                    width: isLandscape ? 4 : nil,
                    height: isLandscape ? nil : 4
                )
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(
                    width: isLandscape ? 3 : 24,
                    height: isLandscape ? 24 : 3
                )
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    let newFraction = isLandscape
                        ? value.location.x / totalSize
                        : value.location.y / totalSize
                    splitState.splitRatio = min(0.7, max(0.3, newFraction))
                }
        )
        .frame(
            width: isLandscape ? 4 : nil,
            height: isLandscape ? nil : 4
        )
    }

    private var unsplitButton: some View {
        Button {
            if let id = splitState.rightSessionID { sessions.close(sessionID: id) }
            splitState.rightSessionID = nil
            splitState.isSplit = false
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                Text("UNSPLIT")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(AppColors.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.border, lineWidth: 0.5))
        }
        .padding(6)
    }
}

private struct NotebookPickerSheet: View {
    @Environment(AppContainer.self) private var container
    var onSelect: (Notebook) -> Void
    @State private var notebooks: [Notebook] = []

    var body: some View {
        NavigationStack {
            List(notebooks) { nb in
                Button(nb.title) {
                    onSelect(nb)
                }
                .foregroundStyle(AppColors.textPrimary)
            }
            .listStyle(.plain)
            .navigationTitle("Open Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            notebooks = (try? container.notebooks.fetchAll()) ?? []
        }
        .presentationDetents([.medium, .large])
    }
}
