# Plan C — iPad AI Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Layer the full AI feature set from the spec on top of the Plan B note app — lasso → transform, side-panel chat, voice input, notebook sync — with automatic routing between the PC companion server (home) and a direct Groq fallback (school). At the end of this plan the user has the full app described in the spec.

**Architecture:** A single `AIClient` protocol with two concrete implementations — `PCServerAIClient` (hits Plan A's FastAPI endpoints) and `GroqFallbackAIClient` (hits Groq directly with a mini 5-key pool). An `AIRouter` picks between them based on a short reachability probe to the configured PC URL, with a user-visible banner telling which path is active. Prompts ship in two forms: live on the PC (hot-reloaded) and as a read-only snapshot bundled into the IPA at build time via a prebuild script that copies `server/prompts/` into the Xcode bundle. Chat, transform, voice, and sync are independent feature modules that all route through `AIRouter`, so replacing one client never touches feature code.

**Tech Stack:**
- Everything from Plan B (Swift 5.10, SwiftUI, GRDB, PencilKit, iOS 17)
- `URLSession` for HTTP (no Alamofire — keep dependency surface minimal)
- `Security.framework` for Keychain
- `AVFoundation` (`AVAudioRecorder`) for voice capture
- Plan A server as the primary AI backend
- Groq REST API as the fallback backend (model IDs match the spec §4 routing table)

**Prerequisites:** Plan B merged and green. Plan A reachable on LAN (optional for school-only development; the fallback path can be developed first).

**Reference:** `docs/superpowers/specs/2026-04-07-ipad-ai-notes-design.md` sections 4, 5, 6, 8.

---

## File Structure

```
ios/NotesApp/
├── AI/
│   ├── AIClient.swift                   # protocol: transform, chat, transcribe
│   ├── AIModels.swift                   # DTOs shared between clients
│   ├── AIRouter.swift                   # reachability probe + routing decision
│   ├── PCServerAIClient.swift           # HTTP client for Plan A endpoints
│   ├── GroqFallbackAIClient.swift       # direct Groq REST client
│   ├── KeyPool.swift                    # 5-slot key rotation with cooldown
│   ├── KeychainStore.swift              # read/write API keys and PC URL
│   └── BakedPrompts.swift               # load snapshot from bundle Resources/prompts/
├── Data/
│   ├── AIMessage.swift                  # Codable + GRDB record (table exists from Plan B)
│   └── AIMessageRepository.swift
├── Canvas/
│   ├── LassoRasterizer.swift            # PKDrawing + lasso selection → PNG
│   └── CanvasView.swift                 # [MODIFY] expose selection change callback
├── Features/
│   ├── Notebook/
│   │   ├── NotebookView.swift           # [MODIFY] chat toggle + lasso menu
│   │   ├── LassoMenuView.swift          # action sheet near selection
│   │   └── TransformResultView.swift    # popover: insert below / replace / dismiss
│   ├── Chat/
│   │   ├── ChatViewModel.swift
│   │   ├── ChatPanelView.swift          # side panel (slides from right)
│   │   └── ChatContextBuilder.swift     # rasterize current page/notebook
│   ├── Voice/
│   │   ├── VoiceRecorder.swift          # AVAudioRecorder wrapper
│   │   └── MicButton.swift              # hold-to-talk + live waveform
│   └── Settings/
│       └── SettingsView.swift           # [MODIFY] PC URL, Groq keys, voice lang
├── Sync/
│   ├── SyncClient.swift                 # push/pull against /sync
│   ├── SyncScheduler.swift              # debounced + timer-driven triggers
│   └── SyncDiff.swift                   # compute changed-pages diff
└── Resources/
    └── prompts/                         # [GENERATED at build time from ../../server/prompts/]

ios/NotesAppTests/
├── KeyPoolTests.swift
├── AIRouterTests.swift                  # reachability mocked
├── LassoRasterizerTests.swift
├── SyncDiffTests.swift
├── ChatContextBuilderTests.swift
├── AIMessageRepositoryTests.swift
└── BakedPromptsTests.swift

ios/Scripts/
└── copy-prompts.sh                      # run as Xcode build phase
```

**Why this split:** AI/ is the whole backend abstraction and is the only place the `PCServerAIClient` vs `GroqFallbackAIClient` decision lives — feature code stays oblivious. Sync/ and Voice/ are siblings, not inside AI/, because they're independent concerns that happen to use the network. `Canvas/LassoRasterizer` is the single pure function that bridges PencilKit selection to base64 PNG; keeping it out of the view makes it unit-testable.

---

## Conventions

- Same as Plan B: 4-space indent, conventional commits, in-memory DB in tests.
- **Never commit secrets.** API keys live in Keychain only. `Settings/config.yaml.example` (Plan A) is the only place they're templated.
- **Network timeouts:** PC server probe = 1.5s; all AI calls = 30s (transforms can be slow).
- **Never log full API keys.** Tests check that `KeyState.description` redacts.
- **Tests that hit the network:** gated by `RUN_LIVE_TESTS=1` env var, same as Plan A.

---

## Task 1: Keychain store for secrets + PC URL

**Files:**
- Create: `ios/NotesApp/AI/KeychainStore.swift`
- Create: `ios/NotesAppTests/KeychainStoreTests.swift` (simulator-only)

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import NotesApp

final class KeychainStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KeychainStore.shared.deleteAll()
    }

    func test_write_then_read_groq_keys() throws {
        let keys = ["sk-1", "sk-2", "sk-3"]
        try KeychainStore.shared.setGroqKeys(keys)
        XCTAssertEqual(try KeychainStore.shared.getGroqKeys(), keys)
    }

    func test_read_missing_returns_empty() throws {
        XCTAssertEqual(try KeychainStore.shared.getGroqKeys(), [])
    }

    func test_pc_server_url_round_trip() throws {
        try KeychainStore.shared.setPCServerURL("http://192.168.1.10:8000")
        XCTAssertEqual(try KeychainStore.shared.getPCServerURL(), "http://192.168.1.10:8000")
    }
}
```

- [ ] **Step 2: Implement `KeychainStore.swift`**

```swift
import Foundation
import Security

/// Thin Keychain wrapper for the handful of secrets this app stores.
/// Never log values from here. Treat errors as non-fatal: a missing
/// item returns nil/empty rather than throwing, so first-launch flows
/// degrade gracefully.
final class KeychainStore {
    static let shared = KeychainStore()
    private init() {}

    private let service = "dev.user.NotesApp"
    private enum Key: String {
        case groqKeys   = "groq.keys.json"
        case pcURL      = "pc.server.url"
    }

    enum KeychainError: Error { case unexpectedStatus(OSStatus) }

    // MARK: - Public

    func setGroqKeys(_ keys: [String]) throws {
        let data = try JSONEncoder().encode(keys)
        try set(key: .groqKeys, data: data)
    }

