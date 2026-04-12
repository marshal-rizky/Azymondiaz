import SwiftUI

struct TransformResultView: View {
    let response: TransformResponse
    let onInsertBelow: (String) -> Void
    let onReplace: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI result")
                    .font(.headline)
                Spacer()
                Text(response.modelUsed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            MathWebView(content: payloadText)
                .frame(minHeight: 120, maxHeight: 300)
            HStack(spacing: 12) {
                Button("Insert below") { onInsertBelow(payloadText) }
                    .buttonStyle(.borderedProminent)
                Button("Replace") { onReplace(payloadText) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Dismiss") { onDismiss() }
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private var payloadText: String {
        response.text ?? response.markdown ?? response.svg ?? ""
    }
}
