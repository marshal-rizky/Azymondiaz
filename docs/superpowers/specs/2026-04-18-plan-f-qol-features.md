# Plan F — QOL Features Design Spec

**Date:** 2026-04-18
**Status:** Approved
**Scope:** Notebook tabs, split-screen, PDF/image import, Cornell template, per-page theme, scratch-out erase

---

## 1. Goal

Add quality-of-life features that bring the app closer to a full GoodNotes replacement: multi-notebook tabs, side-by-side split-screen, media import, richer templates, per-page dark/light theming, and a natural pencil erase gesture.

No AI changes. No sync changes. No data model changes beyond what is listed here.

---

## 2. Feature Summary

| Feature | Description |
|---|---|
| Notebook tabs | Chrome-style tab bar above the nav bar; open multiple notebooks simultaneously |
| Split-screen | In-app two-pane view with draggable gold divider; each pane has its own tab bar |
| PDF → new notebook | Import PDF file; each page becomes a note page with PDF as background |
| PDF → existing notebook | Append PDF pages to the currently open notebook |
| Insert image | Drop a photo/image onto a canvas page as a floating, resizable object |
| Cornell template | New page template with title / cue-column / notes / summary zones |
| Per-page theme | Each page independently set to light or dark, regardless of device appearance |
| Scratch-out erase | Pencil scribble back-and-forth over ink → auto-erases crossed strokes |

---

## 3. Architecture

### 3.1 OpenSessionsManager

New `@Observable` class owned by `AppContainer`.

```swift
struct NotebookSession: Identifiable {
    let id: UUID
    let notebook: Notebook
    var activePageIndex: Int
}

@Observable
final class OpenSessionsManager {
    var sessions: [NotebookSession] = []
    var activeSessionID: UUID?

    func open(_ notebook: Notebook)
    func close(sessionID: UUID)
    func session(for notebook: Notebook) -> NotebookSession?
}
```

`AppContainer` adds `let sessions = OpenSessionsManager()` and injects it into the SwiftUI environment.

### 3.2 SplitState

```swift
@Observable
final class SplitState {
    var isSplit: Bool = false
    var leftSessionID: UUID?
    var rightSessionID: UUID?
    var splitRatio: CGFloat = 0.5   // clamped 0.3–0.7
    var focusedPane: SplitPane = .left

    enum SplitPane { case left, right }
}
```

Lives in `LibraryView` environment so it survives navigation.

---

## 4. Data Model Changes (Migration v3)

### 4.1 Page — new column

```sql
ALTER TABLE pages ADD COLUMN theme TEXT NOT NULL DEFAULT 'light';
-- 'light' | 'dark'
```

### 4.2 page_media — new table

```sql
CREATE TABLE page_media (
    id TEXT PRIMARY KEY,
    page_id TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
    sort_index INTEGER NOT NULL DEFAULT 0,
    image_blob BLOB NOT NULL,
    x REAL NOT NULL DEFAULT 0.3,       -- fraction of page width
    y REAL NOT NULL DEFAULT 0.3,       -- fraction of page height
    width REAL NOT NULL DEFAULT 0.4,   -- fraction of page width
    height REAL NOT NULL DEFAULT 0.4,  -- computed to preserve aspect
    created_at REAL NOT NULL
);
CREATE INDEX idx_page_media_page ON page_media(page_id);
```

### 4.3 PageTemplateKind

Add `.cornell` case to `PageTemplateKind` enum (no DB change — stored as `"cornell"` string).

---

## 5. Notebook Tabs

### Component: `NotebookTabBar.swift`

Pure SwiftUI view. Props: `sessions: [NotebookSession]`, `activeSessionID: Binding<UUID?>`, `onClose: (UUID) -> Void`, `onAdd: () -> Void`.

- Chrome-style horizontal tab strip, sits above the nav bar row
- Active tab: taller (32pt), `AppColors.navBar` background, gold text, gold bottom highlight
- Inactive tabs: 28pt height, `#0D1117` background, `textSecondary` text
- Tab width: 140–200pt min/max, title truncates with ellipsis
- Overflow: horizontal `ScrollView` (no tab compression)
- `＋` button: opens a sheet to pick a notebook from Library to add as a new tab
- `×` on each tab closes it; closing the last tab navigates back to Library
- Each split pane has its own `NotebookTabBar` tracking its own `activeSessionID`

---

## 6. Split-Screen

### Component: `SplitNotebookView.swift`

Wraps two `NotebookView` instances. Replaces the direct `NotebookView` navigation destination.

**Layout:**
- Landscape (width ≥ 768pt): `HStack` — left pane + 4pt gold divider + right pane
- Portrait (width < 768pt): `VStack` — top pane + 4pt gold divider + bottom pane
- Pane sizes controlled by `SplitState.splitRatio`

**Divider:**
- 4pt wide/tall, `AppColors.gold` color
- `DragGesture` updates `splitRatio` live
- White 3×24pt grip indicator centered on divider

**Pane focus:**
- Tapping anywhere inside a pane sets `SplitState.focusedPane`
- Focused pane receives tool pill input; unfocused pane's canvas is not first responder
- Subtle dim overlay (opacity 0.04 black) on unfocused pane

**Controls:**
- Tab bar far right: **⊞ SPLIT** button (only in single-pane mode) — opens sheet to pick second notebook
- Right pane tab bar: **✕ UNSPLIT** button — sets `isSplit = false`, right pane dismissed

---

## 7. PDF / Image Import

### 7.1 Entry Points

- Library `+ New` menu: "PDF → New Notebook"
- `NotebookView` toolbar row 2: import tray icon → action sheet with all three paths

