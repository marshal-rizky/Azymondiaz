# NotesApp (iPad)

Personal note-taking app. See `docs/superpowers/specs/2026-04-07-ipad-ai-notes-design.md`.

## Generating the Xcode project

    brew install xcodegen
    cd ios
    xcodegen generate

## Running tests locally (macOS only)

    cd ios
    xcodebuild test \
      -scheme NotesApp \
      -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (4th generation)'

## Building an unsigned IPA

Push to main. GitHub Actions builds and uploads `NotesApp.ipa` as a workflow artifact. Download and sideload via KSign.
