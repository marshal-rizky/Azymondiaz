# iPad AI Note-Taking App — Design Spec

**Date:** 2026-04-07
**Author:** User (brainstormed with Claude)
**Status:** Approved design, pending implementation plan

---

## 1. Goals

A personal iPad note-taking app with Apple Pencil scribble support and tightly-integrated AI features. Sideloaded via KSign (no App Store). Single user, single iPad, single companion PC.

### Core requirements
- GoodNotes-level canvas quality (PencilKit-based)
- Notebook → Page organization with line/grid templates
- Full dark mode
- PDF export
- AI "Lasso → Transform" for cleaning up, converting, solving, and explaining scribbles
- AI side-panel chat scoped to the current page or notebook
- Voice input for chat via Whisper
- Indonesian + English support end-to-end (including code-switching)
- Works offline from PC (at school) with no feature loss beyond prompt tweaking
- Local-first storage with one-way sync to the user's PC

### Non-goals
- App Store distribution
- Multi-user, collaboration, or real-time sync
- iCloud sync
- Running AI models on-device
- Running heavy AI models on the user's PC (decided: cloud-only inference via Groq)
- Automated UI testing on iPad

---

## 2. Architecture

Three loosely-coupled subsystems:

```
┌─────────────────────┐          ┌──────────────────────┐
│   iPad App (Swift)  │          │  PC Server (Python)  │
│                     │          │                      │
│  • PencilKit canvas │          │  • Prompt proxy      │
│  • Notebooks/pages  │◀────────▶│  • Key pool manager  │
│  • Local SQLite     │  (home)  │  • Sync storage      │
│  • Groq client      │          │  • Mathpix proxy     │
│  • Key pool (mini)  │          │                      │
└─────────────────────┘          └──────────────────────┘
         │                                  │
         ▼                                  ▼
    ┌──────────────────────────────────────────┐
    │             Groq Cloud API                │
    │    (Llama 70B, Vision, Whisper, etc.)     │
    └──────────────────────────────────────────┘
```

### Unit boundaries

1. **Canvas / Notebook Core** (iPad, no AI dependency) — usable as a plain note app on day one.
2. **AI Gateway** (PC server, no iPad dependency) — testable via curl / pytest.
3. **Fallback Client** (inside iPad, Groq-only) — smaller mirror of the gateway for school/offline-from-PC mode.

Each unit can be built, tested, and debugged independently.

### Runtime modes

| Mode | PC reachable? | Internet? | AI path |
|---|---|---|---|
| Home (normal) | Yes | Yes | iPad → PC server → Groq |
| School | No | Yes | iPad → Groq directly |
| Fully offline | No | No | AI disabled; canvas + notes still work |

At school the user gets the same cloud models as at home. The only things lost when the PC is off are: prompt hot-reloading, centralized key-pool dashboarding, and sync.

---

## 3. iPad App

