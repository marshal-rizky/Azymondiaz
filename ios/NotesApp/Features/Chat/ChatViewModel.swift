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

    init(page: Page, notebookPages: [Page], repo: AIMessageRepository, router: AIRouter) {
        self.page = page
        self.notebookPages = notebookPages
        self.repo = repo
        self.router = router
    }

    func load() {
        do {
            messages = try repo.fetchAll(pageId: page.id)
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
            let userMsg = try repo.append(pageId: page.id, role: .user, text: text)
            messages.append(userMsg)

            let history = messages.dropLast().map {
                ChatHistoryEntry(role: $0.role.rawValue, text: $0.text)
            }
            let context = ChatContextBuilder.makeContextImageBase64(
                scope: scope,
                currentPage: page,
                notebookPages: notebookPages,
                pageSize: CGSize(width: 1024, height: 1366)
            )
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
