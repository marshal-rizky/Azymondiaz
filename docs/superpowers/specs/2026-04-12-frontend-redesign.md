# Frontend Redesign — Gold & Black

**Date:** 2026-04-12
**Status:** Approved
**Scope:** All iOS screens — Library, Notebook, Canvas toolbar, Chat panel, Settings

---

## 1. Design Tokens

Single source of truth: `ios/NotesApp/Theme/DesignSystem.swift`

### Colors

```swift
// Backgrounds
AppColors.bg           = #0A0A0C   // page/screen background
AppColors.surface      = #141416   // nav bars, side panels
AppColors.surface2     = #1C1C1E   // cards, input fields, folder rows
AppColors.surface3     = #242426   // pressed states, hover

// Borders
AppColors.border       = #2A2A2E   // primary dividers
AppColors.border2      = #333338   // secondary dividers, dashed outlines

// Gold accent
AppColors.gold         = #C9A84C   // primary accent
AppColors.goldDark     = #A87C28   // gradient end / pressed
AppColors.goldLight    = #E8C96A   // highlights
AppColors.goldGradient = LinearGradient(#C9A84C → #A87C28, angle: 135°)

// Text
AppColors.textPrimary  = #F0EDE6   // headings, primary labels
AppColors.textSecondary = #A0A0A8  // secondary labels
AppColors.textTertiary  = #606068  // placeholders, dates, captions

// Canvas (always light — ink must be readable)
AppColors.canvasPaper  = #FAF8F3   // warm off-white page surface
AppColors.canvasRuled  = #C8D4D8   // ruled/grid lines on canvas
```

### Typography

```swift
AppFonts.navTitle      = .system(17, weight: .bold)
AppFonts.sectionHeader = .system(11, weight: .semibold)  // uppercase + tracking
AppFonts.body          = .system(14, weight: .regular)
AppFonts.bodyBold      = .system(14, weight: .semibold)
AppFonts.caption       = .system(11, weight: .regular)
AppFonts.micro         = .system(9,  weight: .regular)
```

### Spacing & Shape

```swift
AppRadius.card   = 10   // notebook covers, folder rows, screens
AppRadius.button = 9    // primary buttons
AppRadius.chip   = 8    // pills, tags
AppRadius.thumb  = 6    // page strip thumbnails
AppSpacing.page  = 18   // horizontal screen padding
AppSpacing.grid  = 16   // gap between notebook cover tiles
AppSpacing.stack = 10   // vertical gap between list items
```

---

## 2. Library Screen (`LibraryView`)

### Layout
- `NavigationStack` with dark background (`AppColors.bg`)
- Nav bar: gear icon (left) · "My Library" title · gold `+` button (right, `goldGradient` fill, shadow)
- Search bar: below nav, `surface2` background, `border` stroke, tertiary placeholder
- Two sections: **Folders** then **Notebooks**

### Folder rows
- Each folder: `surface2` rounded card (`AppRadius.card`), `border` stroke
- Left icon: `surface3` circle with 📁 emoji
- Title in `textPrimary`, count in `textTertiary`, chevron `›` in `border2`
- Long-press context menu: Rename / Move / Delete

### Notebook grid
- `LazyVGrid`, 4 columns, `AppSpacing.grid` gap
- Each cover tile: gradient or dark cover (`AppRadius.card`), spine shadow (`::after` equivalent: left-edge overlay `rgba(0,0,0,0.25)`, 5pt wide), ruled-line decoration, title bottom-left in white
- Cover gradient options (8 presets, user-selectable in creation sheet):
  - Dark amber: `#2A1F08 → #1A1205`
  - Full gold: `#C9A84C → #A87C28`
  - Dark navy: `#1A1A2A → #0D0D1A`
  - Dark teal: `#0A1A18 → #051210`
  - Dark plum: `#1A0A1A → #0D050D`
  - Dark crimson: `#1A0808 → #0D0404`
  - Dark forest: `#0A1A0A → #051205`
  - Dark slate: `#0F0F18 → #080810`
- Date label below cover in `textTertiary`
- "New" tile: dashed `border2` outline, gold `+` icon, inline at end of grid

### New notebook/folder sheet
- `presentationDetents([.medium])`
- `TextField` for title
- Horizontal scroll row of 8 color swatches for cover gradient
- "New Folder" toggle to create a folder instead
- "Create" button: `goldGradient` fill, black text

