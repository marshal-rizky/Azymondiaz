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

- **Plan C (AI integration into iOS):** Not started. Plan written at `docs/plans/2026-04-07-plan-c-ipad-ai.md`

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

## What was fixed in this session (2026-04-11)

### Zoom bugs: bgView not tracking user pinch

**Symptoms (from screen recording `ScreenRecording_04-11-2026 09-43-28_1.mov`):**
- Zooming in: ink strokes scaled up and spread beyond page bounds; the white page (bgView) stayed at the original fit-zoom size
- Page "slid around" during pinch gestures

**Root cause:**
KVO was registered on `UIScrollView.zoomScale`. PKCanvasView's internal pinch gesture does NOT update `zoomScale` via the normal KVO-observable property setter — it manages zoom internally. So KVO never fired during user pinch, bgView was never resized, and ink rendered at pinch scale while the template image stayed small.

**Fix (commit `7773e61`):**
Switched KVO target from `zoomScale` → `contentSize`. PK updates `contentSize` every frame during a pinch (as part of its internal scroll bookkeeping), so this fires reliably. bgView is now resized each frame from the new `contentSize` directly — no zoom scale calculation needed.

**File:** `ios/NotesApp/Canvas/CanvasView.swift`
- `addObserver` / `removeObserver` keyPath: `#keyPath(UIScrollView.contentSize)`
- `observeValue`: reads `newSize` from change dict, sets `bgView?.frame` immediately, debounces template re-render + `centerPage` at 150ms

**Status:** Fix committed and pushed. NEEDS TESTING on device — verify that:
1. Pinching in shows page AND ink zooming together (bgView tracks ink)
2. No page sliding during pinch (contentInset not updated mid-gesture, only in debounce)
3. Template re-renders sharply after gesture settles

---

## Next steps
1. Start Plan C: `docs/plans/2026-04-07-plan-c-ipad-ai.md`
   - Task 1: Keychain store for secrets + PC URL
   - Task 2: KeyPool (5-slot Groq key rotation)
   - Task 3: AIClient protocol + PCServerAIClient + GroqFallbackAIClient
   - Task 4: AIRouter (reachability probe, auto-switch home ↔ school)
   - ... (15 tasks total, full TDD)
2. Run server (`cd server && .venv/Scripts/activate && uvicorn notes_server.server:app --reload`) before testing AI features
