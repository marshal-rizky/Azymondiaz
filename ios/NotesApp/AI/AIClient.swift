import Foundation

/// Two implementations: PCServerAIClient (home), GroqFallbackAIClient (school).
/// The feature code never knows which is active — that's AIRouter's job.
protocol AIClient {
    var label: String { get }   // "pc" or "groq" — shown in the banner
    func transform(_ request: TransformRequest) async throws -> TransformResponse
    func chat(_ request: ChatRequest) async throws -> ChatResponse
    func transcribe(_ request: TranscribeRequest) async throws -> TranscribeResponse
}
