import XCTest
@testable import NotesApp

final class BakedPromptsTests: XCTestCase {
    func test_all_transform_actions_have_prompts() {
        let prompts = BakedPrompts.loadFromBundle()
        for action in AIAction.allCases {
            let p = prompts.transformPrompt(for: action)
            XCTAssertFalse(p.isEmpty, "Missing prompt for \(action.rawValue)")
        }
    }

    func test_chat_prompt_is_present() {
        let prompts = BakedPrompts.loadFromBundle()
        XCTAssertFalse(prompts.chatPrompt().isEmpty)
    }
}
