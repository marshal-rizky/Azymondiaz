import Foundation

final class PCServerAIClient: AIClient {
    let label = "pc"
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func transform(_ request: TransformRequest) async throws -> TransformResponse {
        try await post("/ai/transform", body: request)
    }

    func chat(_ request: ChatRequest) async throws -> ChatResponse {
        try await post("/ai/chat", body: request)
    }

    func transcribe(_ request: TranscribeRequest) async throws -> TranscribeResponse {
        try await post("/ai/transcribe", body: request)
    }

    /// Reachability probe used by AIRouter.
    func ping() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("/health"))
        req.timeoutInterval = 1.5
        do {
            let (_, response) = try await session.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func post<Req: Encodable, Res: Decodable>(
        _ path: String, body: Req
    ) async throws -> Res {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        do {
            req.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw AIError.decoding(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIError.http(-1, "Not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.http(http.statusCode, body)
        }

        do {
            return try JSONDecoder().decode(Res.self, from: data)
        } catch {
            throw AIError.decoding(error)
        }
    }
}
