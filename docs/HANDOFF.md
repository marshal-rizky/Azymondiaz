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

- **Plan C (AI integration into iOS):** COMPLETE. All 15 tasks implemented, CI green, and **all Plan C smoke checklist items passed on device (2026-04-12)**.
  - Keychain store (injectable `SecretStorage` protocol), KeyPool (5-slot rotation), AIClient protocol
  - `PCServerAIClient` (home, 1.5s ping probe), `GroqFallbackAIClient` (school fallback, direct Groq REST)
  - `AIRouter` (@Observable, reachability probe, no silent downgrade, routing banner)
  - Baked prompts (`ios/Scripts/copy-prompts.sh` → bundle resource), `BakedPrompts.swift`
  - AI region selection: finger-drag box on canvas → crops ink → transform menu (7 actions) → `TransformResultView`
  - Chat panel: `ChatContextBuilder`, `ChatViewModel`, `ChatPanelView` (scope picker, bubble UI, MathWebView)
  - Voice input: `VoiceRecorder` (AVAudioRecorder, hold-to-talk), `MicButton`
  - Sync: `SyncDiff`, `SyncClient` (push), `SyncScheduler` (5-min timer)
  - `AppContainer` wired: `aiMessages`, `aiRouter`, `syncClient`, `syncScheduler`
  - `SettingsView`: PC URL, Groq keys, voice language, routing label, sync now button
  - ⚠️ AI features require runtime config (PC URL or Groq keys in Settings) before use

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
**Problem:** Our `Database` class collided with GRDB's internal `Database` type.
**Fix:** Renamed to `AppDatabase` in all 5 affected files.

### 2. WAL mode crash in all DB tests
**Problem:** `DatabasePool` forces WAL mode but in-memory SQLite doesn't support it.
**Fix:** `AppDatabase.makeInMemory()` uses `DatabaseQueue`; production still uses `DatabasePool`.

### 3. ThumbnailRenderer size mismatch on 2x Retina CI simulator
**Fix:** Force `UIGraphicsImageRendererFormat.scale = 1.0`.

### 4. CI simulator not found
**Fix:** Dynamically pick any available iPad simulator UDID via `xcrun simctl list`.

### 5. Zoom implementation
**Final architecture:** `PKCanvasView` IS the root UIScrollView. `UIImageView` (template) at z=0 inside it. KVO on `contentSize` resizes bgView each zoom tick; debounced 150ms re-render keeps template sharp. `minimumZoomScale` = fit-page. **Key insight:** Never wrap PKCanvasView in an outer UIScrollView — PK only re-renders strokes when its own zoomScale changes.

---

## What was done in this session (2026-04-11)

### Canvas bug fixes
- **Template not updating between pages:** `coord.parent` was stale in `updateUIView`. Fixed by syncing at top of `updateUIView`.
- **Lines multiplying on zoom:** KVO on `zoomScale` doesn't fire during pinch; switched to `contentSize` KVO.

### Plan C — AI integration (all 15 tasks)
Full implementation. See key files table in Status section above.

### CI — Keychain test fix
Introduced `SecretStorage` protocol + `InMemoryStorage` (test-only). Tests inject in-memory backend; no Keychain API in CI.

---

## What was fixed in this session (2026-04-12)

### 1. AI offline after configuring Groq keys
- **Root cause A:** `llama-3.2-90b-vision-preview` removed from Groq. Fix: updated to `meta-llama/llama-4-scout-17b-16e-instruct`.
- **Root cause B:** `AIRouter.activeLabel` defaulted `"offline"`. Fix: added `isConfigured` computed property; banner checks that instead.

### 2. Chat through PC server — field name mismatches
`ChatHistoryEntry.text` → `"content"`, `ChatRequest.imageBase64` → `"context_image_base64"` via `CodingKeys`.

### 3. Sync always failing — request format mismatch
iOS sent flat dict; server expects nested `NotebookSnapshot`. Rewrote `SyncClient.push()`.

### 4. Popover overlapping nav bar
Moved `.popover` from view body to the AI toolbar button.

