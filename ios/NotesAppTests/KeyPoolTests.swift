import XCTest
@testable import NotesApp

final class KeyPoolTests: XCTestCase {
    func test_empty_pool_returns_nil() {
        let pool = KeyPool(keys: [])
        XCTAssertNil(pool.pick())
    }

    func test_round_robin_rotation() {
        let pool = KeyPool(keys: ["a", "b", "c"])
        XCTAssertEqual(pool.pick()?.key, "a")
        XCTAssertEqual(pool.pick()?.key, "b")
        XCTAssertEqual(pool.pick()?.key, "c")
        XCTAssertEqual(pool.pick()?.key, "a")
    }

    func test_rate_limited_key_skipped_until_cooldown_expires() {
        let pool = KeyPool(keys: ["a", "b"], clock: { Date(timeIntervalSince1970: 0) })
        _ = pool.pick()
        pool.markRateLimited(key: "a", retryAfter: 30)
        // Within cooldown window: should never pick "a"
        for _ in 0..<5 {
            XCTAssertEqual(pool.pick()?.key, "b")
        }
    }

    func test_three_consecutive_errors_kills_key() {
        let pool = KeyPool(keys: ["a", "b"])
        pool.markError(key: "a")
        pool.markError(key: "a")
        pool.markError(key: "a")
        // "a" is dead; rotation should only surface "b"
        for _ in 0..<5 {
            XCTAssertEqual(pool.pick()?.key, "b")
        }
    }

    func test_success_resets_error_count() {
        let pool = KeyPool(keys: ["a"])
        pool.markError(key: "a")
        pool.markError(key: "a")
        pool.markSuccess(key: "a")
        pool.markError(key: "a")
        pool.markError(key: "a")
        // 2 errors after reset → still alive
        XCTAssertEqual(pool.pick()?.key, "a")
    }

    func test_description_redacts_key_body() {
        let state = KeyPool.KeyState(key: "sk-proj-ABCDEFGHIJ")
        let desc = String(describing: state)
        XCTAssertFalse(desc.contains("ABCDEFGHIJ"))
    }
}
