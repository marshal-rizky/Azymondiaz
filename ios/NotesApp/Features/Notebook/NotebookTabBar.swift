import SwiftUI

struct NotebookTabBar: View {
    let sessions: [NotebookSession]
    @Binding var activeSessionID: UUID?
    var onClose: (UUID) -> Void
    var onAdd: () -> Void
    var onSplit: (() -> Void)?      // nil when split is already active
    var canAdd: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(sessions) { session in
                        tabItem(session: session)
                    }
                    addButton
                }
            }
            if let onSplit {
                splitButton(action: onSplit)
            }
        }
        .frame(height: 36)
        .background(Color(hex: "#0D1117")!)
    }

    @ViewBuilder
    private func tabItem(session: NotebookSession) -> some View {
        let isActive = session.id == activeSessionID
        HStack(spacing: 6) {
            Text(session.notebook.title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? AppColors.gold : AppColors.textSecondary)
                .lineLimit(1)
                .frame(minWidth: 100, maxWidth: 180, alignment: .leading)
            Button {
                onClose(session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isActive ? AppColors.textSecondary : Color(white: 0.35))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: isActive ? 32 : 28, alignment: .bottom)
        .background(
            isActive
            ? AppColors.navBar
            : Color(hex: "#0D1117")!
        )
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 6, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 6
        ))
        .onTapGesture { activeSessionID = session.id }
        .animation(.easeInOut(duration: 0.15), value: activeSessionID)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 13))
                .foregroundStyle(canAdd ? AppColors.gold : AppColors.textTertiary)
                .frame(width: 34, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
    }

    private func splitButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 10))
                Text("SPLIT")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(AppColors.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppColors.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}
