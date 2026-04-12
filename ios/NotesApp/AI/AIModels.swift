import Foundation

enum AIAction: String, Codable, CaseIterable {
    case cleanup
    case typedText  = "typed_text"
    case math
    case physics
    case chemistry
    case explain
    case list
}

struct TransformRequest: Codable {
    let action: AIAction
    let imageBase64: String
    let contextText: String?

    enum CodingKeys: String, CodingKey {
        case action
        case imageBase64 = "image_base64"
        case contextText = "context"
    }
}

struct TransformResponse: Codable {
    enum ResultType: String, Codable { case text, markdown, svg }
    let resultType: ResultType
    let text: String?
    let markdown: String?
    let svg: String?
    let modelUsed: String

    enum CodingKeys: String, CodingKey {
        case resultType = "result_type"
        case text
        case markdown
        case svg
        case modelUsed = "model_used"
    }
}

struct ChatHistoryEntry: Codable {
    let role: String   // "user" | "assistant"
    let text: String

    enum CodingKeys: String, CodingKey {
        case role
        case text = "content"   // server expects "content" (matches OpenAI/Groq wire format)
    }
}

struct ChatRequest: Codable {
    let pageId: String
    let message: String
    let history: [ChatHistoryEntry]
    let scope: String               // "page" | "notebook"
    let imageBase64: String?        // context attachment

    enum CodingKeys: String, CodingKey {
        case pageId = "page_id"
        case message
        case history
        case scope
        case imageBase64 = "context_image_base64"  // matches PC server field name
    }
}

struct ChatResponse: Codable {
    let reply: String
    let tokensUsed: Int?
    let modelUsed: String

    enum CodingKeys: String, CodingKey {
        case reply
        case tokensUsed = "tokens_used"
        case modelUsed  = "model_used"
    }
}

struct TranscribeRequest: Codable {
    let audioBase64: String
    let language: String?

    enum CodingKeys: String, CodingKey {
        case audioBase64 = "audio_base64"
        case language
    }
}

struct TranscribeResponse: Codable {
    let text: String
    let languageDetected: String?

    enum CodingKeys: String, CodingKey {
        case text
        case languageDetected = "language_detected"
    }
}

enum AIError: Error, LocalizedError {
    case notConfigured
    case network(Error)
    case http(Int, String)
    case allKeysExhausted
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:    return "AI is not configured. Open Settings to add a PC server URL or Groq API keys."
        case .network(let e):   return "Network error: \(e.localizedDescription)"
        case .http(let code, let body): return "AI server error \(code): \(body)"
        case .allKeysExhausted: return "All API keys rate-limited. Retry in a moment."
        case .decoding(let e):  return "Bad response from AI: \(e.localizedDescription)"
        }
    }
}
