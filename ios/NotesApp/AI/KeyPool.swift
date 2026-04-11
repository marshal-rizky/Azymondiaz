import Foundation

/// Mirrors the server-side pool but runs on-device for school/fallback mode.
final class KeyPool {
    struct KeyState: CustomStringConvertible {
        var key: String
        var errorCount: Int = 0
        var cooldownUntil: Date? = nil
        var dead: Bool = false

        var description: String {
            let redacted = key.count > 6 ? "\(key.prefix(5))…\(key.suffix(2))" : "***"
            return "KeyState(\(redacted), errors=\(errorCount), dead=\(dead))"
        }
    }

    private var states: [KeyState]
    private var cursor: Int = 0
    private let clock: () -> Date
    private let lock = NSLock()

    init(keys: [String], clock: @escaping () -> Date = Date.init) {
        self.states = keys.map { KeyState(key: $0) }
        self.clock = clock
    }

    func pick() -> KeyState? {
        lock.lock(); defer { lock.unlock() }
        guard !states.isEmpty else { return nil }
        let now = clock()
        for _ in 0..<states.count {
            let idx = cursor % states.count
            cursor = (cursor + 1) % states.count
            var s = states[idx]
            if s.dead { continue }
            if let until = s.cooldownUntil, until > now { continue }
            if s.cooldownUntil != nil { s.cooldownUntil = nil }
            states[idx] = s
            return s
        }
        return nil
    }

    func markRateLimited(key: String, retryAfter seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        guard let idx = states.firstIndex(where: { $0.key == key }) else { return }
        states[idx].cooldownUntil = clock().addingTimeInterval(seconds)
    }

    func markError(key: String) {
        lock.lock(); defer { lock.unlock() }
        guard let idx = states.firstIndex(where: { $0.key == key }) else { return }
        states[idx].errorCount += 1
        if states[idx].errorCount >= 3 {
            states[idx].dead = true
        }
    }

    func markSuccess(key: String) {
        lock.lock(); defer { lock.unlock() }
        guard let idx = states.firstIndex(where: { $0.key == key }) else { return }
        states[idx].errorCount = 0
    }

    var summary: [KeyState] {
        lock.lock(); defer { lock.unlock() }
        return states
    }
}
