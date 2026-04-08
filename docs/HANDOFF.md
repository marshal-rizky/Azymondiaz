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

- **Plan B (iOS app):** IN PROGRESS. All 15 tasks coded and committed.
  - GitHub Actions CI is running — waiting for green build on `macos-15` runner.
  - Once CI is green: download IPA from Actions → sideload via KSign.
  - Smoke checklist: `docs/smoke-checklist.md`

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

## Known CI failure — MUST FIX before Plan B is done

**Error:** `'Database' is ambiguous for type lookup in this context`

**Cause:** Our class `ios/NotesApp/Data/Database.swift` is named `Database`, which collides with GRDB's own internal `Database` class. Swift can't tell them apart in the test target.

**Fix:** Rename our class from `Database` to `AppDatabase` everywhere:
- `ios/NotesApp/Data/Database.swift` — rename the class itself
- `ios/NotesApp/Data/Migrations.swift` — `register(on pool: DatabasePool)` is fine, no change needed
- `ios/NotesApp/App/AppContainer.swift` — `let database: AppDatabase`, `AppDatabase.makeDefault()`
- `ios/NotesAppTests/DatabaseTests.swift` — `let db = try AppDatabase.makeInMemory()`
- `ios/NotesAppTests/NotebookRepositoryTests.swift` — `private var db: AppDatabase!`
- `ios/NotesAppTests/PageRepositoryTests.swift` — `private var db: AppDatabase!`

All other files reference `db.pool` not `Database` directly, so only the above need touching.

## Next steps
1. Fix `Database` → `AppDatabase` name collision (see above)
2. Push fix → wait for green CI
3. Download IPA from Actions tab → sideload via KSign
4. Run smoke checklist at `docs/smoke-checklist.md`
5. Start Plan C: `docs/plans/2026-04-07-plan-c-ipad-ai.md`
