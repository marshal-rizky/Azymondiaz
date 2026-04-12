import Foundation
import Observation

/// Selects between PC server and Groq fallback. Runs a cheap reachability probe
/// before each call. Never silently downgrades a model — if the PC is reachable
/// but returns an error, the error propagates.
@Observable
final class AIRouter: AIClient {
    private let pcClient: AIClient?
    private let groqClient: AIClient?
    private let pcReachable: () async -> Bool

    /// Last-used client label — observed by the banner UI.
    private(set) var activeLabel: String = "offline"

    var label: String { activeLabel }

    /// True when at least one backend is configured. Used by the offline banner.
    var isConfigured: Bool { pcClient != nil || groqClient != nil }

    init(
        pcClient: AIClient?,
        groqClient: AIClient?,
        pcReachable: @escaping () async -> Bool
    ) {
        self.pcClient = pcClient
        self.groqClient = groqClient
        self.pcReachable = pcReachable
    }

    // MARK: - AIClient

    func transform(_ request: TransformRequest) async throws -> TransformResponse {
        try await route { try await $0.transform(request) }
    }
    func chat(_ request: ChatRequest) async throws -> ChatResponse {
        try await route { try await $0.chat(request) }
    }
    func transcribe(_ request: TranscribeRequest) async throws -> TranscribeResponse {
        try await route { try await $0.transcribe(request) }
    }

    // MARK: - Private

    private func route<T>(_ call: (AIClient) async throws -> T) async throws -> T {
        if let pc = pcClient, await pcReachable() {
            activeLabel = "pc"
            return try await call(pc)   // spec §4: surface errors as-is, no silent downgrade
        }
        if let groq = groqClient {
            activeLabel = "groq"
            return try await call(groq)
        }
        activeLabel = "offline"
        throw AIError.notConfigured
    }
}

extension AIRouter {
    /// Build from current KeychainStore state. Called by AppContainer on launch.
    static func bootstrap() -> AIRouter {
        let keys = (try? KeychainStore.shared.getGroqKeys()) ?? []
        let pcURLString = try? KeychainStore.shared.getPCServerURL()
        let pcClient: PCServerAIClient? = {
            guard let s = pcURLString, !s.isEmpty, let url = URL(string: s) else { return nil }
            return PCServerAIClient(baseURL: url)
        }()
        let groqClient: GroqFallbackAIClient? = {
            guard !keys.isEmpty else { return nil }
            return GroqFallbackAIClient(
                pool: KeyPool(keys: keys),
                prompts: BakedPrompts.loadFromBundle()
            )
        }()
        let reachable: () async -> Bool = { [weak pcClient] in
            guard let pc = pcClient else { return false }
            return await pc.ping()
        }
        return AIRouter(pcClient: pcClient, groqClient: groqClient, pcReachable: reachable)
    }
}
