import Foundation

/// Minimal direct-to-Groq client. Used when the PC server is unreachable.
final class GroqFallbackAIClient: AIClient {
    let label = "groq"
    private let pool: KeyPool
    private let prompts: BakedPrompts
    private let session: URLSession

    // Model IDs — keep in sync with server/app/routing.py in Plan A.
    private let visionModel  = "llama-3.2-90b-vision-preview"
    private let chatModel    = "llama-3.3-70b-versatile"
    private let whisperModel = "whisper-large-v3-turbo"

    private let baseURL = URL(string: "https://api.groq.com/openai/v1")!

    init(pool: KeyPool, prompts: BakedPrompts, session: URLSession = .shared) {
        self.pool = pool
        self.prompts = prompts
        self.session = session
    }

    // MARK: - AIClient

    func transform(_ request: TransformRequest) async throws -> TransformResponse {
        let system = prompts.transformPrompt(for: request.action)
        let userImage: [String: Any] = [
            "type": "image_url",
            "image_url": ["url": "data:image/png;base64,\(request.imageBase64)"]
        ]
        let userText: [String: Any] = ["type": "text", "text": "Apply: \(request.action.rawValue)"]
        let body: [String: Any] = [
            "model": visionModel,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": [userImage, userText]]
            ]
        ]
        let reply = try await chatCompletion(body: body)
        let kind: TransformResponse.ResultType = (request.action == .cleanup || request.action == .typedText)
            ? .text : .markdown
        return TransformResponse(
            resultType: kind,
            text: kind == .text ? reply : nil,
            markdown: kind == .markdown ? reply : nil,
            svg: nil,
            modelUsed: visionModel
        )
    }

    func chat(_ request: ChatRequest) async throws -> ChatResponse {
        let system = prompts.chatPrompt()
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        for h in request.history {
            messages.append(["role": h.role, "content": h.text])
        }
        if let img = request.imageBase64 {
            messages.append([
                "role": "user",
                "content": [
                    ["type": "text", "text": request.message],
                    ["type": "image_url",
                     "image_url": ["url": "data:image/png;base64,\(img)"]]
                ] as [Any]
            ])
            let body: [String: Any] = ["model": visionModel, "messages": messages]
            let reply = try await chatCompletion(body: body)
            return ChatResponse(reply: reply, tokensUsed: nil, modelUsed: visionModel)
        } else {
            messages.append(["role": "user", "content": request.message])
            let body: [String: Any] = ["model": chatModel, "messages": messages]
            let reply = try await chatCompletion(body: body)
            return ChatResponse(reply: reply, tokensUsed: nil, modelUsed: chatModel)
        }
    }

    func transcribe(_ request: TranscribeRequest) async throws -> TranscribeResponse {
        guard let state = pool.pick() else { throw AIError.allKeysExhausted }
        var req = URLRequest(url: baseURL.appendingPathComponent("/audio/transcriptions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(state.key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model", whisperModel)
        if let lang = request.language, lang != "auto" { field("language", lang) }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(Data(base64Encoded: request.audioBase64) ?? Data())
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        do {
            let (data, response) = try await session.data(for: req)
            try handleStatus(response: response, data: data, keyUsed: state.key)
            let decoded = try JSONDecoder().decode(WhisperResponse.self, from: data)
            pool.markSuccess(key: state.key)
            return TranscribeResponse(text: decoded.text, languageDetected: decoded.language)
        } catch {
            pool.markError(key: state.key)
            throw AIError.network(error)
        }
    }

    // MARK: - Private

    private struct WhisperResponse: Decodable {
        let text: String
        let language: String?
    }

    private struct OpenAIChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    private func chatCompletion(body: [String: Any]) async throws -> String {
        guard let state = pool.pick() else { throw AIError.allKeysExhausted }
        var req = URLRequest(url: baseURL.appendingPathComponent("/chat/completions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(state.key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: req)
            try handleStatus(response: response, data: data, keyUsed: state.key)
            let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
            pool.markSuccess(key: state.key)
            return decoded.choices.first?.message.content ?? ""
        } catch let error as AIError {
            throw error
        } catch {
            pool.markError(key: state.key)
            throw AIError.network(error)
        }
    }

    private func handleStatus(response: URLResponse, data: Data, keyUsed: String) throws {
        guard let http = response as? HTTPURLResponse else {
            pool.markError(key: keyUsed)
            throw AIError.http(-1, "Not an HTTP response")
        }
        if http.statusCode == 429 {
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)) ?? 60
            pool.markRateLimited(key: keyUsed, retryAfter: retryAfter)
            throw AIError.http(429, "rate limited")
        }
        if !(200..<300).contains(http.statusCode) {
            pool.markError(key: keyUsed)
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.http(http.statusCode, body)
        }
    }
}