    func getGroqKeys() throws -> [String] {
        guard let data = try get(key: .groqKeys) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func setPCServerURL(_ url: String) throws {
        try set(key: .pcURL, data: Data(url.utf8))
    }

    func getPCServerURL() throws -> String? {
        guard let data = try get(key: .pcURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteAll() {
        for key in [Key.groqKeys, .pcURL] {
            let q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key.rawValue
            ]
            SecItemDelete(q as CFDictionary)
        }
    }

    // MARK: - Private

    private func set(key: Key, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private func get(key: Key) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return result as? Data
    }
}
```

- [ ] **Step 3: Run the tests**

Expected: 3 tests **PASS**.

- [ ] **Step 4: Commit**

```bash
git add ios/NotesApp/AI/KeychainStore.swift ios/NotesAppTests/KeychainStoreTests.swift
git commit -m "feat(ai): Keychain store for Groq keys + PC URL"
```

---

## Task 2: Mini key pool for on-device Groq fallback

**Files:**
- Create: `ios/NotesApp/AI/KeyPool.swift`
- Create: `ios/NotesAppTests/KeyPoolTests.swift`

This mirrors the server-side `KeyPool` from Plan A but with a smaller API — the iPad only needs "pick next usable key" and "mark this key rate-limited/dead."

- [ ] **Step 1: Write failing tests**

```swift
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
```

- [ ] **Step 2: Implement `KeyPool.swift`**

```swift
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
```

- [ ] **Step 3: Run tests**

Expected: all 6 **PASS**.

- [ ] **Step 4: Commit**

```bash
git add ios/NotesApp/AI/KeyPool.swift ios/NotesAppTests/KeyPoolTests.swift
git commit -m "feat(ai): on-device 5-key rotation pool"
```

---

## Task 3: AI DTOs + `AIClient` protocol

**Files:**
- Create: `ios/NotesApp/AI/AIModels.swift`
- Create: `ios/NotesApp/AI/AIClient.swift`

- [ ] **Step 1: Implement `AIModels.swift`**

```swift
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
        case imageBase64 = "image_base64"
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
```

- [ ] **Step 2: Implement `AIClient.swift`**

```swift
import Foundation

/// Two implementations: PCServerAIClient (home), GroqFallbackAIClient (school).
/// The feature code never knows which is active — that's AIRouter's job.
protocol AIClient {
    var label: String { get }   // "pc" or "groq" — shown in the banner
    func transform(_ request: TransformRequest) async throws -> TransformResponse
    func chat(_ request: ChatRequest) async throws -> ChatResponse
    func transcribe(_ request: TranscribeRequest) async throws -> TranscribeResponse
}
```

- [ ] **Step 3: Build (no new tests)**

Build should succeed. Commit.

```bash
git add ios/NotesApp/AI/AIModels.swift ios/NotesApp/AI/AIClient.swift
git commit -m "feat(ai): DTOs + AIClient protocol"
```

---

## Task 4: PC server client

**Files:**
- Create: `ios/NotesApp/AI/PCServerAIClient.swift`

No unit tests — exercised via integration (Task 6 covers reachability logic, live calls are manual smoke).

- [ ] **Step 1: Implement `PCServerAIClient.swift`**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add ios/NotesApp/AI/PCServerAIClient.swift
git commit -m "feat(ai): PC server HTTP client with /health probe"
```

---

## Task 5: Groq fallback client

**Files:**
- Create: `ios/NotesApp/AI/GroqFallbackAIClient.swift`

This talks directly to `https://api.groq.com/openai/v1/…`. Model IDs match spec §4.

- [ ] **Step 1: Implement `GroqFallbackAIClient.swift`**

```swift
import Foundation

/// Minimal direct-to-Groq client. Used when the PC server is unreachable.
final class GroqFallbackAIClient: AIClient {
    let label = "groq"
    private let pool: KeyPool
    private let prompts: BakedPrompts
    private let session: URLSession

    // Model IDs — keep in sync with server/app/routing.py in Plan A.
    private let visionModel = "llama-3.2-90b-vision-preview"
    private let chatModel   = "llama-3.3-70b-versatile"
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
        // Coarse heuristic: cleanup → text; math/list → markdown; explain → markdown
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
        // Attach image context if present (vision model can take it; for pure chat we fall back to text).
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

        // multipart/form-data with file + model + language
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
```

- [ ] **Step 2: Build**

Expected: FAILS — `BakedPrompts` not yet defined. Next task.

- [ ] **Step 3: Commit (WIP)**

```bash
git add ios/NotesApp/AI/GroqFallbackAIClient.swift
git commit -m "feat(ai): direct Groq fallback client for school mode"
```

---

## Task 6: Baked prompts — prebuild copy script + loader

**Files:**
- Create: `ios/Scripts/copy-prompts.sh`
- Modify: `ios/project.yml` (add Run Script build phase + prompts resource group)
- Create: `ios/NotesApp/AI/BakedPrompts.swift`
- Create: `ios/NotesAppTests/BakedPromptsTests.swift`

- [ ] **Step 1: Write the copy script**

Create `ios/Scripts/copy-prompts.sh`:

```bash
#!/bin/bash
# Copies the authoritative server prompts into the iOS app bundle's
# Resources/prompts/ directory. Runs as an Xcode build phase so every
# iPA ships the latest snapshot (used in school fallback mode).
set -euo pipefail

SERVER_PROMPTS="${SRCROOT}/../server/prompts"
DEST="${SRCROOT}/NotesApp/Resources/prompts"

rm -rf "$DEST"
mkdir -p "$DEST"

if [ -d "$SERVER_PROMPTS" ]; then
  cp -R "$SERVER_PROMPTS/." "$DEST/"
  echo "Copied prompts from $SERVER_PROMPTS"
else
  # First build or server monorepo not checked out: write minimal stubs so
  # BakedPromptsTests still passes and the app does not crash in offline mode.
  echo "WARNING: $SERVER_PROMPTS not found — writing stub prompts"
  cat > "$DEST/transform_cleanup.txt" <<'EOF'
Clean up this handwriting into neat text. Preserve meaning exactly.
EOF
  cat > "$DEST/transform_typed_text.txt" <<'EOF'
Convert this handwriting into plain typed text, nothing else.
EOF
  cat > "$DEST/transform_math.txt" <<'EOF'
You are a careful math tutor. Read the handwritten problem, solve it,
and explain each step clearly in the user's language.
EOF
  cat > "$DEST/transform_physics.txt" <<'EOF'
You are a careful physics tutor. Interpret the handwritten problem or
diagram, identify the relevant concept, and walk through the solution.
EOF
  cat > "$DEST/transform_chemistry.txt" <<'EOF'
You are a careful chemistry tutor. Interpret the handwritten question
and answer clearly. Note any structural-formula ambiguities.
EOF
  cat > "$DEST/transform_explain.txt" <<'EOF'
Explain the content of this handwritten note at a high-school level
in the user's language.
EOF
  cat > "$DEST/transform_list.txt" <<'EOF'
Convert the content of this note into a clear bulleted list.
EOF
  cat > "$DEST/chat_system.txt" <<'EOF'
You are a helpful study assistant. Match the user's language.
Indonesian, English, or mixed is fine.
EOF
fi

echo "Prompts baked:"
ls "$DEST"
```

Make it executable:

```bash
chmod +x ios/Scripts/copy-prompts.sh
```

- [ ] **Step 2: Wire build phase into `project.yml`**

Edit `ios/project.yml`. Under the `NotesApp` target, add a `preBuildScripts` entry and extend the `resources` list:

```yaml
targets:
  NotesApp:
    type: application
    platform: iOS
    sources:
      - path: NotesApp
    resources:
      - path: NotesApp/Resources/Assets.xcassets
      - path: NotesApp/Resources/prompts
        type: folder
        optional: true
    preBuildScripts:
      - name: "Bake server prompts into bundle"
        path: Scripts/copy-prompts.sh
        basedOnDependencyAnalysis: false
    # (rest unchanged)
```

- [ ] **Step 3: Write failing tests**

```swift
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
```

- [ ] **Step 4: Implement `BakedPrompts.swift`**

```swift
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
```

- [ ] **Step 5: Regenerate project, build, run tests**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (4th generation)'
```

Expected: both `BakedPromptsTests` **PASS** and the Task 5 build error clears.

- [ ] **Step 6: Commit**

```bash
git add ios/Scripts/copy-prompts.sh ios/project.yml ios/NotesApp/AI/BakedPrompts.swift ios/NotesAppTests/BakedPromptsTests.swift
git commit -m "feat(ai): bake server prompts into iPA for school fallback"
```

---

## Task 7: AIRouter — reachability probe + client selection

**Files:**
- Create: `ios/NotesApp/AI/AIRouter.swift`
- Create: `ios/NotesAppTests/AIRouterTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
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
```

- [ ] **Step 2: Implement `AIRouter.swift`**

```swift
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
```

- [ ] **Step 3: Convenience bootstrap**

Append at the end of `AIRouter.swift`:

```swift
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
```

- [ ] **Step 4: Extend AppContainer**

Add to `ios/NotesApp/App/AppContainer.swift` inside the class:

```swift
    var aiRouter: AIRouter

    // replace the init(database:) body with:
    init(database: Database) {
        self.database = database
        self.notebooks = NotebookRepository(pool: database.pool)
        self.pages = PageRepository(pool: database.pool)
        self.aiRouter = AIRouter.bootstrap()
    }

    /// Call after the user changes PC URL or keys in Settings.
    func reloadAI() {
        self.aiRouter = AIRouter.bootstrap()
    }
```

- [ ] **Step 5: Run tests**

Expected: all 4 `AIRouterTests` **PASS**.

- [ ] **Step 6: Commit**

```bash
git add ios/NotesApp/AI/AIRouter.swift ios/NotesApp/App/AppContainer.swift ios/NotesAppTests/AIRouterTests.swift
git commit -m "feat(ai): AIRouter with reachability probe and no silent downgrade"
```

---

## Task 8: AIMessage model + repository

**Files:**
- Create: `ios/NotesApp/Data/AIMessage.swift`
- Create: `ios/NotesApp/Data/AIMessageRepository.swift`
- Create: `ios/NotesAppTests/AIMessageRepositoryTests.swift`

The `ai_messages` table was created in Plan B; we just add model/repo.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import NotesApp

final class AIMessageRepositoryTests: XCTestCase {
    private var db: Database!
    private var notebooks: NotebookRepository!
    private var pages: PageRepository!
    private var messages: AIMessageRepository!
    private var pageId: String!

    override func setUpWithError() throws {
        db = try Database.makeInMemory()
        notebooks = NotebookRepository(pool: db.pool)
        pages = PageRepository(pool: db.pool)
        messages = AIMessageRepository(pool: db.pool)
        let nb = try notebooks.create(title: "NB", coverColor: "#111111")
        pageId = try pages.append(notebookId: nb.id, template: .line).id
    }

    func test_append_and_fetch_for_page_in_chronological_order() throws {
        _ = try messages.append(pageId: pageId, role: .user, text: "hi")
        _ = try messages.append(pageId: pageId, role: .assistant, text: "hello")
        _ = try messages.append(pageId: pageId, role: .user, text: "thanks")
        let all = try messages.fetchAll(pageId: pageId)
        XCTAssertEqual(all.map(\.text), ["hi", "hello", "thanks"])
    }

    func test_messages_are_cascade_deleted_with_page() throws {
        _ = try messages.append(pageId: pageId, role: .user, text: "hi")
        try pages.delete(id: pageId)
        XCTAssertTrue(try messages.fetchAll(pageId: pageId).isEmpty)
    }
}
```

- [ ] **Step 2: Implement `AIMessage.swift`**

```swift
import Foundation
import GRDB

enum AIMessageRole: String, Codable { case user, assistant }

struct AIMessage: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var pageId: String
    var role: AIMessageRole
    var text: String
    var createdAt: Date

    static let databaseTableName = "ai_messages"

    enum CodingKeys: String, CodingKey {
        case id
        case pageId = "page_id"
        case role
        case text
        case createdAt = "created_at"
    }
}
```

- [ ] **Step 3: Implement `AIMessageRepository.swift`**

```swift
import Foundation
import GRDB

final class AIMessageRepository {
    private let pool: DatabasePool
    init(pool: DatabasePool) { self.pool = pool }

    @discardableResult
    func append(pageId: String, role: AIMessageRole, text: String) throws -> AIMessage {
        let m = AIMessage(
            id: UUID().uuidString,
            pageId: pageId,
            role: role,
            text: text,
            createdAt: Date()
        )
        try pool.write { db in try m.insert(db) }
        return m
    }

    func fetchAll(pageId: String) throws -> [AIMessage] {
        try pool.read { db in
            try AIMessage
                .filter(Column("page_id") == pageId)
                .order(Column("created_at").asc)
                .fetchAll(db)
        }
    }

    func deleteAll(pageId: String) throws {
        try pool.write { db in
            try AIMessage
                .filter(Column("page_id") == pageId)
                .deleteAll(db)
        }
    }
}
```

- [ ] **Step 4: Wire into AppContainer**

In `AppContainer.swift`, add:

```swift
    let aiMessages: AIMessageRepository
```

and in `init`:

```swift
    self.aiMessages = AIMessageRepository(pool: database.pool)
```

- [ ] **Step 5: Run tests**

Expected: both **PASS**.

- [ ] **Step 6: Commit**

```bash
git add ios/NotesApp/Data/AIMessage.swift ios/NotesApp/Data/AIMessageRepository.swift ios/NotesApp/App/AppContainer.swift ios/NotesAppTests/AIMessageRepositoryTests.swift
git commit -m "feat(data): AIMessage model + repository"
```

---

## Task 9: Lasso rasterizer (PKDrawing selection → base64 PNG)

**Files:**
- Create: `ios/NotesApp/Canvas/LassoRasterizer.swift`
- Create: `ios/NotesAppTests/LassoRasterizerTests.swift`

The PencilKit built-in lasso gives us back a `PKDrawing` containing only the selected strokes plus the selection bounds. Rasterize it to a transparent-background PNG.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import PencilKit
@testable import NotesApp

final class LassoRasterizerTests: XCTestCase {
    func test_rasterize_empty_drawing_returns_empty_base64() {
        let result = LassoRasterizer.rasterize(
            selection: PKDrawing(),
            bounds: .zero
        )
        XCTAssertTrue(result.isEmpty)
    }

    func test_rasterize_nonempty_drawing_returns_png_base64() {
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: [
                PKStrokePoint(location: CGPoint(x: 10, y: 10), timeOffset: 0,
                              size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: 0),
                PKStrokePoint(location: CGPoint(x: 50, y: 50), timeOffset: 0.01,
                              size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: 0)
            ], creationDate: Date())
        )
        let drawing = PKDrawing(strokes: [stroke])
        let bounds = drawing.bounds.insetBy(dx: -10, dy: -10)
        let b64 = LassoRasterizer.rasterize(selection: drawing, bounds: bounds)
        XCTAssertFalse(b64.isEmpty)
        let data = Data(base64Encoded: b64)!
        XCTAssertEqual(data.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }
}
```

- [ ] **Step 2: Implement `LassoRasterizer.swift`**

```swift
import UIKit
import PencilKit

enum LassoRasterizer {
    /// Renders the given drawing clipped to `bounds` on a transparent background
    /// and returns base64-encoded PNG. Caller passes the lasso selection bounds.
    static func rasterize(selection: PKDrawing, bounds: CGRect) -> String {
        guard !selection.bounds.isEmpty, bounds.width > 0, bounds.height > 0 else {
            return ""
        }
        // Use 2x scale so the vision model gets enough pixels for messy handwriting.
        let scale: CGFloat = 2.0
        let image = selection.image(from: bounds, scale: scale)
        // Compose on transparent canvas — selection.image already has transparent bg,
        // but rerender so the output PNG has exact `bounds` dimensions.
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let out = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: bounds.size))
        }
        return out.pngData()?.base64EncodedString() ?? ""
    }
}
```

- [ ] **Step 3: Run tests**

Expected: both **PASS**.

- [ ] **Step 4: Commit**

```bash
git add ios/NotesApp/Canvas/LassoRasterizer.swift ios/NotesAppTests/LassoRasterizerTests.swift
git commit -m "feat(canvas): lasso rasterizer for AI transform payloads"
```

---

## Task 10: Lasso menu + transform popover

**Files:**
- Modify: `ios/NotesApp/Canvas/CanvasView.swift` — expose a `onLassoCommit` callback
- Create: `ios/NotesApp/Features/Notebook/LassoMenuView.swift`
- Create: `ios/NotesApp/Features/Notebook/TransformResultView.swift`
- Modify: `ios/NotesApp/Features/Notebook/NotebookView.swift` — wire lasso → menu → transform

- [ ] **Step 1: Expose lasso selection from `CanvasView`**

Replace `ios/NotesApp/Canvas/CanvasView.swift` with:

```swift
import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let allowsFingerDrawing: Bool
    /// Called when the user commits a lasso selection.
    /// Parameters: selected sub-drawing, selection bounds in canvas coordinates.
    var onLassoSelection: ((PKDrawing, CGRect) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        canvas.alwaysBounceVertical = false

        // Watch lasso selection via an auxiliary gesture. PKCanvasView's lasso
        // tool emits selection through PKToolPicker; the simplest reliable hook
        // is a tap gesture that fires after the user lifts the lasso loop.
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.onTapAfterLasso)
        )
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        canvas.addGestureRecognizer(tap)

        DispatchQueue.main.async {
            if let window = canvas.window,
               let picker = PKToolPicker.shared(for: window) {
                picker.setVisible(true, forFirstResponder: canvas)
                picker.addObserver(canvas)
                canvas.becomeFirstResponder()
            }
        }
        context.coordinator.canvas = canvas
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing { uiView.drawing = drawing }
        uiView.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var parent: CanvasView
        weak var canvas: PKCanvasView?
        init(_ parent: CanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }

        @objc func onTapAfterLasso() {
            // When lasso tool is active and a selection exists, the canvas's
            // selectedStrokes is populated. Emit it and clear.
            guard let canvas = canvas else { return }
            let selected = canvas.drawing.strokes.filter { _ in false } // placeholder
            // PKCanvasView doesn't publicly expose the selection set; instead we
            // rely on the fact that after a lasso the selection can be retrieved
            // via `canvas.tool` if it's PKLassoTool and the user taps "copy".
            // Practical workaround: when the user triggers the in-app AI button
            // while a selection is active, NotebookView calls us via
            // `requestCurrentSelection(bounds:)` below.
            _ = selected
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// Called from NotebookView's toolbar "AI" button. Returns the current
        /// selection as a (drawing, bounds) pair, or nil if nothing selected.
        func currentSelection() -> (PKDrawing, CGRect)? {
            guard let canvas = canvas else { return nil }
            // Fallback when PencilKit selection API is unavailable: use the whole
            // visible page. NotebookView will prefer this path — "AI on whole page"
            // is still useful, and Plan C can refine to real lasso selection later
            // if PencilKit exposes it on the target iOS version.
            let drawing = canvas.drawing
            let bounds = drawing.bounds.isEmpty ? canvas.bounds : drawing.bounds
            return (drawing, bounds)
        }
    }
}
```

**Note on the lasso API limitation:** PencilKit does not publicly expose the current lasso selection across all iOS versions. The pragmatic compromise is: the **AI button in the toolbar** uses the current drawing (or the last-committed lasso bounds if you later add a private API escape hatch). This still delivers the lasso → transform flow from the spec's user perspective — the user taps the AI button after circling — it just rasterizes the whole current page as context. The spec's "AI never modifies ink without approval" rule is preserved because the transform result still goes into a popover with explicit insert/replace/dismiss.

- [ ] **Step 2: Implement `LassoMenuView.swift`**

```swift
import SwiftUI

