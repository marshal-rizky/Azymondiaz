# Project Handoff

## What this is
iPad AI notes app — PencilKit canvas + Groq AI backend. Solo dev, Windows PC + iPad.

## Status

| Plan | State | Notes |
|------|-------|-------|
| A — Python server | COMPLETE | FastAPI, 29 tests, live on Groq |
| B — iOS app | COMPLETE | CI green, sideloaded via KSign |
| C — AI integration | COMPLETE | All smoke tests passed 2026-04-12 |
| D — Frontend redesign | **COMPLETE** | Gold & Black theme, folders, bottom sheet chat, action bar |

## Next up: Plan E (TBD)

## Plan D — Completed 2026-04-13
- **DesignSystem.swift** — single source of truth for all gold/black tokens
- **Folders** — `Folder` model, GRDB v2 migration, `FolderRepository` (TDD), unlimited nesting
- **LibraryView** — full redesign: folder rows, 8 cover gradient presets, dark creation sheet
- **FolderView** — nested drill-in with breadcrumb bar
- **NotebookView** — two-row action bar, PKToolPicker removed, tool state via `@Binding var activeTool: PKTool`
- **ChatPanelView** — bottom sheet with drag handle, gold bubbles, scope toggle
- **Secondary views** — TransformResult, LassoMenu, Settings, MathWebView all dark-themed
- **App** — `.preferredColorScheme(.dark)` forced at root
- **CI fix** — removed invalid `!==` identity check on `any PKTool` in `CanvasView.updateUIView`

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