### Canvas
- **`PKCanvasView`** (PencilKit) for inking. Inherits pressure, tilt, palm rejection, and low-latency pen handling.
- **`PKToolPicker`** for the tool bar (pen, eraser, lasso).
- **Custom overlay layer** drawn on top of the canvas for: page background (lines/grid), AI suggestion popovers, lasso action menu, selection highlights.
- Ink is serialized as **`PKDrawing`** (Apple's native format) and stored as a blob per page.

### Data model (SQLite, via GRDB or SQLite.swift)

```
Notebook
  id: UUID
  title: TEXT
  cover_color: TEXT
  created_at: TIMESTAMP
  updated_at: TIMESTAMP

Page
  id: UUID
  notebook_id: UUID (FK → Notebook.id)
  index: INTEGER  -- order within notebook
  template: TEXT  -- 'line' | 'grid' | 'blank'
  drawing_blob: BLOB  -- PKDrawing bytes
  thumbnail_blob: BLOB  -- small PNG for the page strip
  created_at: TIMESTAMP
  updated_at: TIMESTAMP

AIMessage
  id: UUID
  page_id: UUID (FK → Page.id)
  role: TEXT  -- 'user' | 'assistant'
  text: TEXT
  created_at: TIMESTAMP

SyncState
  id: INTEGER PRIMARY KEY  -- always 1, single row
  last_sync_at: TIMESTAMP
  pc_server_url: TEXT
```

Single SQLite file at `~/Documents/notes.sqlite` inside the app sandbox.

### Screens

1. **Library** — Grid of notebook covers (shelf metaphor).
2. **Notebook view** — Current page full-screen, page-strip thumbnails on the side, tool bar on top (pen / eraser / lasso / undo / redo / AI button / chat toggle).
3. **Page** — Canvas with the selected template rendered as the background of the overlay layer.
4. **Side panel (chat)** — Slides from the right, per-page chat history, dismissible by swipe.
5. **Settings** — PC server URL, API keys, theme (light / dark / auto), default page template, voice language, auto-sync interval.

### Dark mode
- Native iOS dark mode. Canvas background inverts; ink retains the color the user drew with.

### Offline behavior
- Everything non-AI works fully offline (canvas, notebooks, PDF export, reading old chat history).
- AI buttons show a disabled/offline state when no network.

---

## 4. PC Companion Server

A small **Python / FastAPI** service. Single-user, runs on user's PC over LAN. Target ~200 lines of Python.

### Endpoints

```
POST /ai/transform
  body: { action, image_base64?, text?, context? }
  returns: { result_type, text?, svg?, markdown?, model_used }

POST /ai/chat
  body: { page_id, message, history[], scope: 'page'|'notebook' }
  returns: { reply, tokens_used, model_used }

POST /ai/transcribe
  body: { audio_base64, language? }
  returns: { text, language_detected }

POST /sync/push
  body: { notebook_snapshot, since_timestamp }
  returns: { accepted_at }

POST /sync/pull
  body: { notebook_id? }
  returns: { full_snapshot }

GET /health
  returns: { status, key_pool_summary }
```

### Key pool

```python
class KeyPool:
    groq_keys: list[KeyState]  # 5 Groq keys
    # Each KeyState: { key, status: ok|cooling_down|dead, last_error, cooldown_until }

    def pick(task_type) -> key
    def mark_rate_limited(key, retry_after)
    def mark_error(key)  # 3 failures in a row -> dead
    def summary() -> dict  # for /health
```

### Routing (cloud-only, quality-first)

| Task | Primary model | Notes |
|---|---|---|
| Vision transform (ink → interpretation) | Llama 3.2 90B Vision (Groq) | Fallback: 11B Vision |
| Text chat / reasoning | Llama 3.3 70B (Groq) | |
| Voice transcription | Whisper Large v3 Turbo (Groq) | |
| Math OCR (dedicated) | Mathpix API (optional, free tier) | Only when user picks "Math mode" in lasso menu |

**No silent downgrades.** If the whole primary chain fails for a task, return an error with `"reason": "all keys exhausted"` rather than invisibly falling back to a weaker model. The user should always know what answered.

### Config (`config.yaml`)

```yaml
groq:
  keys:
    - sk-...
    - sk-...
    # (5 total)
  cooldown_seconds: 60

mathpix:
  app_id: ...
  app_key: ...

sync:
  storage_dir: ~/Notes/

voice:
  default_language: auto   # or 'id', 'en', 'id,en'

ai:
  response_language: match_input
```

### Prompts
All prompts live as plain text files under `server/prompts/`, e.g. `transform_cleanup.txt`, `transform_explain_math.txt`. Hot-reloaded on every request so prompt tuning needs zero restart.

A **snapshot of the current prompts is also bundled into the iPad IPA at build time** (copied from `server/prompts/` into the Xcode resources by a prebuild script). The iPad uses this snapshot only in school / PC-unreachable mode. Consequence: prompt changes made on the PC after an IPA build don't reach the iPad's fallback path until the next rebuild. This is acceptable — the user only needs "good enough" prompts when away from home, and major prompt improvements trigger a rebuild anyway.

### Logging
Every AI request logged as JSON Lines to `logs/requests.jsonl`:
```
{timestamp, action, model_used, key_index, latency_ms, tokens, image_path, prompt, response}
```
Images are saved as separate files and referenced by path. Enables "why did it answer badly?" postmortems.

---

## 5. AI Interactions

### A) Lasso → Transform

1. User circles ink with PencilKit's built-in lasso tool.
2. A small action menu appears near the selection:
   - Clean up handwriting
   - Convert to typed text
   - Math mode
   - Physics mode
   - Chemistry mode
   - Explain this
   - Turn into list
3. iPad rasterizes the selected ink region to a transparent-background PNG and base64-encodes it.
4. `POST /ai/transform` with `action` + `image_base64`.
5. Server picks the right model for the action and returns one of: plain text, markdown, or SVG.
6. iPad shows the result in a popover. User explicitly chooses: **insert below**, **replace selection**, or **dismiss**.

**Hard rule: AI never modifies user ink without explicit approval.**

### Subject modes
- **Math mode** — routes through Mathpix (if configured) for OCR, then Llama 70B for the solution/explanation. Falls back to Vision model if Mathpix is disabled.
- **Physics mode** — uses vision model with a physics-aware system prompt.
- **Chemistry mode** — uses vision model with a chemistry-aware system prompt. (Known limitation: structural formulas are unreliable; user should verify.)

### Expected quality (honest expectations)
- Math (clean handwriting): strong
- Math (messy): good with Mathpix, okay without
- Physics equations: strong
- Physics diagrams: mixed (60-75% reliable)
- Chemistry text/equations: strong
- Chemistry structures: unreliable, use with skepticism

### B) Side panel chat

1. Tap chat icon → panel slides in from the right.
2. Chat is scoped to the **current page** by default. A toggle at the top switches to **whole notebook** scope.
3. Asking a question automatically attaches the scoped context (the current page rasterized as an image, or a multi-page compilation for notebook scope).
4. Chat history is persisted per-page in `AIMessage`. Reopening a page restores the prior conversation.
5. Multilingual: speak/type in Indonesian, English, or mixed — models respond in the same language (`response_language: match_input`).

### C) Voice input

- Mic button in the chat input field.
- **Hold-to-talk** gesture (walkie-talkie style) by default. Tap-to-toggle available as a setting.
- Live waveform while recording.
- On release: audio sent to `/ai/transcribe` (or directly to Groq Whisper in school mode) → transcript populates the chat input → **user can edit before sending**.
- Optional setting: "auto-send after transcription."
- Language: auto-detect by default; can be locked to `id`, `en`, or `id,en` (code-switching hint).

### Error states
- PC unreachable → banner: "Using Groq fallback"
- All keys rate-limited → "AI temporarily unavailable, retry in N seconds"
- No internet → AI buttons grayed out with tooltip "offline"

---

## 6. Sync & Storage

### Single source of truth: the iPad
The iPad's SQLite file is always authoritative. The PC holds a passive mirror. **No conflict resolution is needed** because the PC never writes.

### Sync triggers
- On notebook close
- Every 5 minutes while actively writing (debounced)
- Manual "Sync now" button in settings

### Push protocol
- `POST /sync/push` sends a diff: pages changed since `last_sync_at` + their drawing blobs + any new AIMessages.
- Server writes to its own SQLite + `media/` folder.
- Server responds with `accepted_at` timestamp; iPad updates `SyncState.last_sync_at`.

### Disaster recovery
- `POST /sync/pull` returns the full database snapshot.
- Used only when reinstalling the app or recovering from iPad loss.

### What lives where

| Data | iPad | PC |
|---|---|---|
| Notebooks / pages / ink | full | mirror |
| AI chat history | full | mirror |
| Exported PDFs | generated on demand | archived |
| Voice recordings | deleted after transcription | not stored |
| API keys | yes (for school fallback) | yes (primary config) |
| Prompts (for school fallback) | snapshot shipped in IPA (baked at build time) | source-of-truth in `server/prompts/` |

---

## 7. Build & Deploy

### The reality
User has no Mac. Builds happen on **GitHub Actions macOS runners** (free tier: 2000 min/month ≈ 400+ builds). Signing happens on-device via **KSign**.

### Workflow (`.github/workflows/build-ipa.yml`)
```yaml
on: [push]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - checkout
      - setup Xcode
      - xcodebuild test -scheme NotesApp    # runs Tier 1 Swift tests
  build:
    needs: test
    runs-on: macos-latest
    steps:
      - checkout
      - setup Xcode
      - xcodebuild archive (unsigned)
      - package unsigned .ipa
      - upload-artifact: NotesApp.ipa
```

### Why unsigned
KSign signs with the user's own cert on the iPad. No certs/secrets in GitHub. No Apple Developer account required. Works like any sideloaded IPA.

### Iteration loop per change type

| Change type | Rebuild IPA? | Loop time |
|---|---|---|
| Prompt text | No | seconds (hot reload) |
| AI routing, key pool | No | seconds (uvicorn reload) |
| Sync logic on PC | No | seconds |
| New lasso action (PC side) | No | seconds |
| New lasso action (iPad UI) | Yes | 4-6 min |
| Canvas / UI / data model | Yes | 4-6 min |

Once the iPad's generic "send image + action name to PC" plumbing is in place, most AI iteration is zero-rebuild.

### Repo layout

```
ipad-ai-notes/
├── ios/
│   ├── NotesApp.xcodeproj
│   ├── NotesApp/
│   └── NotesAppTests/
├── server/
│   ├── server.py
│   ├── config.yaml.example
│   ├── prompts/
│   ├── tests/
│   └── logs/            # gitignored
├── docs/superpowers/specs/
└── .github/workflows/build-ipa.yml
```

---

## 8. Testing Strategy

### PC server
- **pytest** unit tests for key pool, routing, config loading
- **Integration tests** against real Groq, gated by `RUN_LIVE_TESTS=1` env var (manual only, to control API budget)
- **Prompt regression fixtures** — sample inputs + expected output patterns in `server/tests/fixtures/`

### iPad — Tier 1 (CI, every push)
Logic modules with no UIKit/PencilKit dependencies:
- SQLite models and queries
- Sync diff calculation
- Groq fallback client + mini key rotation
- PDF export
- Chat history management

Run via `xcodebuild test` on the macOS runner. **Build fails → no IPA artifact.** No wasted sideloads on broken logic.

### iPad — Tier 2 (manual smoke on device)
10-item checklist run after each install:
- Pen input feel + latency
- Palm rejection
- Lasso transform end-to-end
- Dark mode render
- Voice recording + transcription
- PC sync happy path
- Groq fallback (disable PC, verify AI still works)
- PDF export
- Notebook create / delete / rename
- Chat history persistence across page navigation

### Prompt iteration loop
Draw on iPad → run action → PC server logs request/response → tweak `server/prompts/*.txt` → server auto-reloads → replay via `curl` against the logged request (or re-run from iPad). Zero rebuild.

### Explicitly NOT testing
- No automated UI tests (XCUITest) — too slow for a personal app
- No load testing — one user
- No cross-device testing — one iPad

---

## 9. Known Risks & Open Questions

### Risks
1. **Slow iteration on iPad-side changes** — mitigated by keeping the iPad thin and iterating on the PC server for most AI work.
2. **Chemistry structural formula recognition is weak** — documented; user will need to verify these outputs.
3. **Physics diagram recognition is inconsistent** — same mitigation; user should treat outputs as drafts.
4. **Groq rate limits under heavy use** — mitigated by 5-key rotation + honest error messages.
5. **KSign 7-day refresh** — inherent to free sideloading; user is already comfortable with this from game sideloading.
6. **Personal API keys stored on iPad for school fallback** — acceptable for a single-user app but means anyone with physical access to the iPad + the app's unsealed container could extract them. Keys should still be stored via iOS Keychain, not SQLite.

### Open questions (for implementation plan)
1. Which SQLite wrapper — GRDB or SQLite.swift? (Minor; GRDB probably wins for Swift ergonomics.)
2. Should Mathpix be a Day-1 integration or deferred? (Currently planned as optional, enabled by config.)
3. Page thumbnails — generate on save, or lazily on library view open?
4. PDF export — iPad-side using UIGraphicsPDFRenderer, or server-side? (Lean iPad-side to keep server stateless.)

---

## 10. Success Criteria

The app is considered successful when:

- User can open it at school, take a full lesson's worth of notes with Apple Pencil, and never notice a lag or glitch in the canvas.
- User can lasso a handwritten math problem and get a correct, clean explanation in under 10 seconds, in Indonesian or English.
- User can speak a question in mixed Indonesian/English and have Whisper transcribe it accurately.
- User can tweak AI prompts from their PC in seconds without rebuilding the iPad app.
- When the user gets home, notes sync automatically without user intervention.
- A Groq rate limit on one key never produces a user-facing error (rotation handles it transparently).

---

## Appendix A — Decisions Log

| Decision | Chosen | Rejected | Why |
|---|---|---|---|
| Canvas | PencilKit + custom overlay | Fully custom Metal | Matches GoodNotes quality for free |
| Note structure | Notebook → Page | Infinite canvas | User preference |
| AI inference | Cloud (Groq) | Local Ollama on PC | User's local models too slow; quality more consistent in cloud |
| Backend role | Proxy + sync only | Primary AI brain | No longer needed; kept for prompt iteration speed |
| Sync model | iPad-authoritative push-only | Bi-directional CRDT | Single user, one device, zero conflict surface |
| Build host | GitHub Actions macOS runners | Cloud Mac rental, Flutter | Free, no Mac needed, preserves native PencilKit |
| Signing | KSign on-device | GitHub signing secrets | No Developer account, matches existing user workflow |
| Live margin suggestions | Rejected | — | User's own call: "even the paid apps don't get it right" |
