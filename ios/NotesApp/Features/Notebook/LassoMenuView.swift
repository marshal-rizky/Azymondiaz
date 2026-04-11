import SwiftUI

struct LassoMenuView: View {
    let onSelect: (AIAction) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(.cleanup,   "Clean up handwriting", "wand.and.stars")
            row(.typedText, "Convert to typed text", "textformat")
            Divider()
            row(.math,      "Math mode",      "function")
            row(.physics,   "Physics mode",   "atom")
            row(.chemistry, "Chemistry mode", "flask")
            Divider()
            row(.explain,   "Explain this",   "lightbulb")
            row(.list,      "Turn into list", "list.bullet")
        }
        .padding(.vertical, 8)
        .frame(width: 260)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
    }

    private func row(_ action: AIAction, _ title: String, _ icon: String) -> some View {
        Button {
            onSelect(action)
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
