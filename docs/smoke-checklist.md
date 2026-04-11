# Manual smoke test checklist (Plan B)

Run after every install. Expected time: ~5 minutes.

## Library
- [ ] App launches to Library without crash
- [ ] Tap "+" → enter a title → new notebook appears
- [ ] Long-press notebook → Delete → notebook disappears
- [ ] App relaunch preserves notebooks

## Notebook
- [ ] Tap a notebook → opens with one blank page
- [ ] Toolbar "Add page" → Line → new line-ruled page appended, selected in strip
- [ ] Same for Grid and Blank
- [ ] Page strip thumbnails update after drawing (within ~1 second of lifting pen)
- [ ] Tap a different page in strip → canvas loads its drawing
- [ ] Delete page → strip re-indexes, never goes below 1 page
- [ ] Force-quit app mid-drawing → relaunch → last strokes present (debounce saved them)

## Canvas (Apple Pencil)
- [ ] Pen input feels latency-free (no visible lag)
- [ ] Palm rejection: resting palm while writing does not draw stray lines
- [ ] `allowsFingerDrawing` is false: finger input does NOT draw (confirms pencil-only policy)
- [ ] Eraser works via tool picker
- [ ] Undo / redo via tool picker works

## Templates
- [ ] Line template: horizontal ruled lines visible in light AND dark mode
- [ ] Grid template: grid visible in light AND dark mode
- [ ] Blank template: no guides

## Dark mode
- [ ] Settings → Theme → Dark → Library and canvas backgrounds go dark
- [ ] Ink color drawn in dark mode is preserved when switching back to light
- [ ] Templates re-render with dark guides in dark mode (lower contrast)

## PDF export
- [ ] Notebook toolbar → Export PDF → share sheet appears
- [ ] Save to Files → open the PDF → all pages present, in order, with ink visible
- [ ] PDF background is LIGHT even when the app is in dark mode

## Settings
- [ ] Default template picker persists across launches
- [ ] Theme picker persists across launches

---

If any item fails, open an issue and do NOT ship. Fixing Tier 1 tests to catch the regression is preferred over a re-test loop.

---

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
