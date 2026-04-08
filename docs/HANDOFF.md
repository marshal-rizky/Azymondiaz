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

## Next steps
1. Confirm CI green on Plan B (check Actions tab: github.com/marshal-rizky/Azymondiaz)
2. Download IPA, sideload, run smoke checklist at `docs/smoke-checklist.md`
3. Start Plan C: `docs/plans/2026-04-07-plan-c-ipad-ai.md`
