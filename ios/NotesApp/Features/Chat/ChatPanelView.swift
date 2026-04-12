import SwiftUI

struct ChatPanelView: View {
    @Bindable var viewModel: ChatViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { msg in
                            bubble(msg: msg).id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            inputBar
        }
        .frame(width: 360)
        .background(Color(.systemBackground))
        .onAppear { viewModel.load() }
        .alert("Chat error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        ), actions: { Button("OK") {} }, message: {
            Text(viewModel.errorMessage ?? "")
        })
    }

    private var header: some View {
        HStack {
            Text("Chat").font(.headline)
            Picker("Scope", selection: $viewModel.scope) {
                Text("Page").tag(ChatScope.page)
                Text("Notebook").tag(ChatScope.notebook)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark")
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func bubble(msg: AIMessage) -> some View {
        let isUser = msg.role == .user
        HStack {
            if isUser { Spacer() }
            bubbleContent(msg: msg)
                .background(isUser ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 300)
            if !isUser { Spacer() }
        }
    }

    /// Inner content of a chat bubble. Separated to avoid @ViewBuilder let-binding issues.
    @ViewBuilder
    private func bubbleContent(msg: AIMessage) -> some View {
        if msg.role == .user {
            Text(msg.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else if containsMath(msg.text) {
            // Render markdown + LaTeX via WKWebView (requires internet — same as AI)
            MathWebView(content: msg.text)
                .frame(minHeight: 80, maxHeight: 400)
        } else {
            // Basic markdown (bold, italic, code) via AttributedString — no network needed
            Text(markdownAttr(msg.text))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    private func containsMath(_ text: String) -> Bool {
        text.contains("$") || text.contains("\\")
    }

    private func markdownAttr(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            MicButton { audio in
                Task { await viewModel.transcribe(audio: audio) }
            }
            TextField("Ask anything…", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(viewModel.isSending || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }
}
