# Project Handoff

## What this is
iPad AI notes app — PencilKit canvas + Groq AI backend. Solo dev, Windows PC + iPad.

## Status

| Plan | State | Notes |
|------|-------|-------|
| A — Python server | COMPLETE | FastAPI, 29 tests, live on Groq |
| B — iOS app | COMPLETE | CI green, sideloaded via KSign |
| C — AI integration | COMPLETE | All smoke tests passed 2026-04-12 |
| D — Frontend redesign | COMPLETE | Gold & Black theme, folders, bottom sheet chat, action bar |
| E — Frontend Redesign | **COMPLETE** | GoodNotes-style floating tool pill, NavigationSplitView, undo/redo wired |

## Next up: TBD

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

## Plan E — Completed 2026-04-13
- **DesignSystem.swift** — added `AppColors.navBar = Color(hex: "#1B2A4A")` dark navy chrome color
- **CanvasView.swift** — exposed `@Binding var undoManager: UndoManager?`, wired in `makeUIView` to `canvas.undoManager`
- **NotebookView.swift** — complete rewrite:
  - `enum ActiveTool: Equatable { case pen, pencil, marker, eraser, lasso }` replaces `activePenType`
  - `currentPKTool` computed var now maps ActiveTool → PKTool (fixed lasso, eraser, marker opacity)
  - Custom dark navy nav bar with tab chip, Export PDF pill
  - Second toolbar row with pages toggle, search, functional undo/redo via canvasUndoManager
  - Floating glassmorphic tool pill (pen/pencil/marker/eraser/lasso + size + color swatches)
  - Floating undo/redo pill (top-left), AI+chat pill (top-right vertical)
  - Slide-in pages panel (180pt overlay)
  - AI selection banner overlay
  - `.navigationBarHidden(true)` + custom dismiss via `@Environment(\.dismiss)`
- **LibraryView.swift** — complete rewrite:
  - Replaced `NavigationStack` with `NavigationSplitView` (sidebar + detail)
  - Sidebar (~220pt): app title, Documents/Folders/Settings with gold selected state
  - Detail: large title, "+ New" gold Capsule, search, filter bar
  - Folder icon: `Image(systemName: "folder.fill")` in gold
- **Bug fix** — `CanvasView.swift:95`: fixed `self.parent.undoManager` → `self.undoManager` inside async closure (compile error resolved)

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