### 5. AI output plain text (LaTeX/markdown not rendered)
Added `MathWebView.swift` (WKWebView + KaTeX + marked from CDN). Used in `TransformResultView` and chat assistant bubbles.

### 6. Chat blank on open; full page sent every message
- Added synthetic welcome message in `ChatViewModel.load()`.
- Context image attached on first message only (`contextAttached` flag).

### 7. App crash when AI result appeared
**Root cause:** `JSONSerialization.data(withJSONObject: bareString)` throws ObjC exception; Swift `try?` doesn't catch it. Fix: `JSONEncoder().encode(content)`.

---

## What was fixed in this session (2026-04-12, continued — AI selection overhaul)

### 1. Lasso AI always scanning full page (root cause: wrong gesture recognizer)
**Root cause:** `PKCanvasView.drawingGestureRecognizer` handles **finger** input only (per Apple docs). Pencil lasso is routed through PencilKit's private internal recognizer — no public API to observe it. All previous `handleLassoGesture` code was dead; `lassoSelectionBounds` was always nil.

**Fix:** Replaced PencilKit lasso detection entirely with a dedicated **finger AI-selection mode**:
- Sparkles button tapped → canvas enters `aiSelectionMode`
- Blue hint banner: "Drag with finger to select AI region"
- Finger `UIPanGestureRecognizer` (finger-only, `allowedTouchTypes = direct`) draws a blue selection rectangle
- UIScrollView `panGestureRecognizer` disabled during selection to prevent scroll conflict
- On finger lift → rect converted to drawing coordinates → `lassoSelectionBounds` set → transform menu opens
- Pencil continues drawing/lassoing normally — no conflict (`drawingPolicy = .pencilOnly`)

**Files:** `ios/NotesApp/Canvas/CanvasView.swift`, `ios/NotesApp/Features/Notebook/NotebookView.swift`

### 2. AI crop landing on empty space (coordinate conversion bug)
**Root cause:** `sender.location(in: canvas)` returns **content coordinates** because UIScrollView sets `bounds.origin = contentOffset`. The formula was adding `contentOffset` a second time → crop rect shifted by `-contentOffset` into blank space → blank PNG sent to AI.

**Fix:** `drawingCoord = locationInCanvas / zoomScale` (no `contentOffset` term).
**File:** `ios/NotesApp/Canvas/CanvasView.swift`

### 3. "Ask in Chat" button added to transform result
After a transform, user can tap "Ask in Chat" → transform answer appears as an **ephemeral assistant bubble** in the chat (not in the input field), leaving the input empty for the user's follow-up question.

**Files:** `ios/NotesApp/Features/Notebook/TransformResultView.swift`, `ios/NotesApp/Features/Notebook/NotebookView.swift`, `ios/NotesApp/Features/Chat/ChatViewModel.swift`

### 4. "Ask in Chat" was sending the answer as the user's message
**Root cause:** `onSendToChat` set `chatVM.inputText = transformResult` → user tapped send → posted AI answer as user message.
**Fix:** Pass as `injectedAssistantMessage` to `ChatViewModel.init`. `load()` appends it as an ephemeral assistant bubble (not persisted).
**File:** `ios/NotesApp/Features/Chat/ChatViewModel.swift`

### 5. MathWebView invisible text in dark mode
**Root cause:** HTML body had no explicit color. WKWebView dark-mode auto-adapt made background dark but text inherited black → invisible. Also WKWebView `scrollView.backgroundColor` was opaque white.
**Fix:** `html,body { background: transparent }` + `color: #000000` with `@media (prefers-color-scheme: dark) { color: #ffffff }`. `scrollView.backgroundColor = .clear`.
**File:** `ios/NotesApp/AI/MathWebView.swift`

---

## Known issues / next steps

- Sync **pull** (restore after reinstall) not yet wired on iOS side. Server's `/sync/pull` endpoint exists; iOS client not implemented.
- `MathWebView` loads KaTeX + marked from jsDelivr CDN. Falls back to blank if offline (AI also needs internet, so acceptable). Future: bundle KaTeX locally.

## Server quick-start reminder

```bash
cd server
.venv/Scripts/activate   # Windows
uvicorn notes_server.server:app --reload
```
