# Project Handoff

## What this is
iPad AI notes app — PencilKit canvas + Groq AI backend. Solo dev, Windows PC + iPad.
Full spec: `docs/specs/2026-04-07-ipad-ai-notes-design.md`

## Status
- **Plan A (Python server):** COMPLETE. All 15 tasks done, 29 tests passing.
  - FastAPI server at `server/` — /health, /ai/chat, /ai/transform, /ai/transcribe, /sync/push, /sync/pull
  - Live-tested against real Groq keys, works.
  - Run: `cd server && .venv/Scripts/activate && uvicorn notes_server.server:app --reload`
  - Test: `cd server && pytest`

- **Plan B (iOS app):** COMPLETE. All 15 tasks done, CI green, IPA sideloaded and smoke-tested on iPad.
  - All 7 smoke checklist items passed (`docs/smoke-checklist.md`)
  - Pinch-to-zoom works: ink stays sharp (PKCanvasView native zoom), template re-renders sharp after gesture
  - Run: CI → Actions tab → download `NotesApp-ipa` artifact → sideload via KSign

- **Plan C (AI integration into iOS):** COMPLETE. All 15 tasks implemented and CI green.
  - Keychain store (injectable `SecretStorage` protocol), KeyPool (5-slot rotation), AIClient protocol
  - `PCServerAIClient` (home, 1.5s ping probe), `GroqFallbackAIClient` (school fallback, direct Groq REST)
  - `AIRouter` (@Observable, reachability probe, no silent downgrade, routing banner)
  - Baked prompts (`ios/Scripts/copy-prompts.sh` → bundle resource), `BakedPrompts.swift`
  - Lasso transform: `LassoRasterizer` → `LassoMenuView` (7 actions) → `TransformResultView` popover
  - Chat panel: `ChatContextBuilder`, `ChatViewModel`, `ChatPanelView` (scope picker, bubble UI)
  - Voice input: `VoiceRecorder` (AVAudioRecorder, hold-to-talk), `MicButton`
  - Sync: `SyncDiff`, `SyncClient` (push), `SyncScheduler` (5-min timer)
  - `AppContainer` wired: `aiMessages`, `aiRouter`, `syncClient`, `syncScheduler`
  - `SettingsView`: PC URL, Groq keys, voice language, routing label, sync now button
  - ⚠️ AI features require runtime config (PC URL or Groq keys in Settings) before use — see smoke checklist

## Key files
- Plans: `docs/plans/`
- Spec: `docs/specs/`
- Server: `server/` (Python/FastAPI)
- iOS app: `ios/` (Swift/SwiftUI/PencilKit/GRDB)
- CI workflow: `.github/workflows/build-ipa.yml`

## Tech
- Server: Python 3.11, FastAPI, Groq SDK, SQLite (GRDB sync mirror)
- iOS: Swift 5.10, iOS 17+, SwiftUI, PencilKit, GRDB.swift 6.x
- Build: XcodeGen + GitHub Actions macos-15 runner → unsigned IPA → KSign sideload
- API keys: in server/config.yaml (gitignored), originals in AI fighting/ai-boxing/.env

---

## What was fixed in this session (2026-04-09)

### 1. `Database` → `AppDatabase` rename (CI fix)
**Problem:** Our `Database` class collided with GRDB's internal `Database` type. Swift couldn't resolve the ambiguity in the test target.
**Fix:** Renamed our class to `AppDatabase` in all 5 affected files:
- `ios/NotesApp/Data/Database.swift`
- `ios/NotesApp/App/AppContainer.swift`
- `ios/NotesAppTests/DatabaseTests.swift`
- `ios/NotesAppTests/NotebookRepositoryTests.swift`
- `ios/NotesAppTests/PageRepositoryTests.swift`

### 2. WAL mode crash in all DB tests
**Problem:** `SQLite error 1: could not activate WAL Mode at path: :memory:` — `DatabasePool` forces WAL mode but in-memory SQLite doesn't support it.
**Fix:**
- Changed `AppDatabase.makeInMemory()` to use `DatabaseQueue` instead of `DatabasePool`
- Migrated `pool: DatabasePool` → `writer: any DatabaseWriter` throughout:
  - `AppDatabase`, `Migrations`, `NotebookRepository`, `PageRepository`, `AppContainer`, all test files
