// ios/NotesApp/Features/Notebook/TransformResultView.swift
import SwiftUI

struct TransformResultView: View {
    let response: TransformResponse
    let onInsertBelow: (String) -> Void
    let onReplace: (String) -> Void
    let onDismiss: () -> Void
    var onSendToChat: ((String) -> Void)? = nil

    var body: some View {
        ZStack {
            AppColors.surface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("AI result")
                        .font(AppFonts.bodyBold)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text(response.modelUsed)
                        .font(AppFonts.micro)
                        .foregroundStyle(AppColors.textTertiary)
                }
                MathWebView(content: payloadText)
                    .frame(minHeight: 120, maxHeight: 300)
                    .background(AppColors.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))

                HStack(spacing: 10) {
                    if let sendToChat = onSendToChat {
                        Button("Ask in Chat") { sendToChat(payloadText) }
                            .font(AppFonts.caption).fontWeight(.semibold)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(AppColors.goldGradient)
                            .clipShape(Capsule())
                    }
                    Button("Insert below") { onInsertBelow(payloadText) }
                        .font(AppFonts.caption).fontWeight(.semibold)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(AppColors.surface2)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppColors.border, lineWidth: 0.5))
                    Button("Replace") { onReplace(payloadText) }
                        .font(AppFonts.caption).fontWeight(.semibold)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(AppColors.surface2)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppColors.border, lineWidth: 0.5))
                    Spacer()
                    Button("Dismiss") { onDismiss() }
                        .font(AppFonts.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(16)
        }
        .frame(width: 420)
    }

    private var payloadText: String {
        response.text ?? response.markdown ?? response.svg ?? ""
    }
}