### 7.2 ImportCoordinator.swift

`UIViewControllerRepresentable` that manages document/photo picker presentation. Three methods:

```swift
func importPDFAsNewNotebook()
func importPDFIntoCurrentNotebook(notebook: Notebook)
func insertImageOnPage(page: Page)
```

### 7.3 PDF Rendering

Uses `PDFKit` (`PDFDocument`, `PDFPage`):
- Each `PDFPage` rendered to PNG at 1024×1366pt via `UIGraphicsImageRenderer`
- PNG stored as `PageMediaItem.image_blob` with `x=0, y=0, width=1, height=1` (full-page)
- Page template set to `.blank`, theme `"light"` by default

### 7.4 Floating Image Objects

`PageMediaItem` rendered as a `UIImageView` overlay in `CanvasView`, positioned between the template background and the `PKCanvasView` ink layer.

Gestures on the image view:
- `UIPanGestureRecognizer` — moves the image (updates `x`, `y`)
- `UIPinchGestureRecognizer` — resizes (updates `width`, `height` preserving aspect ratio)
- Double-tap: shows a context menu with "Delete image"

Position/size written back to `PageMediaItem` via `PageMediaRepository` on gesture end.

**Z-order:** template background → image objects (sorted by `sort_index`) → `PKCanvasView`

---

## 8. Cornell Template

### Layout (at 1024×1366pt)

```
┌─────────────────────────────────────┐  ← top: 0
│  Title bar                          │  height: 64pt, gold bottom border
├──────────────┬──────────────────────┤  ← y: 64
│  Cue column  │  Notes area          │  
│  220pt wide  │  remainder           │  height: 1182pt
│              │                      │
│  (gold right │                      │
│   border)    │                      │
├──────────────┴──────────────────────┤  ← y: 1246
│  Summary area                       │  height: 120pt, gold top border
└─────────────────────────────────────┘
```

Rendered in `PageTemplate.render(kind:size:isDark:)` via `CGContext` — gold lines at 15% opacity for light theme, 25% for dark. No new dependencies.

---

## 9. Per-Page Theme

`Page.theme: String` (`"light"` | `"dark"`).

- `NotebookViewModel` passes `page.theme` to `CanvasView` and `PageTemplate.render`
- Dark theme canvas background: `#1C1C1E`; ruled/grid lines: `#3A3A3C`
- `NotebookView` toolbar row 2: sun/moon icon button — taps toggle `page.theme`, saves immediately via `PageRepository`
- Completely independent of device `colorScheme` — a dark page in a light-mode app is valid
- `CanvasView` sets `PKCanvasView.backgroundColor` accordingly

---

## 10. Scratch-Out Erase

Hook: `PKCanvasViewDelegate.canvasViewDrawingDidChange` in `CanvasView.Coordinator`.

After each new pencil stroke is committed:

```swift
let newStroke = latestStroke(in: canvas.drawing)
if ScratchOutDetector.isScribble(stroke: newStroke) {
    let rect = newStroke.renderBounds.insetBy(dx: -8, dy: -8)
    var drawing = canvas.drawing
    drawing.strokes = drawing.strokes.filter {
        !$0.renderBounds.intersects(rect)
    }
    canvas.drawing = drawing        // also removes the scratch stroke itself
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}
```

**`ScratchOutDetector.isScribble(stroke:) -> Bool`** — pure struct, unit-testable:

Criteria (all must pass):
- ≥ 3 X-axis direction reversals in the stroke's control points
- Vertical extent of stroke path < 80pt
- Total horizontal travel ≥ 80pt
- Stroke duration < 1.2 seconds (via `PKStrokePoint.timeOffset`)

Pencil-only: existing `PKCanvasView.drawingPolicy = .pencilOnly` means only pencil strokes reach `canvasViewDrawingDidChange`. Finger AI-selection is unaffected.

---

## 11. Files Changed

| Action | File |
|---|---|
| New | `ios/NotesApp/App/OpenSessionsManager.swift` |
| New | `ios/NotesApp/Features/Notebook/NotebookTabBar.swift` |
| New | `ios/NotesApp/Features/Notebook/SplitNotebookView.swift` |
| New | `ios/NotesApp/Canvas/ScratchOutDetector.swift` |
| New | `ios/NotesApp/Features/Import/ImportCoordinator.swift` |
| New | `ios/NotesApp/Data/PageMediaRepository.swift` |
| Modify | `ios/NotesApp/App/AppContainer.swift` |
| Modify | `ios/NotesApp/Data/Migrations.swift` (v3) |
| Modify | `ios/NotesApp/Data/Page.swift` (theme column) |
| Modify | `ios/NotesApp/Canvas/PageTemplate.swift` (cornell, dark per-page) |
| Modify | `ios/NotesApp/Canvas/CanvasView.swift` (image overlay, scratch-out hook) |
| Modify | `ios/NotesApp/Features/Notebook/NotebookView.swift` (theme toggle, import button) |
| Modify | `ios/NotesApp/Features/Library/LibraryView.swift` (PDF→new notebook entry) |
| Modify | `ios/NotesApp/Features/Notebook/NotebookViewModel.swift` (theme save) |

---

## 12. Out of Scope

- Drag-to-reorder images on canvas
- Custom Cornell column widths
- Image annotations (drawing directly on an imported image without it covering the canvas)
- PDF export of pages with imported images (deferred — complex layout)
- Multi-page PDF viewer within a page
- Apple Pencil double-tap to activate scratch-out (hardware-specific, deferred)