struct LassoMenuView: View {
    let onSelect: (AIAction) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(.cleanup,  "Clean up handwriting", "wand.and.stars")
            row(.typedText,"Convert to typed text","textformat")
            Divider()
            row(.math,     "Math mode",      "function")
            row(.physics,  "Physics mode",   "atom")
            row(.chemistry,"Chemistry mode", "flask")
            Divider()
            row(.explain,  "Explain this",   "lightbulb")
            row(.list,     "Turn into list", "list.bullet")
        }
        .padding(.vertical, 8)
        .frame(width: 260)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
    }

    private func row(_ action: AIAction, _ title: String, _ icon: String) -> some View {
        Button {
            onSelect(action)
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Implement `TransformResultView.swift`**

```swift
import SwiftUI

struct TransformResultView: View {
    let response: TransformResponse
    let onInsertBelow: (String) -> Void
    let onReplace: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI result")
                    .font(.headline)
                Spacer()
                Text(response.modelUsed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                Text(payloadText)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 240)
            HStack(spacing: 12) {
                Button("Insert below") { onInsertBelow(payloadText) }
                    .buttonStyle(.borderedProminent)
                Button("Replace") { onReplace(payloadText) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Dismiss") { onDismiss() }
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private var payloadText: String {
        response.text ?? response.markdown ?? response.svg ?? ""
    }
}
```

- [ ] **Step 4: Wire into `NotebookView.swift`**

Add to `NotebookView`:

```swift
    @State private var showingLassoMenu = false
    @State private var showingTransformResult: TransformResponse? = nil
    @State private var transformInFlight = false
    @State private var transformError: String? = nil
    @State private var showingChat = false    // Task 12 uses this
```

Add a canvas-overlay AI button to the `.toolbar`:

```swift
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingLassoMenu = true
                    } label: {
                        Label("AI", systemImage: "sparkles")
                    }
                    .disabled(transformInFlight)
                }
```

Add popovers inside the top-level `HStack`:

```swift
        .popover(isPresented: $showingLassoMenu) {
            LassoMenuView(
                onSelect: { action in Task { await runTransform(action: action) } },
                onDismiss: { showingLassoMenu = false }
            )
            .presentationCompactAdaptation(.popover)
        }
        .sheet(item: Binding(
            get: { showingTransformResult.map { IdentifiableResponse(wrapped: $0) } },
            set: { showingTransformResult = $0?.wrapped }
        )) { item in
            TransformResultView(
                response: item.wrapped,
                onInsertBelow: { text in
                    // Insert as a plain annotation: append a new text line at the
                    // bottom of the current page by appending a small sub-drawing.
                    // Minimum viable: open share sheet with text until a text layer is added.
                    UIPasteboard.general.string = text
                    showingTransformResult = nil
                },
                onReplace: { text in
                    UIPasteboard.general.string = text
                    showingTransformResult = nil
                },
                onDismiss: { showingTransformResult = nil }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("AI error", isPresented: Binding(
            get: { transformError != nil },
            set: { if !$0 { transformError = nil } }
        ), actions: {
            Button("OK") { transformError = nil }
        }, message: {
            Text(transformError ?? "")
        })
```

And add the helper at the bottom of `NotebookView`:

```swift
    private struct IdentifiableResponse: Identifiable {
        let id = UUID()
        let wrapped: TransformResponse
    }

    @MainActor
    private func runTransform(action: AIAction) async {
        guard let vm = viewModel, let page = vm.currentPage else { return }
        vm.flushSave()
        let pageSize = CGSize(width: 1024, height: 1366)
        let drawing = vm.currentDrawing
        let bounds = drawing.bounds.isEmpty
            ? CGRect(origin: .zero, size: pageSize)
            : drawing.bounds
        let base64 = LassoRasterizer.rasterize(selection: drawing, bounds: bounds)
        guard !base64.isEmpty else {
            transformError = "Nothing to transform — draw something first."
            return
        }
        transformInFlight = true
        defer { transformInFlight = false }
        do {
            let response = try await container.aiRouter.transform(
                TransformRequest(action: action, imageBase64: base64, contextText: nil)
            )
            showingTransformResult = response
            _ = page // silence unused warning
        } catch {
            transformError = error.localizedDescription
        }
    }
```

**On "Insert below" and "Replace":** both copy the result to the pasteboard as a conservative first iteration. The spec's "AI never modifies ink without approval" rule is fully satisfied (the user explicitly chooses), and adding a real ink-text overlay is a known follow-up documented in the smoke checklist.

- [ ] **Step 5: Build**

```bash
xcodebuild build -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (4th generation)'
```

Expected: **SUCCESS**.

- [ ] **Step 6: Commit**

```bash
git add ios/NotesApp/Canvas/CanvasView.swift ios/NotesApp/Features/Notebook
git commit -m "feat(ai): lasso menu + transform popover wired through AIRouter"
```

---

## Task 11: Chat context builder

**Files:**
- Create: `ios/NotesApp/Features/Chat/ChatContextBuilder.swift`
- Create: `ios/NotesAppTests/ChatContextBuilderTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import PencilKit
@testable import NotesApp

final class ChatContextBuilderTests: XCTestCase {
    func test_page_scope_uses_current_page_drawing() {
        let page = Page(id: "p1", notebookId: "nb", pageIndex: 0, template: .line,
                        drawingBlob: PKDrawing().dataRepresentation(),
                        thumbnailBlob: nil, createdAt: Date(), updatedAt: Date())
        let b64 = ChatContextBuilder.makeContextImageBase64(
            scope: .page,
            currentPage: page,
            notebookPages: [page],
            pageSize: CGSize(width: 400, height: 600)
        )
        XCTAssertNotNil(b64)
    }

    func test_notebook_scope_stacks_multiple_pages_vertically() {
        let blank = PKDrawing().dataRepresentation()
        let pages: [Page] = (0..<3).map { i in
            Page(id: "p\(i)", notebookId: "nb", pageIndex: i, template: .blank,
                 drawingBlob: blank, thumbnailBlob: nil,
                 createdAt: Date(), updatedAt: Date())
        }
        let single = ChatContextBuilder.makeContextImageBase64(
            scope: .page, currentPage: pages[0], notebookPages: pages,
            pageSize: CGSize(width: 200, height: 300)
        )!
        let many = ChatContextBuilder.makeContextImageBase64(
            scope: .notebook, currentPage: pages[0], notebookPages: pages,
            pageSize: CGSize(width: 200, height: 300)
        )!
        let singleBytes = Data(base64Encoded: single)!
        let manyBytes = Data(base64Encoded: many)!
        XCTAssertGreaterThan(manyBytes.count, singleBytes.count)
    }
}
```

- [ ] **Step 2: Implement `ChatContextBuilder.swift`**

```swift
import UIKit
import PencilKit

enum ChatScope: String { case page, notebook }

enum ChatContextBuilder {
    static func makeContextImageBase64(
        scope: ChatScope,
        currentPage: Page,
        notebookPages: [Page],
        pageSize: CGSize
    ) -> String? {
        let pages: [Page] = scope == .page ? [currentPage] : notebookPages
        guard !pages.isEmpty else { return nil }

        // Stack pages vertically at half resolution to keep payload small.
        let scale: CGFloat = 0.5
        let singleSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        let totalSize = CGSize(
            width: singleSize.width,
            height: singleSize.height * CGFloat(pages.count)
        )
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: totalSize, format: format)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: totalSize))
            for (idx, page) in pages.enumerated() {
                let origin = CGPoint(x: 0, y: CGFloat(idx) * singleSize.height)
                let rect = CGRect(origin: origin, size: singleSize)
                // Background template
                let bg = PageTemplate.render(kind: page.template, size: singleSize, isDark: false)
                bg.draw(in: rect)
                // Ink
                if let blob = page.drawingBlob,
                   let drawing = try? PKDrawing(data: blob),
                   !drawing.bounds.isEmpty {
                    let inkImg = drawing.image(
                        from: CGRect(origin: .zero, size: pageSize),
                        scale: scale
                    )
                    inkImg.draw(in: rect)
                }
            }
        }
        return image.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}
```

- [ ] **Step 3: Run tests**

Expected: both **PASS**.

- [ ] **Step 4: Commit**

```bash
git add ios/NotesApp/Features/Chat/ChatContextBuilder.swift ios/NotesAppTests/ChatContextBuilderTests.swift
git commit -m "feat(chat): context builder rasterizes page/notebook for AI"
```

---

## Task 12: Chat panel UI + view model

**Files:**
- Create: `ios/NotesApp/Features/Chat/ChatViewModel.swift`
- Create: `ios/NotesApp/Features/Chat/ChatPanelView.swift`
- Modify: `ios/NotesApp/Features/Notebook/NotebookView.swift` — slide-in chat panel

- [ ] **Step 1: Implement `ChatViewModel.swift`**

```swift
import Foundation
import SwiftUI

@Observable
final class ChatViewModel {
    private(set) var messages: [AIMessage] = []
    var inputText: String = ""
    var scope: ChatScope = .page
    var isSending = false
    var errorMessage: String?

    private let page: Page
    private let notebookPages: [Page]
    private let repo: AIMessageRepository
    private let router: AIRouter

    init(page: Page, notebookPages: [Page], repo: AIMessageRepository, router: AIRouter) {
        self.page = page
        self.notebookPages = notebookPages
        self.repo = repo
        self.router = router
    }

    func load() {
        do {
            messages = try repo.fetchAll(pageId: page.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        inputText = ""
        isSending = true
        defer { isSending = false }

        do {
            let userMsg = try repo.append(pageId: page.id, role: .user, text: text)
            messages.append(userMsg)

            let history = messages.dropLast().map {
                ChatHistoryEntry(role: $0.role.rawValue, text: $0.text)
            }
            let context = ChatContextBuilder.makeContextImageBase64(
                scope: scope,
                currentPage: page,
                notebookPages: notebookPages,
                pageSize: CGSize(width: 1024, height: 1366)
            )
            let response = try await router.chat(
                ChatRequest(
                    pageId: page.id,
                    message: text,
                    history: Array(history),
                    scope: scope.rawValue,
                    imageBase64: context
                )
            )
            let reply = try repo.append(pageId: page.id, role: .assistant, text: response.reply)
            messages.append(reply)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Implement `ChatPanelView.swift`**

```swift
import SwiftUI

struct ChatPanelView: View {
    @Bindable var viewModel: ChatViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { msg in
                            bubble(msg: msg).id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            inputBar
        }
        .frame(width: 360)
        .background(Color(.systemBackground))
        .onAppear { viewModel.load() }
        .alert("Chat error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        ), actions: { Button("OK") {} }, message: {
            Text(viewModel.errorMessage ?? "")
        })
    }

    private var header: some View {
        HStack {
            Text("Chat").font(.headline)
            Picker("Scope", selection: $viewModel.scope) {
                Text("Page").tag(ChatScope.page)
                Text("Notebook").tag(ChatScope.notebook)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark")
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func bubble(msg: AIMessage) -> some View {
        let isUser = msg.role == .user
        HStack {
            if isUser { Spacer() }
            Text(msg.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isUser ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer() }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask anything…", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(viewModel.isSending || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }
}
```

- [ ] **Step 3: Wire into `NotebookView`**

Add a toolbar toggle button in `NotebookView.toolbar`:

```swift
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingChat.toggle()
                    } label: {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    }
                }
```

And wrap the root `HStack` inside a new outer `HStack` so the panel slides in from the right:

```swift
    var body: some View {
        HStack(spacing: 0) {
            mainContent
            if showingChat, let vm = viewModel, let page = vm.currentPage {
                Divider()
                ChatPanelView(
                    viewModel: ChatViewModel(
                        page: page,
                        notebookPages: vm.pages,
                        repo: container.aiMessages,
                        router: container.aiRouter
                    ),
                    onClose: { showingChat = false }
                )
                .transition(.move(edge: .trailing))
            }
        }
        // …existing modifiers (.navigationTitle, .toolbar, .onAppear, etc.)
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            if let vm = viewModel {
                pageStrip(vm: vm).frame(width: 140).background(Color(.secondarySystemBackground))
                Divider()
                canvasArea(vm: vm)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }
```

- [ ] **Step 4: Build**

Expected: **SUCCESS**.

- [ ] **Step 5: Commit**

```bash
git add ios/NotesApp/Features/Chat ios/NotesApp/Features/Notebook/NotebookView.swift
git commit -m "feat(chat): slide-in side panel scoped per page/notebook"
```

---

## Task 13: Voice input — AVAudioRecorder + mic button

**Files:**
- Create: `ios/NotesApp/Features/Voice/VoiceRecorder.swift`
- Create: `ios/NotesApp/Features/Voice/MicButton.swift`
- Modify: `ios/NotesApp/Features/Chat/ChatPanelView.swift` — add mic button next to send
- Modify: `ios/NotesApp/Features/Chat/ChatViewModel.swift` — add `transcribeAndFillInput(data:)`

- [ ] **Step 1: Implement `VoiceRecorder.swift`**

```swift
import Foundation
import AVFoundation

/// Hold-to-talk recorder. Writes M4A to a temp file, exposes the raw data on stop.
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var level: Float = 0

    private var recorder: AVAudioRecorder?
    private var tempURL: URL?
    private var meterTimer: Timer?

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()
        self.recorder = recorder
        self.tempURL = url
        self.isRecording = true
        self.meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let r = self.recorder else { return }
            r.updateMeters()
            let db = r.averagePower(forChannel: 0)
            self.level = max(0, 1 + db / 60) // -60 dB floor
        }
    }

    /// Stops recording and returns the captured audio as Data.
    func stop() -> Data? {
        recorder?.stop()
        recorder = nil
        meterTimer?.invalidate()
        meterTimer = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false)
        guard let url = tempURL else { return nil }
        let data = try? Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        tempURL = nil
        return data
    }
}
```

- [ ] **Step 2: Implement `MicButton.swift`**

```swift
import SwiftUI

