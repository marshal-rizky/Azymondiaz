// ios/NotesApp/Features/Chat/ChatPanelView.swift
import SwiftUI

struct ChatPanelView: View {
    @Bindable var viewModel: ChatViewModel
    let onClose: () -> Void

    @State private var panelHeight: CGFloat = 320
    @GestureState private var dragOffset: CGFloat = 0

    private let minHeight: CGFloat = 280
    private let maxHeight: CGFloat = UIScreen.main.bounds.height * 0.85
    private let handleHeight: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            Divider().background(AppColors.border)
            messages
            Divider().background(AppColors.border)
            inputBar
        }
        .frame(height: max(minHeight, min(maxHeight, panelHeight + dragOffset)))
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 20, y: -4)
        .onAppear { viewModel.load() }
        .alert("Chat error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        ), actions: { Button("OK") {} },
           message: { Text(viewModel.errorMessage ?? "") })
    }

    // MARK: - Handle

    private var handle: some View {
        VStack {
            Capsule()
                .fill(AppColors.border2)
                .frame(width: 36, height: 4)
        }
        .frame(height: handleHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = -value.translation.height
                }
                .onEnded { value in
                    panelHeight = max(minHeight, min(maxHeight,
                                                     panelHeight - value.translation.height))
                }
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Chat")
                    .font(AppFonts.bodyBold)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(AppColors.surface3)
                        .clipShape(Circle())
                }
            }
            // Scope toggle
            HStack(spacing: 2) {
                scopePill(label: "This page", scope: .page)
                scopePill(label: "Notebook",  scope: .notebook)
            }
            .padding(2)
            .background(AppColors.bg)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.chip)
                .stroke(AppColors.border, lineWidth: 0.5))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func scopePill(label: String, scope: ChatScope) -> some View {
        let isActive = viewModel.scope == scope
        Button { viewModel.scope = scope } label: {
            Text(label)
                .font(AppFonts.caption).fontWeight(.semibold)
                .foregroundStyle(isActive ? .black : AppColors.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isActive ? AppColors.goldGradient
                            : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip - 2))
        }
    }

    // MARK: - Messages

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if viewModel.messages.isEmpty {
                        welcomeChip
                    }
                    ForEach(viewModel.messages) { msg in
                        bubble(msg: msg).id(msg.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var welcomeChip: some View {
        Text("I can see your notes — ask me anything ✦")
            .font(AppFonts.caption)
            .foregroundStyle(AppColors.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AppColors.surface2)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.chip)
                .stroke(AppColors.border, lineWidth: 0.5))
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func bubble(msg: AIMessage) -> some View {
        let isUser = msg.role == .user
        HStack {
            if isUser { Spacer(minLength: 40) }
            bubbleContent(msg: msg, isUser: isUser)
            if !isUser { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private func bubbleContent(msg: AIMessage, isUser: Bool) -> some View {
        if isUser {
            Text(msg.text)
                .font(AppFonts.body)
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.goldGradient)
                .clipShape(ChatBubbleShape(isUser: true))
        } else if containsMath(msg.text) {
            MathWebView(content: msg.text)
                .frame(minHeight: 80, maxHeight: 400)
                .background(AppColors.surface2)
                .clipShape(ChatBubbleShape(isUser: false))
                .overlay(ChatBubbleShape(isUser: false)
                    .stroke(AppColors.border, lineWidth: 0.5))
        } else {
            Text(markdownAttr(msg.text))
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.surface2)
                .clipShape(ChatBubbleShape(isUser: false))
                .overlay(ChatBubbleShape(isUser: false)
                    .stroke(AppColors.border, lineWidth: 0.5))
        }
    }

    private func containsMath(_ text: String) -> Bool {
        text.contains("$") || text.contains("\\")
    }

    private func markdownAttr(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            MicButton { audio in Task { await viewModel.transcribe(audio: audio) } }
                .frame(width: 32, height: 32)
                .background(AppColors.surface2)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.chip)
                    .stroke(AppColors.border, lineWidth: 0.5))
            TextField("Ask anything…", text: $viewModel.inputText, axis: .vertical)
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppColors.surface2)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.chip)
                    .stroke(AppColors.border, lineWidth: 0.5))
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(
                        viewModel.isSending || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? LinearGradient(colors: [AppColors.surface3, AppColors.surface3], startPoint: .top, endPoint: .bottom)
                        : AppColors.goldGradient
                    )
                    .clipShape(Circle())
                    .shadow(color: AppColors.gold.opacity(0.35), radius: 4, y: 2)
            }
            .disabled(viewModel.isSending || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppColors.surface)
    }
}

// MARK: - Chat bubble shape (rounded with one tight corner)

private struct ChatBubbleShape: Shape {
    let isUser: Bool
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 14
        let tight: CGFloat = 4
        var p = Path()
        if isUser {
            p.addRoundedRect(in: rect, cornerRadii: .init(
                topLeading: r, bottomLeading: r, bottomTrailing: tight, topTrailing: r))
        } else {
            p.addRoundedRect(in: rect, cornerRadii: .init(
                topLeading: r, bottomLeading: tight, bottomTrailing: r, topTrailing: r))
        }
        return p
    }
}
