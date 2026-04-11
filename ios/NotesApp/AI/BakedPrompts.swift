import Foundation

/// Read-only snapshot of `server/prompts/*.txt` copied into the bundle at build time.
/// Used exclusively by GroqFallbackAIClient (school mode). On the PC path, prompts
/// live server-side and hot-reload per request.
struct BakedPrompts {
    private let transforms: [AIAction: String]
    private let chat: String

    static func loadFromBundle() -> BakedPrompts {
        let fileMap: [AIAction: String] = [
            .cleanup:   "transform_cleanup",
            .typedText: "transform_typed_text",
            .math:      "transform_math",
            .physics:   "transform_physics",
            .chemistry: "transform_chemistry",
            .explain:   "transform_explain",
            .list:      "transform_list"
        ]
        var transforms: [AIAction: String] = [:]
        for (action, name) in fileMap {
            transforms[action] = Self.readText(name: name) ?? "Apply \(action.rawValue) to the input."
        }
        let chat = Self.readText(name: "chat_system") ?? "You are a helpful study assistant."
        return BakedPrompts(transforms: transforms, chat: chat)
    }

    func transformPrompt(for action: AIAction) -> String {
        transforms[action] ?? ""
    }

    func chatPrompt() -> String { chat }

    // MARK: - Private

    private static func readText(name: String) -> String? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "txt",
            subdirectory: "prompts"
        ) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
