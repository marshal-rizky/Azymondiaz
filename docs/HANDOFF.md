# Project Handoff

## What this is
iPad AI notes app — PencilKit canvas + Groq AI backend. Solo dev, Windows PC + iPad.

## Status

| Plan | State | Notes |
|------|-------|-------|
| A — Python server | COMPLETE | FastAPI, 29 tests, live on Groq |
| B — iOS app | COMPLETE | CI green, sideloaded via KSign |
| C — AI integration | COMPLETE | All smoke tests passed 2026-04-12 |
| D — Frontend redesign | **IN PROGRESS** | Gold & Black theme, folders — plan written, not started |

## Next up: Plan D (Frontend Redesign)
- **Spec:** `docs/superpowers/specs/2026-04-12-frontend-redesign.md`
- **Plan:** `docs/superpowers/plans/2026-04-12-frontend-redesign.md` — 9 tasks, inline execution
- **Design tokens:** single source of truth → `ios/NotesApp/Theme/DesignSystem.swift` (to create, Task 1)
- **Theme:** Gold `#C9A84C` accent, `#0A0A0C` bg, `#FAF8F3` canvas paper (always light)
- **New feature:** Folder model with unlimited nesting (`parent_folder_id`), Tasks 2–5
- **Key removals:** PKToolPicker gone — tools set programmatically via `@Binding var activeTool: PKTool`

## Tech
- Server: Python 3.11, FastAPI, Groq SDK
- iOS: Swift 5.10, iOS 17+, SwiftUI, PencilKit, GRDB.swift 6.x
- Build: XcodeGen + GitHub Actions → unsigned IPA → KSign sideload
- API keys: `server/config.yaml` (gitignored)

## Key gotchas (hard-won)
- `AppDatabase.makeInMemory()` must use `DatabaseQueue` not `DatabasePool` (WAL incompatible with in-memory)
- PKCanvasView IS the root UIScrollView — never wrap it in another UIScrollView
- AI region crop: `drawingCoord = locationInCanvas / zoomScale` (no contentOffset term — already in content coords)
- Finger AI-selection uses a dedicated `UIPanGestureRecognizer` with `allowedTouchTypes = direct`; pencil lasso has no public API
- `JSONEncoder().encode(content)` not `JSONSerialization` — bare strings throw uncatchable ObjC exceptions

## Server quick-start
```bash
cd server && .venv/Scripts/activate && uvicorn notes_server.server:app --reload
```

## Known issues
- Sync **pull** not wired on iOS (server endpoint exists, iOS client not implemented)
- `MathWebView` loads KaTeX from CDN — blank if offline (acceptable; AI also needs internet)