### Nested folders
- Tapping a folder pushes a new screen (same layout, filtered content)
- Nav back button shows parent name
- Breadcrumb bar below nav: `surface · › · FolderName · › · ActiveFolder` — tap any segment to jump
- Unlimited nesting depth via `parent_folder_id UUID?` on `Folder` model

---

## 3. Data Model Changes

### New `Folder` table

```sql
Folder
  id:               UUID  PRIMARY KEY
  parent_folder_id: UUID? FK → Folder.id   -- null = root level
  title:            TEXT
  created_at:       TIMESTAMP
  updated_at:       TIMESTAMP
```

### Updated `Notebook` table

```sql
-- Add column:
folder_id: UUID? FK → Folder.id   -- null = loose in Library root
```

Cascade: deleting a folder moves its notebooks to root (no orphan delete). Deleting a folder that contains subfolders recursively deletes subfolders.

---

## 4. Notebook Screen (`NotebookView`)

### Row 1 — Navigation bar
- `surface` background, `border` bottom divider
- Back arrow + parent folder name in `gold`
- Notebook title centered in `textPrimary`
- "Export PDF" as text button right-aligned (`gold` color, `surface3` background pill)

### Row 2 — Action bar
- `surface2` background, `border` bottom divider, height 40pt
- **Group 1:** Undo `↩` / Redo `↪`
- Divider
- **Group 2 — Tools:** Pen 🖊 / Pencil ✏️ / Eraser ◻ / Lasso ⊙
  - Active tool: `goldGradient` fill, black icon
  - Inactive: `textSecondary` icon, transparent bg
  - Tapping sets the corresponding `PKTool` on `PKCanvasView` programmatically — no PKToolPicker shown
- Divider
- **Group 3 — Colors:** 4 fixed dot swatches (cream `#F0EDE6`, gold `#C9A84C`, indigo `#5C6BC0`, teal `#26A69A`)
  - Fixed presets — no custom color picker in this version
  - Selected: gold ring overlay (`RoundedRectangle` stroke)
  - Tapping sets `PKInkingTool(type: activePenType, color: UIColor(selectedColor))`
- Divider
- **Group 4 — AI + Chat:** Sparkles ✦ / Chat 💬
  - Active (panel open / mode active): `gold` tint bg + `gold` icon
- Spacer
- Routing badge pill (shown only when not using PC server): `gold` text + `rgba(gold, 0.1)` bg + `rgba(gold, 0.2)` border
- Divider
- Add page `＋▭` / Delete page 🗑

### AI selection mode
- Activated by tapping ✦ sparkles button
- Full-width `gold` banner replaces the routing area: "Drag with finger to select a region ✦ · Cancel ✕"
- Finger pan draws gold-bordered selection rect with corner handles
- On lift → transform menu popover

### Page strip
- Width 88pt, `surface` background, `border` right divider
- Thumbnails: `surface2` background, `AppRadius.thumb` corners, `border` shadow
- Selected: `gold` 2pt ring + soft gold glow shadow
- Page number: `textTertiary` caption bottom-right of thumb
- `+` add tile at bottom: dashed `border2` outline

### Canvas
- `PKCanvasView` fills remaining space
- Background: `canvasPaper` (`#FAF8F3`) — always light regardless of app theme
- Template lines rendered in `canvasRuled` (`#C8D4D8`)
- Page rendered with subtle `surface` drop shadow inset 16pt from canvas edges

---

## 5. Chat Panel (`ChatPanelView`)

### Layout
Bottom sheet that slides up from the bottom edge of the NotebookView body (below the action bar). Implemented as a `VStack` overlay inside the notebook body `ZStack` — **not** a SwiftUI `.sheet` (which would cover the full screen including the toolbar).

- **Collapsed:** `offset(y: panelHeight)` — off-screen
- **Half-height:** default on open — `panelHeight = 320pt`, canvas visible above
- **Full-height:** user drags handle to top — `panelHeight = bodyHeight`, canvas hidden
- Animated with `.animation(.spring(response: 0.35, dampingFraction: 0.8))`
- Drag handle: 36×3pt pill, `border2` color, centered at top of sheet; `DragGesture` adjusts offset

### Header
- `surface` background
- "Chat" title (`textPrimary`, bold) + ✕ close button (24pt `surface3` circle)
- Scope toggle: `bg` background pill selector
  - Active tab: `goldGradient` fill, black text
  - Inactive: `textTertiary`

