import Foundation
import SwiftUI

@Observable
final class ChatViewModel {
    private(set) var messages: [AIMessage] = []
    var inputText: String = ""
    var scope: ChatScope = .page
    var isSending = false
    var errorMessage: String?

    private let page: Page
    private let notebookPages: [Page]
    private let repo: AIMessageRepository
    private let router: AIRouter
    /// Page context image is attached only on the first message per session.
    private var contextAttached = false

    init(page: Page, notebookPages: [Page], repo: AIMessageRepository, router: AIRouter) {
        self.page = page
        self.notebookPages = notebookPages
        self.repo = repo
        self.router = router
    }

    func load() {
        do {
            messages = try repo.fetchAll(pageId: page.id)
            if messages.isEmpty {
                // Show a welcome message so the panel isn't blank on first open.
                // Not persisted — it vanishes after the first real message exchange.
                messages = [AIMessage(
                    id: "welcome-\(page.id)",
                    pageId: page.id,
                    role: .assistant,
                    text: "Hi! I can see your page. Ask me anything about it.",
                    createdAt: Date()
                )]
            } else {
                // Prior conversation exists → context was already sent.
                contextAttached = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        inputText = ""
        isSending = true
        defer { isSending = false }

        do {
            // Remove synthetic welcome message before persisting real ones.
            if messages.first?.id.hasPrefix("welcome-") == true {
                messages.removeFirst()
            }

            let userMsg = try repo.append(pageId: page.id, role: .user, text: text)
            messages.append(userMsg)

            let history = messages.dropLast().map {
                ChatHistoryEntry(role: $0.role.rawValue, text: $0.text)
            }

            // Attach page image only on the first message — the model retains
            // context from that point on, so re-sending is wasteful.
            let context: String?
            if !contextAttached {
                contextAttached = true
                context = ChatContextBuilder.makeContextImageBase64(
                    scope: scope,
                    currentPage: page,
                    notebookPages: notebookPages,
                    pageSize: CGSize(width: 1024, height: 1366)
                )
            } else {
                context = nil
            }

            let response = try await router.chat(
                ChatRequest(
                    pageId: page.id,
                    message: text,
                    history: Array(history),
                    scope: scope.rawValue,
                    imageBase64: context
                )
            )
            let reply = try repo.append(pageId: page.id, role: .assistant, text: response.reply)
            messages.append(reply)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func transcribe(audio: Data) async {
        let b64 = audio.base64EncodedString()
        do {
            let res = try await router.transcribe(
                TranscribeRequest(audioBase64: b64, language: "auto")
            )
            inputText = res.text
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