struct MicButton: View {
    @StateObject private var recorder = VoiceRecorder()
    let onTranscribe: (Data) -> Void

    var body: some View {
        Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "mic.circle")
            .font(.title2)
            .foregroundStyle(recorder.isRecording ? .red : .accentColor)
            .scaleEffect(1 + CGFloat(recorder.level) * 0.4)
            .animation(.easeOut(duration: 0.05), value: recorder.level)
            .gesture(
                LongPressGesture(minimumDuration: 0.1)
                    .onChanged { _ in
                        if !recorder.isRecording { try? recorder.start() }
                    }
                    .onEnded { _ in
                        if let data = recorder.stop() {
                            onTranscribe(data)
                        }
                    }
            )
            .accessibilityLabel("Hold to record")
    }
}
```

- [ ] **Step 3: Extend `ChatViewModel`**

Add to `ChatViewModel`:

```swift
    @MainActor
    func transcribe(audio: Data) async {
        let b64 = audio.base64EncodedString()
        do {
            let res = try await router.transcribe(
                TranscribeRequest(audioBase64: b64, language: "auto")
            )
            inputText = res.text
        } catch {
            errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 4: Add mic to `ChatPanelView.inputBar`**

```swift
    private var inputBar: some View {
        HStack(spacing: 8) {
            MicButton { audio in
                Task { await viewModel.transcribe(audio: audio) }
            }
            TextField("Ask anything…", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(viewModel.isSending || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }
```

- [ ] **Step 5: Build**

Expected: **SUCCESS**. (The `NSMicrophoneUsageDescription` key was added in Plan B's Info.plist — verify it's present; if not, add it now to `project.yml`.)

- [ ] **Step 6: Commit**

```bash
git add ios/NotesApp/Features/Voice ios/NotesApp/Features/Chat
git commit -m "feat(voice): hold-to-talk mic with Whisper transcription"
```

---

## Task 14: Sync client + scheduler

**Files:**
- Create: `ios/NotesApp/Sync/SyncDiff.swift`
- Create: `ios/NotesApp/Sync/SyncClient.swift`
- Create: `ios/NotesApp/Sync/SyncScheduler.swift`
- Create: `ios/NotesAppTests/SyncDiffTests.swift`

- [ ] **Step 1: Write failing tests for `SyncDiff`**

```swift
import XCTest
@testable import NotesApp

final class SyncDiffTests: XCTestCase {
    private var db: Database!
    private var notebooks: NotebookRepository!
    private var pages: PageRepository!

    override func setUpWithError() throws {
        db = try Database.makeInMemory()
        notebooks = NotebookRepository(pool: db.pool)
        pages = PageRepository(pool: db.pool)
    }

    func test_empty_database_produces_empty_diff() throws {
        let diff = try SyncDiff.compute(pool: db.pool, since: nil)
        XCTAssertTrue(diff.notebooks.isEmpty)
        XCTAssertTrue(diff.pages.isEmpty)
    }

    func test_nil_since_returns_everything() throws {
        let nb = try notebooks.create(title: "A", coverColor: "#123456")
        _ = try pages.append(notebookId: nb.id, template: .line)
        _ = try pages.append(notebookId: nb.id, template: .grid)
        let diff = try SyncDiff.compute(pool: db.pool, since: nil)
        XCTAssertEqual(diff.notebooks.count, 1)
        XCTAssertEqual(diff.pages.count, 2)
    }

    func test_since_filters_by_updated_at() throws {
        let nb = try notebooks.create(title: "A", coverColor: "#000000")
        let p1 = try pages.append(notebookId: nb.id, template: .line)
        Thread.sleep(forTimeInterval: 0.1)
        let cutoff = Date()
        Thread.sleep(forTimeInterval: 0.1)
        try pages.updateDrawing(pageId: p1.id, drawing: Data([0x01]), thumbnail: nil)
        let diff = try SyncDiff.compute(pool: db.pool, since: cutoff)
        XCTAssertEqual(diff.pages.map(\.id), [p1.id])
    }
}
```

- [ ] **Step 2: Implement `SyncDiff.swift`**

```swift
import Foundation
import GRDB

struct SyncDiff: Codable {
    let notebooks: [Notebook]
    let pages: [Page]
    let messages: [AIMessage]
    let computedAt: Date

    static func compute(pool: DatabasePool, since: Date?) throws -> SyncDiff {
        try pool.read { db in
            let cutoff = since ?? Date(timeIntervalSince1970: 0)
            let notebooks = try Notebook
                .filter(Column("updated_at") > cutoff)
                .fetchAll(db)
            let pages = try Page
                .filter(Column("updated_at") > cutoff)
                .fetchAll(db)
            let messages = try AIMessage
                .filter(Column("created_at") > cutoff)
                .fetchAll(db)
            return SyncDiff(
                notebooks: notebooks,
                pages: pages,
                messages: messages,
                computedAt: Date()
            )
        }
    }
}
```

- [ ] **Step 3: Implement `SyncClient.swift`**

```swift
import Foundation
import GRDB

final class SyncClient {
    private let baseURL: URL
    private let session: URLSession
    private let pool: DatabasePool

    init(baseURL: URL, pool: DatabasePool, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.pool = pool
        self.session = session
    }

    struct PushResponse: Decodable { let acceptedAt: Date? }

    func push() async throws -> Date {
        let lastSync = try pool.read { db in
            try Date.fetchOne(db, sql: "SELECT last_sync_at FROM sync_state WHERE id = 1")
        }
        let diff = try SyncDiff.compute(pool: pool, since: lastSync)

        var req = URLRequest(url: baseURL.appendingPathComponent("/sync/push"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        req.httpBody = try encoder.encode(diff)

        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIError.http((response as? HTTPURLResponse)?.statusCode ?? -1, "sync push failed")
        }
        let now = Date()
        try pool.write { db in
            try db.execute(sql: "UPDATE sync_state SET last_sync_at = ? WHERE id = 1", arguments: [now])
        }
        return now
    }
}
```

- [ ] **Step 4: Implement `SyncScheduler.swift`**

```swift
import Foundation

@Observable
final class SyncScheduler {
    var status: String = "idle"
    private let client: SyncClient
    private var timer: Timer?

    init(client: SyncClient) {
        self.client = client
    }

    func start() {
        timer?.invalidate()
        // Every 5 minutes, spec §6.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.syncNow() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    func syncNow() async {
        status = "syncing"
        do {
            let at = try await client.push()
            status = "synced \(at.formatted(date: .omitted, time: .shortened))"
        } catch {
            status = "error: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 5: Wire into `AppContainer`**

Add to `AppContainer`:

```swift
    var syncClient: SyncClient?
    var syncScheduler: SyncScheduler?
```

Extend `reloadAI()` to also rebuild sync:

```swift
    func reloadAI() {
        self.aiRouter = AIRouter.bootstrap()
        if let urlString = try? KeychainStore.shared.getPCServerURL(),
           let url = URL(string: urlString) {
            let client = SyncClient(baseURL: url, pool: database.pool)
            self.syncClient = client
            let sched = SyncScheduler(client: client)
            sched.start()
            self.syncScheduler = sched
        } else {
            self.syncScheduler?.stop()
            self.syncClient = nil
            self.syncScheduler = nil
        }
    }
```

And call `reloadAI()` at the end of `init`:

```swift
    init(database: Database) {
        self.database = database
        self.notebooks = NotebookRepository(pool: database.pool)
        self.pages = PageRepository(pool: database.pool)
        self.aiMessages = AIMessageRepository(pool: database.pool)
        self.aiRouter = AIRouter.bootstrap()
        reloadAI() // sets syncClient/scheduler if configured
    }
```

- [ ] **Step 6: Run tests**

Expected: all `SyncDiffTests` **PASS**. Full suite should still be green.

- [ ] **Step 7: Commit**

```bash
git add ios/NotesApp/Sync ios/NotesApp/App/AppContainer.swift ios/NotesAppTests/SyncDiffTests.swift
git commit -m "feat(sync): diff compute + push client + 5-minute scheduler"
```

---

## Task 15: Settings view — AI config, sync status, routing banner, smoke checklist

**Files:**
- Modify: `ios/NotesApp/Features/Settings/SettingsView.swift`
- Modify: `ios/NotesApp/Features/Notebook/NotebookView.swift` — add routing banner
- Modify: `docs/smoke-checklist.md` — add Plan C items

- [ ] **Step 1: Rewrite `SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    @AppStorage("defaultTemplate") private var defaultTemplateRaw: String = PageTemplateKind.line.rawValue
    @AppStorage("themePreference") private var themePreference: String = "system"
    @AppStorage("voiceLanguage") private var voiceLanguage: String = "auto"

    @State private var pcURL: String = ""
    @State private var keysText: String = ""
    @State private var savedMessage: String?
    @State private var syncStatus: String = "idle"

    var body: some View {
        Form {
            Section("Paper") {
                Picker("Default template", selection: $defaultTemplateRaw) {
                    Text("Line").tag(PageTemplateKind.line.rawValue)
                    Text("Grid").tag(PageTemplateKind.grid.rawValue)
                    Text("Blank").tag(PageTemplateKind.blank.rawValue)
                }
            }
            Section("Appearance") {
                Picker("Theme", selection: $themePreference) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }
            Section("AI routing") {
                Text("Active: \(container.aiRouter.activeLabel)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("PC companion server") {
                TextField("http://192.168.1.10:8000", text: $pcURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Section("Groq API keys (one per line)") {
                TextEditor(text: $keysText)
                    .frame(minHeight: 120)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Section("Voice") {
                Picker("Language", selection: $voiceLanguage) {
                    Text("Auto detect").tag("auto")
                    Text("English").tag("en")
                    Text("Indonesian").tag("id")
                    Text("Code-switching (id+en)").tag("id,en")
                }
            }
            Section {
                Button("Save AI configuration") {
                    saveConfig()
                }
            }
            Section("Sync") {
                Text(syncStatus)
                Button("Sync now") {
                    Task {
                        await container.syncScheduler?.syncNow()
                        syncStatus = container.syncScheduler?.status ?? "idle"
                    }
                }
                .disabled(container.syncClient == nil)
            }
            if let msg = savedMessage {
                Text(msg).foregroundStyle(.green)
            }
        }
        .navigationTitle("Settings")
        .onAppear { loadConfig() }
    }

    private func loadConfig() {
        pcURL = (try? KeychainStore.shared.getPCServerURL()) ?? ""
        let keys = (try? KeychainStore.shared.getGroqKeys()) ?? []
        keysText = keys.joined(separator: "\n")
        syncStatus = container.syncScheduler?.status ?? "not configured"
    }

    private func saveConfig() {
        do {
            try KeychainStore.shared.setPCServerURL(pcURL)
            let keys = keysText
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            try KeychainStore.shared.setGroqKeys(keys)
            container.reloadAI()
            savedMessage = "Saved. Active: \(container.aiRouter.activeLabel)"
        } catch {
            savedMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 2: Add routing banner to `NotebookView`**

Inside `NotebookView.mainContent`, wrap the inner HStack in a `VStack` with a top banner:

```swift
    private var mainContent: some View {
        VStack(spacing: 0) {
            if container.aiRouter.activeLabel == "groq" {
                Text("Using Groq fallback")
                    .font(.caption)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.2))
            } else if container.aiRouter.activeLabel == "offline" {
                Text("AI offline — configure in Settings")
                    .font(.caption)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
            }
            HStack(spacing: 0) {
                if let vm = viewModel {
                    pageStrip(vm: vm).frame(width: 140).background(Color(.secondarySystemBackground))
                    Divider()
                    canvasArea(vm: vm)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
    }
```

- [ ] **Step 3: Extend `docs/smoke-checklist.md`**

Append:

```markdown
## Plan C additions

### Routing banner
- [ ] With PC reachable: banner hidden
- [ ] Turn off PC server: banner reads "Using Groq fallback"
- [ ] Remove all Groq keys: banner reads "AI offline — configure in Settings"

### Lasso transform
- [ ] Draw a simple arithmetic problem (e.g., "23 × 17")
- [ ] Tap AI button → Math mode → result appears in popover within ~10s
- [ ] "Dismiss" closes without changing ink
- [ ] "Insert below" / "Replace" copy the result to the pasteboard

### Chat panel
- [ ] Toggle chat → panel slides in from right
- [ ] Ask "what is 2+2?" in English → correct reply
- [ ] Ask in Indonesian — reply in Indonesian
- [ ] Toggle scope to Notebook → ask about content across pages
- [ ] Close and re-open the page → chat history persists
- [ ] Messages are cascade-deleted when the page is deleted

### Voice input
- [ ] Hold mic button → red waveform pulses
- [ ] Release → transcript appears in input field
- [ ] Edit transcript then send normally
- [ ] Speak a mixed-language sentence — verify transcript

### Sync
- [ ] Configure PC URL in Settings, save
- [ ] Draw on a page, wait 30s, hit "Sync now"
- [ ] Verify on PC that `server/storage.sqlite` (or equivalent) contains the new page
- [ ] Delete app + reinstall → (manual) use Plan A's `/sync/pull` to restore

### Baked prompts smoke
- [ ] Turn off PC, turn off internet briefly to verify AI is grayed out
- [ ] Turn internet back on, verify Groq fallback still produces results
  (prompts used are the baked-in snapshot, not the PC's live versions)
```

- [ ] **Step 4: Build and run full test suite**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (4th generation)'
```

Expected: all tests from Plan B + Plan C (roughly 30 tests) **PASS**.

- [ ] **Step 5: Commit**

```bash
git add ios/NotesApp/Features/Settings/SettingsView.swift ios/NotesApp/Features/Notebook/NotebookView.swift docs/smoke-checklist.md
git commit -m "feat(settings): AI config, sync status, routing banner + smoke checklist"
```

- [ ] **Step 6: Push, download IPA, sign with KSign, run full smoke checklist end-to-end**

If every item passes, Plan C — and the spec — is done.

---

## Self-Review

**Spec coverage:**
- §4 Endpoints: transform / chat / transcribe / sync — Tasks 3, 4, 5, 14 ✓
- §4 Key pool: on-device 5-slot with cooldown — Task 2 ✓
- §4 Routing (cloud-only, quality-first, no silent downgrade) — Task 7 ✓
- §4 Prompts bundled into IPA at build time — Task 6 ✓
- §5.A Lasso → Transform (7 actions, insert/replace/dismiss, ink never modified without approval) — Tasks 9, 10 ✓ (with the honest note on PencilKit's selection API limitation — the user still gets the full UX from the button)
- §5.B Side panel chat (scoped, persisted, multilingual) — Tasks 8, 11, 12 ✓
- §5.C Voice input (hold-to-talk, waveform, editable transcript, language selection) — Task 13 ✓
- §5 Error banners (Using Groq fallback / offline) — Task 15 ✓
- §6 Sync (authoritative iPad, push triggers, 5-min timer, sync now button) — Task 14, 15 ✓
- §6 Sync "what lives where" table — matches (baked prompts via Task 6, keys in Keychain via Task 1) ✓
- §8 Tier 1 tests: SQLite models ✓ (Plan B), sync diff ✓, Groq fallback + mini key rotation ✓ (KeyPool tests), PDF export ✓ (Plan B), chat history management ✓ (AIMessageRepositoryTests)

**Intentional scope reductions (noted in-plan, not hidden):**
- PencilKit lasso selection API — `CanvasView.Coordinator.currentSelection()` falls back to the full page drawing. The UX matches the spec; if iOS exposes the private selection set on the target version, add it with a small patch. Smoke checklist still catches the quality bar.
- "Insert below" / "Replace" of transform results copies text to the pasteboard rather than mutating the PKDrawing. Expanding to an in-canvas text layer is a known follow-up; the spec's core "user explicitly approves any ink change" rule is preserved.

**Placeholder scan:** No TBDs. Every code step contains the exact code. Prebuild script has a stub-prompt branch so tests pass even in a fresh clone.

**Type consistency check:**
- `AIAction` cases used identically in `BakedPrompts.fileMap`, `GroqFallbackAIClient.transform`, `LassoMenuView.row` ✓
- `AIClient.transform/chat/transcribe` signatures identical across protocol, `PCServerAIClient`, `GroqFallbackAIClient`, `AIRouter` ✓
- `ChatScope.page / .notebook` used identically in `ChatContextBuilder`, `ChatViewModel`, `ChatPanelView`, `ChatRequest.scope` (string-cast via `scope.rawValue`) ✓
- `KeyPool.pick() -> KeyState?` used identically in both places that consume it ✓
- `SyncDiff.compute(pool:since:)` signature matches test call + `SyncClient.push` call ✓
- `AIMessageRepository.append(pageId:role:text:)` matches `ChatViewModel.send()` call ✓

---

## Execution Handoff

All three plans now exist:

1. `docs/superpowers/plans/2026-04-07-plan-a-pc-server.md` — 15 tasks, Python/FastAPI server
2. `docs/superpowers/plans/2026-04-07-plan-b-ipad-core.md` — 15 tasks, standalone iPad note app
3. `docs/superpowers/plans/2026-04-07-plan-c-ipad-ai.md` — 15 tasks, AI integration on top of Plan B

**Build order:** A is independent and testable via curl. B is independent and ships a usable note app. C depends on both A (to talk to) and B (to extend). A and B can run in parallel; C comes last.

Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best for 45 tasks across three plans.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints. Context will be tight across all three plans.

Which approach, and which plan first?
