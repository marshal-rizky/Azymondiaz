import XCTest
@testable import NotesApp

final class AIRouterTests: XCTestCase {
    final class StubClient: AIClient {
        let label: String
        var shouldThrow = false
        init(_ label: String) { self.label = label }
        func transform(_ request: TransformRequest) async throws -> TransformResponse {
            if shouldThrow { throw AIError.network(URLError(.notConnectedToInternet)) }
            return TransformResponse(resultType: .text, text: label, markdown: nil, svg: nil, modelUsed: label)
        }
        func chat(_ request: ChatRequest) async throws -> ChatResponse {
            ChatResponse(reply: label, tokensUsed: nil, modelUsed: label)
        }
        func transcribe(_ request: TranscribeRequest) async throws -> TranscribeResponse {
            TranscribeResponse(text: label, languageDetected: nil)
        }
    }

    func test_uses_pc_when_reachable() async throws {
        let pc = StubClient("pc")
        let groq = StubClient("groq")
        let router = AIRouter(pcClient: pc, groqClient: groq, pcReachable: { true })
        let res = try await router.transform(TransformRequest(action: .cleanup, imageBase64: "", contextText: nil))
        XCTAssertEqual(res.text, "pc")
        XCTAssertEqual(router.activeLabel, "pc")
    }

    func test_falls_back_to_groq_when_pc_unreachable() async throws {
        let pc = StubClient("pc")
        let groq = StubClient("groq")
        let router = AIRouter(pcClient: pc, groqClient: groq, pcReachable: { false })
        let res = try await router.transform(TransformRequest(action: .cleanup, imageBase64: "", contextText: nil))
        XCTAssertEqual(res.text, "groq")
        XCTAssertEqual(router.activeLabel, "groq")
    }

    func test_pc_error_does_not_silently_fall_back() async {
        let pc = StubClient("pc")
        pc.shouldThrow = true
        let groq = StubClient("groq")
        let router = AIRouter(pcClient: pc, groqClient: groq, pcReachable: { true })
        do {
            _ = try await router.transform(TransformRequest(action: .cleanup, imageBase64: "", contextText: nil))
            XCTFail("expected throw")
        } catch {
            // Expected. Spec §4: "No silent downgrades."
        }
    }

    func test_missing_pc_and_empty_groq_throws_notConfigured() async {
        let router = AIRouter(pcClient: nil, groqClient: nil, pcReachable: { false })
        do {
            _ = try await router.chat(ChatRequest(pageId: "x", message: "hi", history: [], scope: "page", imageBase64: nil))
            XCTFail()
        } catch let e as AIError {
            if case .notConfigured = e {} else { XCTFail("wrong error \(e)") }
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}