- Production `makeDefault()` still uses `DatabasePool` (needs concurrent reads)

### 3. ThumbnailRenderer size mismatch on 2x Retina CI simulator
**Problem:** `UIGraphicsImageRenderer` renders at screen scale (2×); `UIImage(data:)` reads back at scale 1.0 → reported size = pixel dimensions (320×426 instead of 160×213).
**Fix:** Force `UIGraphicsImageRendererFormat.scale = 1.0` so PNG pixel dimensions always equal `targetSize`.

### 4. CI simulator not found
**Problem:** `iPad Pro 11-inch (M4)` runtime not always cached on ephemeral GitHub Actions runners.
**Fix:** Use `xcrun simctl list devices available | grep -E "iPad.*\(" | head -1 | grep -oE '[0-9A-F-]{36}'` to dynamically pick any available iPad simulator UDID. Also fixed YAML syntax error (multi-line Python heredoc was terminating the YAML block scalar).

### 5. Zoom implementation (multiple iterations, final architecture)
**Problem:** Needed pinch-to-zoom where both template background and ink scale together and stay sharp.

**Root cause analysis:**
- `UIScrollView` outer-wrap approach: applies GPU transform to container bitmap → BOTH ink and template are pixel-scaled → blurry at any zoom > 1x
- `UIImageView` inside `PKCanvasView` approach: UIImageView scrolls with content but isn't inside PK's `viewForZooming` → template doesn't follow zoom transform

**Final architecture (`ios/NotesApp/Canvas/CanvasView.swift`):**
- `PKCanvasView` IS the root UIScrollView — PK re-renders strokes natively at each `zoomScale` change → ink always sharp
- `UIImageView` (template) added at z=0 inside `PKCanvasView`
- KVO on `PKCanvasView.zoomScale`: resize `UIImageView.frame` immediately (cheap), then debounce a full `PageTemplate.render()` re-render 150ms after gesture settles → template sharp after zoom
- `minimumZoomScale` = fit-entire-page (computed from bounds in `DispatchQueue.main.async`) → cannot over-zoom out, no black gaps
- `maximumZoomScale = 5.0`
- `PKCanvasView.backgroundColor = .secondarySystemBackground` (gray outside page)
- `contentInset` centering so page stays centered when smaller than viewport

**Key insight:** Never use an outer `UIScrollView` for PencilKit zoom. Always use `PKCanvasView`'s own zoom — that's the only way PK re-renders strokes at higher resolution.

---

## What was done in this session (2026-04-11)

### Canvas bug fixes

**Bug 1 — Template not updating between pages**
`updateUIView` was not re-rendering `bgView` when the template or dark-mode setting changed because `coord.parent` was stale. Fixed by syncing `coord.parent = self` at the top of `updateUIView` and re-rendering when template/isDark changes.

**Bug 2 — Lines multiplying on zoom**
KVO was on `UIScrollView.zoomScale`, which PKCanvasView does not update via the normal KVO path during user pinch. Switched to `#keyPath(UIScrollView.contentSize)` — PK updates this every frame during pinch. Template now resizes from `contentSize` directly; no zoom-scale arithmetic needed. Debounced re-render at 150ms after gesture settles keeps template sharp.

**File:** `ios/NotesApp/Canvas/CanvasView.swift`

### Plan C — AI integration (all 15 tasks)

Implemented in full on top of Plan B. Key files added/modified:

| Area | Files |
|------|-------|
| Secrets | `AI/KeychainStore.swift` (injectable `SecretStorage` protocol) |
| Key rotation | `AI/KeyPool.swift` (5-slot, cooldown, error tracking) |
| AI layer | `AI/AIModels.swift`, `AI/AIClient.swift`, `AI/PCServerAIClient.swift`, `AI/GroqFallbackAIClient.swift` |
| Routing | `AI/AIRouter.swift` (@Observable, reachability probe, no silent downgrade) |
| Prompts | `AI/BakedPrompts.swift`, `Scripts/copy-prompts.sh` |
| Canvas lasso | `Canvas/LassoRasterizer.swift`, `Features/Notebook/LassoMenuView.swift`, `Features/Notebook/TransformResultView.swift` |
| Chat | `Features/Chat/ChatContextBuilder.swift`, `Features/Chat/ChatViewModel.swift`, `Features/Chat/ChatPanelView.swift` |
| Voice | `Features/Voice/VoiceRecorder.swift`, `Features/Voice/MicButton.swift` |
| Sync | `Sync/SyncDiff.swift`, `Sync/SyncClient.swift`, `Sync/SyncScheduler.swift` |
| Wiring | `App/AppContainer.swift`, `Features/Settings/SettingsView.swift` |
| Data | `Data/AIMessage.swift`, `Data/AIMessageRepository.swift` |

### CI — Keychain test fix

`KeychainStoreTests` was calling `KeychainStore.shared` which hits the real Keychain API. CI runners use ad-hoc signing which does not embed entitlements → `errSecMissingEntitlement (-34018)` → test failure. Fix: introduced `SecretStorage` protocol + `InMemoryStorage` (test-only dictionary backend). Tests now inject `KeychainStore(storage: InMemoryStorage())` — no Keychain API touched in CI.

---

## What was fixed in this session (2026-04-12)

### 1. AI offline after configuring Groq keys — banner bug + dead model
**Root cause A:** `llama-3.2-90b-vision-preview` was removed from Groq. Every transform / vision-chat call returned HTTP error → `KeyPool.markError` → 3 errors = key dead → all keys die → `allKeysExhausted`. More keys didn't help because all of them died.
**Fix:** `GroqFallbackAIClient.visionModel` → `"meta-llama/llama-4-scout-17b-16e-instruct"` (tested working).

**Root cause B:** `AIRouter.activeLabel` defaulted to `"offline"` regardless of key config. NotebookView banner checked `activeLabel == "offline"` → showed "AI offline" even with valid keys configured.
**Fix:** Added `isConfigured: Bool` computed property to `AIRouter`. Banner now checks `!container.aiRouter.isConfigured` for the offline state.

### 2. Chat through PC server — field name mismatches
`ChatHistoryEntry.text` was encoded as `"text"` but server expects `"content"`. `ChatRequest.imageBase64` was encoded as `"image_base64"` but server expects `"context_image_base64"`.
**Fix:** Added `CodingKeys` to `ChatHistoryEntry` mapping `text → "content"`. Updated `ChatRequest` CodingKey for `imageBase64 → "context_image_base64"`.

### 3. Sync always failing — request format mismatch
iOS `SyncDiff` sent flat `{notebooks, pages, messages, computedAt}` but server's `SyncPushRequest` expects `{notebooks: [{...notebook, pages: [{...page}]}], since_timestamp}`.
**Fix:** Rewrote `SyncClient.push()` to build server-compatible nested snapshots. For each changed notebook (or notebook with changed pages), fetches ALL current pages and sends as `NotebookSnapshot` with `drawing_blob_base64`, timestamps as Unix floats.

### 4. "Physics mode" label overlapping navigation title
Lasso menu `.popover` was attached to the whole view body — SwiftUI positioned it over the nav bar.
**Fix:** Moved `.popover` to the AI toolbar button itself. Popover now anchors from the sparkles button.

---

## Known issues / next steps

- **AI features need runtime config before use.** After sideloading, go to Settings and enter either:
  - PC URL (e.g. `http://192.168.x.x:8000`) — requires PC server running (`cd server && uvicorn notes_server.server:app --reload`)
  - One or more Groq API keys — for school / offline-PC fallback
- **Smoke checklist items for Plan C** (`docs/smoke-checklist.md`) have NOT yet been run end-to-end on device. Run them after configuring keys.
- Sync pull (restore after reinstall) is server-side only — not yet wired on the iOS side (Plan A's `/sync/pull` endpoint exists; iOS client for pull not implemented).

## Server quick-start reminder

```bash
cd server
.venv/Scripts/activate   # Windows
uvicorn notes_server.server:app --reload
```