### Messages
- Welcome chip on first open: `surface2` rounded pill, `textTertiary`, centered
- **User bubbles:** `goldGradient` fill, black text, 14pt radius, bottom-right 4pt
- **Bot bubbles:** `surface2` fill, `textPrimary`, `border` stroke, 14pt radius, bottom-left 4pt
- Math/LaTeX rendered via `MathWebView` (existing) with dark-mode HTML: `background: transparent; color: #F0EDE6`
- Typing indicator: 3-dot animation in bot-bubble style

### Input bar
- `surface` background, `border` top divider
- Mic button: `surface2` + `border`, gold mic icon
- Text field: `surface2` + `border`, `textTertiary` placeholder
- Send button: `goldGradient` circle, black arrow, gold glow shadow — disabled state: `surface3`, no shadow

---

## 6. Transform Result View (`TransformResultView`)

- Sheet background: `surface`
- Result rendered in `MathWebView` (dark mode styles already fixed)
- Buttons row: "Insert below" / "Replace" / "Ask in Chat" / "Dismiss"
  - Primary action ("Ask in Chat"): `goldGradient` fill
  - Secondary: `surface2` + `border`

---

## 7. Settings View (`SettingsView`)

- `Form` replaced with custom `List`-style sections on `bg` background
- Section headers: `textTertiary` uppercase small caps
- Rows: `surface2` background, `border` separators
- Pickers: gold tint on selected value
- "Save AI configuration" button: `goldGradient` fill, full width, black text
- Sync status text: `textSecondary`

---

## 8. Implementation Approach

**Design tokens first.** All changes flow from `DesignSystem.swift`.

### New files
- `ios/NotesApp/Theme/DesignSystem.swift` — all color/font/spacing/radius tokens
- `ios/NotesApp/Data/Folder.swift` — `Folder` model (GRDB `Record`)
- `ios/NotesApp/Data/FolderRepository.swift` — CRUD + nested fetch
- `ios/NotesApp/Features/Library/FolderView.swift` — drilled-in folder screen (reuses LibraryView layout)

### Modified files
- `ios/NotesApp/Theme/Theme.swift` — wire `ThemePreference` to always use dark (force dark mode)
- `ios/NotesApp/Data/Migrations.swift` — add `folders` table, add `folder_id` to `notebooks`
- `ios/NotesApp/Data/Notebook.swift` — add `folderID: UUID?`
- `ios/NotesApp/Features/Library/LibraryView.swift` — full redesign + folder rows
- `ios/NotesApp/Features/Library/LibraryViewModel.swift` — folder-aware fetch
- `ios/NotesApp/Features/Notebook/NotebookView.swift` — two-row toolbar, dark chrome, AI banner
- `ios/NotesApp/Features/Chat/ChatPanelView.swift` — bottom sheet layout, gold bubbles
- `ios/NotesApp/Features/Chat/ChatViewModel.swift` — no logic changes
- `ios/NotesApp/Features/Notebook/TransformResultView.swift` — dark sheet styling
- `ios/NotesApp/Features/Notebook/LassoMenuView.swift` — dark popover styling
- `ios/NotesApp/Features/Settings/SettingsView.swift` — dark form styling
- `ios/NotesApp/AI/MathWebView.swift` — dark mode HTML already fixed; verify gold text color
- `ios/NotesApp/Canvas/CanvasView.swift` — remove PKToolPicker, tool state driven from action bar
- `ios/NotesApp/App/NotesAppApp.swift` — apply `.preferredColorScheme(.dark)` on root `WindowGroup` content view; canvas `PKCanvasView` background is set explicitly to `UIColor(AppColors.canvasPaper)` so it stays light regardless

### PKToolPicker removal
`CanvasView` currently calls `toolPicker.setVisible(true, ...)`. Remove this. Instead:
- Accept `@Binding var activeTool: PKTool` from parent
- In `updateUIView`, set `canvasView.tool = activeTool`
- `NotebookView` action bar manages the active tool state

---

## 9. Out of Scope

- iPad landscape vs portrait layout differences
- Drag-and-drop reordering of notebooks/folders
- Custom cover image upload
- Folder color customization (beyond the 8 notebook cover presets)
- Animations beyond standard SwiftUI `.transition` and `.animation`

---

## 10. Known Risks

- `PKToolPicker` removal is irreversible once shipped — verify eraser and lasso parity before merging
- Bottom sheet height management needs to avoid covering the action bar; anchor sheet to the body HStack, not the full screen
- Dark `MathWebView` background: already fixed, but confirm gold text color renders correctly with KaTeX
