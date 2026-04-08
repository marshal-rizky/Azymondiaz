# Plan B — iPad Core Note App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a standalone iPad note-taking app with PencilKit-powered canvas, Notebook→Page organization, dark mode, SQLite persistence, and PDF export — with ZERO AI features. At the end of this plan the user has a usable GoodNotes-style note app installable via KSign. Plan C will plug AI into it later.

**Architecture:** Swift + SwiftUI for screens, UIKit-hosted `PKCanvasView` for the pencil surface, GRDB.swift for SQLite persistence. MVVM-lite: a `Repository` layer owns the DB, SwiftUI views observe `@Observable` view models. The data model matches §3 of the spec exactly so Plan C can attach `AIMessage` and sync without migrations. Build happens on GitHub Actions macOS runners producing unsigned IPAs; KSign signs on-device.

**Tech Stack:**
- Swift 5.10, iOS 17 target (for `@Observable`)
- SwiftUI screens + UIViewRepresentable for PencilKit
- PencilKit (`PKCanvasView`, `PKToolPicker`, `PKDrawing`)
- GRDB.swift (SQLite wrapper) pinned to 6.x
- UIGraphicsPDFRenderer for PDF export
- XCTest for Tier 1 unit tests
- GitHub Actions `macos-14` runner, Xcode 15.4

**Reference spec:** `docs/superpowers/specs/2026-04-07-ipad-ai-notes-design.md` (sections 3, 7, 8 are the ones this plan implements)

---

## File Structure

```
ios/
├── NotesApp.xcodeproj/
├── NotesApp/
│   ├── App/
│   │   ├── NotesAppApp.swift            # @main, wires AppContainer
│   │   └── AppContainer.swift           # singletons: Database, repositories
│   ├── Data/
│   │   ├── Database.swift               # GRDB DatabasePool + migrator
│   │   ├── Migrations.swift             # schema v1 (notebooks, pages, ai_messages, sync_state)
│   │   ├── Notebook.swift               # Codable + FetchableRecord + PersistableRecord
│   │   ├── Page.swift                   # Codable + FetchableRecord + PersistableRecord
│   │   ├── NotebookRepository.swift     # CRUD for notebooks
│   │   └── PageRepository.swift         # CRUD for pages, drawing blob, thumbnails
│   ├── Canvas/
│   │   ├── CanvasView.swift             # UIViewRepresentable wrapping PKCanvasView
│   │   ├── PageTemplate.swift           # enum + background renderer (line/grid/blank)
│   │   ├── ThumbnailRenderer.swift      # PKDrawing → small PNG
│   │   └── PDFExporter.swift            # Notebook → PDF Data
│   ├── Features/
│   │   ├── Library/
│   │   │   ├── LibraryView.swift        # Grid of notebook covers
│   │   │   └── LibraryViewModel.swift
│   │   ├── Notebook/
│   │   │   ├── NotebookView.swift       # page strip + canvas host + toolbar
│   │   │   └── NotebookViewModel.swift
│   │   └── Settings/
│   │       └── SettingsView.swift       # placeholders for PC URL, keys (Plan C wires them)
│   ├── Theme/
│   │   └── Theme.swift                  # colors resolved for light/dark
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
├── NotesAppTests/
│   ├── DatabaseTests.swift
│   ├── NotebookRepositoryTests.swift
│   ├── PageRepositoryTests.swift
│   ├── PageTemplateTests.swift
│   ├── ThumbnailRendererTests.swift
│   └── PDFExporterTests.swift
└── README.md

.github/workflows/
└── build-ipa.yml                        # test → archive unsigned → upload artifact
```

**Why this split:** Data/ has zero UI dependencies so it runs in CI without simulator. Canvas/ wraps UIKit/PencilKit behind thin seams so it can be unit-tested where possible (templates, thumbnails, PDF) and manually smoke-tested where not (actual pen strokes). Features/ is pure SwiftUI so adding Plan C's side panel is a local change per screen.

---

## Conventions

- **Formatter:** no SwiftFormat for now; follow Xcode defaults, 4-space indent.
- **Commits:** conventional commits (`feat:`, `test:`, `chore:`, `fix:`).
- **Tests first:** every task that adds logic starts with the failing test. Pure-UI tasks (SwiftUI views) are manually verified in the smoke checklist, not unit-tested.
- **Run tests with:** `cd ios && xcodebuild test -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (4th generation)' | xcpretty`. On CI this is the same command minus `xcpretty`.
- **DB path in tests:** always an in-memory `DatabasePool(path: ":memory:")` — never touch the real app container.

---

## Task 1: Xcode project scaffolding

**Files:**
- Create: `ios/NotesApp.xcodeproj` (via Xcode GUI or XcodeGen config)
- Create: `ios/NotesApp/App/NotesAppApp.swift`
- Create: `ios/NotesApp/Resources/Info.plist`
- Create: `ios/README.md`
- Create: `.gitignore`

Because you have no Mac, project creation happens on a CI runner via **XcodeGen** (a Swift CLI that generates `.xcodeproj` from a yaml). This keeps the project file in version control as a single `project.yml`.

- [ ] **Step 1: Create root `project.yml` for XcodeGen**

Create `ios/project.yml`:

```yaml
name: NotesApp
options:
  bundleIdPrefix: dev.user
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.10"
    DEVELOPMENT_TEAM: ""
    CODE_SIGN_STYLE: Manual
    CODE_SIGNING_REQUIRED: "NO"
    CODE_SIGNING_ALLOWED: "NO"
packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift
    from: "6.29.0"
targets:
  NotesApp:
    type: application
    platform: iOS
    sources:
      - path: NotesApp
    resources:
      - path: NotesApp/Resources/Assets.xcassets
    info:
      path: NotesApp/Resources/Info.plist
      properties:
        CFBundleDisplayName: Notes
        UILaunchScreen: {}
        UISupportedInterfaceOrientations~ipad:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
        UIRequiredDeviceCapabilities:
          - arm64
        NSMicrophoneUsageDescription: "Used for voice input to AI chat." # Plan C
    dependencies:
      - package: GRDB
  NotesAppTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: NotesAppTests
    dependencies:
      - target: NotesApp
```

- [ ] **Step 2: Create app entry point**

Create `ios/NotesApp/App/NotesAppApp.swift`:

```swift
import SwiftUI

@main
struct NotesAppApp: App {
    var body: some Scene {
        WindowGroup {
            Text("NotesApp — scaffolding")
                .padding()
        }
    }
}
```

- [ ] **Step 3: Create empty asset catalog**

Create `ios/NotesApp/Resources/Assets.xcassets/Contents.json`:

```json
{
  "info" : { "author" : "xcode", "version" : 1 }
}
```

Create `ios/NotesApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 4: Create `.gitignore`**

Create `.gitignore` at repo root:

```
# Xcode
*.xcworkspace
xcuserdata/
DerivedData/
*.xcuserstate
ios/NotesApp.xcodeproj/  # regenerated by xcodegen
build/

# Swift Package Manager
.build/
Packages/
Package.resolved

# macOS
.DS_Store

# secrets
server/config.yaml
```

- [ ] **Step 5: Write README**

Create `ios/README.md`:

```markdown
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
```

- [ ] **Step 6: Commit**

```bash
git add ios/project.yml ios/NotesApp/App/NotesAppApp.swift ios/NotesApp/Resources ios/README.md .gitignore
git commit -m "chore: scaffold iOS NotesApp with xcodegen config"
```

---

## Task 2: GitHub Actions CI — test and build unsigned IPA

**Files:**
- Create: `.github/workflows/build-ipa.yml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/build-ipa.yml`:

```yaml
name: Build iPA
on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

jobs:
  test-and-build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 15.4
        run: sudo xcode-select -s /Applications/Xcode_15.4.app

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        working-directory: ios
        run: xcodegen generate

      - name: Run unit tests
        working-directory: ios
        run: |
          set -o pipefail
          xcodebuild test \
            -scheme NotesApp \
            -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (4th generation),OS=latest' \
            CODE_SIGNING_ALLOWED=NO \
            | tee xcodebuild-test.log

      - name: Archive (unsigned)
        working-directory: ios
        run: |
          xcodebuild archive \
            -scheme NotesApp \
            -configuration Release \
            -destination 'generic/platform=iOS' \
            -archivePath build/NotesApp.xcarchive \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO

      - name: Package unsigned .ipa
        working-directory: ios
        run: |
          mkdir -p build/Payload
          cp -R build/NotesApp.xcarchive/Products/Applications/NotesApp.app build/Payload/
          (cd build && zip -qr NotesApp.ipa Payload)
          rm -rf build/Payload

      - name: Upload IPA
        uses: actions/upload-artifact@v4
        with:
          name: NotesApp-ipa
          path: ios/build/NotesApp.ipa
          if-no-files-found: error
```

- [ ] **Step 2: Verify locally (best-effort)**

If you have any macOS access: `act -j test-and-build` (or push to a throwaway branch). Otherwise: push and watch the run. Expected: **test** step fails at first push because `NotesAppTests/` is empty — that's fine, Task 3 creates it. Mark as acceptable if the **archive** step succeeds.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build-ipa.yml
git commit -m "ci: build unsigned iPA on macos-14 runner"
```

---

## Task 3: Database layer (GRDB setup + first migration)

**Files:**
- Create: `ios/NotesApp/Data/Database.swift`
- Create: `ios/NotesApp/Data/Migrations.swift`
- Create: `ios/NotesAppTests/DatabaseTests.swift`

- [ ] **Step 1: Write the failing test**

Create `ios/NotesAppTests/DatabaseTests.swift`:

```swift
import XCTest
import GRDB
@testable import NotesApp

final class DatabaseTests: XCTestCase {
    func test_migrator_creates_all_tables() throws {
        let db = try Database.makeInMemory()
        try db.pool.read { db in
            let tables = try String.fetchAll(db, sql:
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
            XCTAssertTrue(tables.contains("notebooks"))
            XCTAssertTrue(tables.contains("pages"))
            XCTAssertTrue(tables.contains("ai_messages"))
            XCTAssertTrue(tables.contains("sync_state"))
        }
    }

    func test_migrator_is_idempotent() throws {
        let db = try Database.makeInMemory()
        // Running migrator twice should not throw.
        try Migrations.register(on: db.pool)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios && xcodegen generate && xcodebuild test -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (4th generation)'
```

Expected: **FAIL** — `Database` and `Migrations` not defined.

- [ ] **Step 3: Implement `Database.swift`**

Create `ios/NotesApp/Data/Database.swift`:

```swift
import Foundation
import GRDB

/// Thin wrapper around a GRDB `DatabasePool`. Owns the app's single SQLite file.
final class Database {
    let pool: DatabasePool

    private init(pool: DatabasePool) {
        self.pool = pool
    }

    /// Production: opens/creates `~/Documents/notes.sqlite`.
    static func makeDefault() throws -> Database {
        let url = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("notes.sqlite")
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: url.path, configuration: config)
        try Migrations.register(on: pool)
        return Database(pool: pool)
    }

    /// Tests: in-memory pool, no filesystem.
    static func makeInMemory() throws -> Database {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: ":memory:", configuration: config)
        try Migrations.register(on: pool)
        return Database(pool: pool)
    }
}
```

- [ ] **Step 4: Implement `Migrations.swift`**

Create `ios/NotesApp/Data/Migrations.swift`:

```swift
import Foundation
import GRDB

enum Migrations {
    static func register(on pool: DatabasePool) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "notebooks") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("cover_color", .text).notNull().defaults(to: "#4A90E2")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "pages") { t in
                t.column("id", .text).primaryKey()
                t.column("notebook_id", .text)
                    .notNull()
                    .references("notebooks", onDelete: .cascade)
                t.column("page_index", .integer).notNull()
                t.column("template", .text).notNull()          // 'line' | 'grid' | 'blank'
                t.column("drawing_blob", .blob)                // nullable; empty page = nil
                t.column("thumbnail_blob", .blob)              // nullable until first render
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.uniqueKey(["notebook_id", "page_index"])
            }

            try db.create(table: "ai_messages") { t in
                // Table shape locked in now so Plan C does not need a migration.
                t.column("id", .text).primaryKey()
                t.column("page_id", .text)
                    .notNull()
                    .references("pages", onDelete: .cascade)
                t.column("role", .text).notNull()              // 'user' | 'assistant'
                t.column("text", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }

            try db.create(table: "sync_state") { t in
                t.column("id", .integer).primaryKey()          // always 1
                t.column("last_sync_at", .datetime)
                t.column("pc_server_url", .text)
            }
            try db.execute(sql:
                "INSERT INTO sync_state (id, last_sync_at, pc_server_url) VALUES (1, NULL, NULL)"
            )
        }

        try migrator.migrate(pool)
    }
}
```

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (4th generation)'
```

Expected: **PASS** for both `test_migrator_creates_all_tables` and `test_migrator_is_idempotent`.

- [ ] **Step 6: Commit**

```bash
git add ios/NotesApp/Data/Database.swift ios/NotesApp/Data/Migrations.swift ios/NotesAppTests/DatabaseTests.swift
git commit -m "feat(data): add GRDB database with v1 schema"
```

---

## Task 4: Notebook model + repository

**Files:**
- Create: `ios/NotesApp/Data/Notebook.swift`
- Create: `ios/NotesApp/Data/NotebookRepository.swift`
- Create: `ios/NotesAppTests/NotebookRepositoryTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ios/NotesAppTests/NotebookRepositoryTests.swift`:

```swift
import XCTest
import GRDB
@testable import NotesApp

final class NotebookRepositoryTests: XCTestCase {
    private var db: Database!
    private var repo: NotebookRepository!

    override func setUpWithError() throws {
        db = try Database.makeInMemory()
        repo = NotebookRepository(pool: db.pool)
    }

    func test_create_then_fetchAll_returns_one_notebook() throws {
        let created = try repo.create(title: "Physics", coverColor: "#FF8800")
        let all = try repo.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, created.id)
        XCTAssertEqual(all.first?.title, "Physics")
    }

    func test_rename_persists() throws {
        var nb = try repo.create(title: "Old", coverColor: "#000000")
        nb.title = "New"
        try repo.update(nb)
        let reloaded = try XCTUnwrap(repo.fetch(id: nb.id))
        XCTAssertEqual(reloaded.title, "New")
    }

    func test_delete_removes_notebook() throws {
        let nb = try repo.create(title: "Temp", coverColor: "#111111")
        try repo.delete(id: nb.id)
        XCTAssertNil(try repo.fetch(id: nb.id))
        XCTAssertTrue(try repo.fetchAll().isEmpty)
    }

    func test_fetchAll_sorts_by_updated_at_desc() throws {
        let a = try repo.create(title: "A", coverColor: "#111111")
        Thread.sleep(forTimeInterval: 0.01)
        let b = try repo.create(title: "B", coverColor: "#222222")
        let all = try repo.fetchAll()
        XCTAssertEqual(all.map(\.id), [b.id, a.id])
    }
}
```

- [ ] **Step 2: Run and watch them fail**

Expected: FAIL — `Notebook` / `NotebookRepository` not defined.

- [ ] **Step 3: Implement `Notebook.swift`**

Create `ios/NotesApp/Data/Notebook.swift`:

```swift
import Foundation
import GRDB

struct Notebook: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    var coverColor: String
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "notebooks"

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case coverColor = "cover_color"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

- [ ] **Step 4: Implement `NotebookRepository.swift`**

Create `ios/NotesApp/Data/NotebookRepository.swift`:

```swift
import Foundation
import GRDB

final class NotebookRepository {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    func create(title: String, coverColor: String) throws -> Notebook {
        let now = Date()
        let nb = Notebook(
            id: UUID().uuidString,
            title: title,
            coverColor: coverColor,
            createdAt: now,
            updatedAt: now
        )
        try pool.write { db in
            try nb.insert(db)
        }
        return nb
    }

    func fetchAll() throws -> [Notebook] {
        try pool.read { db in
            try Notebook
                .order(Column("updated_at").desc)
                .fetchAll(db)
        }
    }

    func fetch(id: String) throws -> Notebook? {
        try pool.read { db in
            try Notebook.fetchOne(db, key: id)
        }
    }

    func update(_ notebook: Notebook) throws {
        var copy = notebook
        copy.updatedAt = Date()
        try pool.write { db in
            try copy.update(db)
        }
    }

    func delete(id: String) throws {
        _ = try pool.write { db in
            try Notebook.deleteOne(db, key: id)
        }
    }
}
```

- [ ] **Step 5: Run tests**

Expected: all four `NotebookRepositoryTests` **PASS**.

- [ ] **Step 6: Commit**

```bash
git add ios/NotesApp/Data/Notebook.swift ios/NotesApp/Data/NotebookRepository.swift ios/NotesAppTests/NotebookRepositoryTests.swift
git commit -m "feat(data): add Notebook model + repository"
```

---

## Task 5: Page model + repository

**Files:**
- Create: `ios/NotesApp/Data/Page.swift`
- Create: `ios/NotesApp/Data/PageRepository.swift`
- Create: `ios/NotesAppTests/PageRepositoryTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ios/NotesAppTests/PageRepositoryTests.swift`:

```swift
import XCTest
import GRDB
@testable import NotesApp

final class PageRepositoryTests: XCTestCase {
    private var db: Database!
    private var notebooks: NotebookRepository!
    private var pages: PageRepository!
    private var notebookId: String!

    override func setUpWithError() throws {
        db = try Database.makeInMemory()
        notebooks = NotebookRepository(pool: db.pool)
        pages = PageRepository(pool: db.pool)
        notebookId = try notebooks.create(title: "NB", coverColor: "#123456").id
    }

    func test_append_creates_first_page_with_index_zero() throws {
        let page = try pages.append(notebookId: notebookId, template: .line)
        XCTAssertEqual(page.pageIndex, 0)
        XCTAssertEqual(page.template, .line)
        XCTAssertNil(page.drawingBlob)
    }

    func test_append_assigns_sequential_indexes() throws {
        _ = try pages.append(notebookId: notebookId, template: .blank)
        _ = try pages.append(notebookId: notebookId, template: .line)
        let p3 = try pages.append(notebookId: notebookId, template: .grid)
        XCTAssertEqual(p3.pageIndex, 2)
        let all = try pages.fetchAll(notebookId: notebookId)
        XCTAssertEqual(all.map(\.pageIndex), [0, 1, 2])
    }

    func test_updateDrawing_persists_blob() throws {
        let page = try pages.append(notebookId: notebookId, template: .grid)
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try pages.updateDrawing(pageId: page.id, drawing: bytes, thumbnail: nil)
        let reloaded = try XCTUnwrap(pages.fetch(id: page.id))
        XCTAssertEqual(reloaded.drawingBlob, bytes)
    }

    func test_delete_cascades_from_notebook() throws {
        _ = try pages.append(notebookId: notebookId, template: .blank)
        _ = try pages.append(notebookId: notebookId, template: .blank)
        try notebooks.delete(id: notebookId)
        XCTAssertTrue(try pages.fetchAll(notebookId: notebookId).isEmpty)
    }

    func test_deletePage_reindexes_remaining() throws {
        let p0 = try pages.append(notebookId: notebookId, template: .line)
        let p1 = try pages.append(notebookId: notebookId, template: .line)
        let p2 = try pages.append(notebookId: notebookId, template: .line)
        try pages.delete(id: p1.id)
        let remaining = try pages.fetchAll(notebookId: notebookId)
        XCTAssertEqual(remaining.map(\.id), [p0.id, p2.id])
        XCTAssertEqual(remaining.map(\.pageIndex), [0, 1])
    }
}
```

- [ ] **Step 2: Implement `Page.swift`**

Create `ios/NotesApp/Data/Page.swift`:

```swift
import Foundation
import GRDB

enum PageTemplateKind: String, Codable, CaseIterable {
    case line
    case grid
    case blank
}

struct Page: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var notebookId: String
    var pageIndex: Int
    var template: PageTemplateKind
    var drawingBlob: Data?
    var thumbnailBlob: Data?
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "pages"

    enum CodingKeys: String, CodingKey {
        case id
        case notebookId = "notebook_id"
        case pageIndex = "page_index"
        case template
        case drawingBlob = "drawing_blob"
        case thumbnailBlob = "thumbnail_blob"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

- [ ] **Step 3: Implement `PageRepository.swift`**

Create `ios/NotesApp/Data/PageRepository.swift`:

```swift
import Foundation
import GRDB

final class PageRepository {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    func fetchAll(notebookId: String) throws -> [Page] {
        try pool.read { db in
            try Page
                .filter(Column("notebook_id") == notebookId)
                .order(Column("page_index").asc)
                .fetchAll(db)
        }
    }

    func fetch(id: String) throws -> Page? {
        try pool.read { db in
            try Page.fetchOne(db, key: id)
        }
    }

    func append(notebookId: String, template: PageTemplateKind) throws -> Page {
        try pool.write { db in
            let nextIndex = try Int.fetchOne(db, sql:
                "SELECT COALESCE(MAX(page_index) + 1, 0) FROM pages WHERE notebook_id = ?",
                arguments: [notebookId]
            ) ?? 0
            let now = Date()
            let page = Page(
                id: UUID().uuidString,
                notebookId: notebookId,
                pageIndex: nextIndex,
                template: template,
                drawingBlob: nil,
                thumbnailBlob: nil,
                createdAt: now,
                updatedAt: now
            )
            try page.insert(db)
            return page
        }
    }

    func updateDrawing(pageId: String, drawing: Data, thumbnail: Data?) throws {
        try pool.write { db in
            try db.execute(sql: """
                UPDATE pages
                   SET drawing_blob = ?, thumbnail_blob = ?, updated_at = ?
                 WHERE id = ?
                """,
                arguments: [drawing, thumbnail, Date(), pageId]
            )
        }
    }

    func delete(id: String) throws {
        try pool.write { db in
            guard let page = try Page.fetchOne(db, key: id) else { return }
            try Page.deleteOne(db, key: id)
            // Re-number remaining pages so indexes stay contiguous.
            try db.execute(sql: """
                UPDATE pages
                   SET page_index = page_index - 1
                 WHERE notebook_id = ? AND page_index > ?
                """,
                arguments: [page.notebookId, page.pageIndex]
            )
        }
    }
}
```

- [ ] **Step 4: Run tests**

Expected: all five `PageRepositoryTests` **PASS**.

- [ ] **Step 5: Commit**

```bash
git add ios/NotesApp/Data/Page.swift ios/NotesApp/Data/PageRepository.swift ios/NotesAppTests/PageRepositoryTests.swift
git commit -m "feat(data): add Page model + repository with re-indexing on delete"
```

---

## Task 6: Page template background renderer

**Files:**
- Create: `ios/NotesApp/Canvas/PageTemplate.swift`
- Create: `ios/NotesAppTests/PageTemplateTests.swift`

`PageTemplate` is a pure function `(kind, size) -> UIImage` that draws line / grid / blank backgrounds. Unit-testable because it doesn't depend on PencilKit.

- [ ] **Step 1: Write the failing tests**

Create `ios/NotesAppTests/PageTemplateTests.swift`:

```swift
import XCTest
import UIKit
@testable import NotesApp

final class PageTemplateTests: XCTestCase {
    func test_blank_returns_solid_background() {
        let image = PageTemplate.render(
            kind: .blank,
            size: CGSize(width: 100, height: 100),
            isDark: false
        )
        XCTAssertEqual(image.size, CGSize(width: 100, height: 100))
    }

    func test_line_and_grid_have_different_pixels_than_blank() {
        let size = CGSize(width: 200, height: 200)
        let blank = PageTemplate.render(kind: .blank, size: size, isDark: false).pngData()
        let line  = PageTemplate.render(kind: .line,  size: size, isDark: false).pngData()
        let grid  = PageTemplate.render(kind: .grid,  size: size, isDark: false).pngData()
        XCTAssertNotEqual(blank, line)
        XCTAssertNotEqual(blank, grid)
        XCTAssertNotEqual(line, grid)
    }

    func test_dark_blank_differs_from_light_blank() {
        let size = CGSize(width: 50, height: 50)
        let light = PageTemplate.render(kind: .blank, size: size, isDark: false).pngData()
        let dark  = PageTemplate.render(kind: .blank, size: size, isDark: true).pngData()
        XCTAssertNotEqual(light, dark)
    }
}
```

- [ ] **Step 2: Implement `PageTemplate.swift`**

Create `ios/NotesApp/Canvas/PageTemplate.swift`:

```swift
import UIKit

enum PageTemplate {
    /// Line spacing for ruled paper, in points.
    static let lineSpacing: CGFloat = 32
    /// Grid cell size for grid paper, in points.
    static let gridSize: CGFloat = 24

    static func render(kind: PageTemplateKind, size: CGSize, isDark: Bool) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // Page background.
            let bg: UIColor = isDark
                ? UIColor(white: 0.08, alpha: 1.0)
                : UIColor(white: 0.99, alpha: 1.0)
            cg.setFillColor(bg.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            // Guide color: low-contrast so it never competes with ink.
            let guide: UIColor = isDark
                ? UIColor(white: 0.22, alpha: 1.0)
                : UIColor(white: 0.82, alpha: 1.0)
            cg.setStrokeColor(guide.cgColor)
            cg.setLineWidth(1.0)

            switch kind {
            case .blank:
                return
            case .line:
                var y: CGFloat = lineSpacing
                while y < size.height {
                    cg.move(to: CGPoint(x: 0, y: y))
                    cg.addLine(to: CGPoint(x: size.width, y: y))
                    y += lineSpacing
                }
                cg.strokePath()
            case .grid:
                var x: CGFloat = gridSize
                while x < size.width {
                    cg.move(to: CGPoint(x: x, y: 0))
                    cg.addLine(to: CGPoint(x: x, y: size.height))
                    x += gridSize
                }
                var y: CGFloat = gridSize
                while y < size.height {
                    cg.move(to: CGPoint(x: 0, y: y))
                    cg.addLine(to: CGPoint(x: size.width, y: y))
                    y += gridSize
                }
                cg.strokePath()
            }
        }
    }
}
```

- [ ] **Step 3: Run tests**

Expected: all three **PASS**.

- [ ] **Step 4: Commit**

```bash
git add ios/NotesApp/Canvas/PageTemplate.swift ios/NotesAppTests/PageTemplateTests.swift
git commit -m "feat(canvas): render line/grid/blank page backgrounds"
```

---

## Task 7: Thumbnail renderer

**Files:**
- Create: `ios/NotesApp/Canvas/ThumbnailRenderer.swift`
- Create: `ios/NotesAppTests/ThumbnailRendererTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ios/NotesAppTests/ThumbnailRendererTests.swift`:

```swift
import XCTest
import PencilKit
@testable import NotesApp

final class ThumbnailRendererTests: XCTestCase {
    func test_renders_empty_drawing_to_target_size() {
        let drawing = PKDrawing()
        let png = ThumbnailRenderer.render(
            drawing: drawing,
            template: .line,
            pageSize: CGSize(width: 1024, height: 1366),
            thumbnailWidth: 160,
            isDark: false
        )
        let image = UIImage(data: png)!
        // aspect-preserved height: 1366 * (160/1024) ≈ 213
        XCTAssertEqual(image.size.width, 160, accuracy: 1)
        XCTAssertEqual(image.size.height, 213, accuracy: 2)
    }

    func test_output_is_nonempty_png() {
        let png = ThumbnailRenderer.render(
            drawing: PKDrawing(),
            template: .blank,
            pageSize: CGSize(width: 500, height: 700),
            thumbnailWidth: 100,
            isDark: false
        )
        XCTAssertGreaterThan(png.count, 0)
        // PNG magic: 0x89 'P' 'N' 'G'
        XCTAssertEqual(png.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }
}
```

- [ ] **Step 2: Implement `ThumbnailRenderer.swift`**

Create `ios/NotesApp/Canvas/ThumbnailRenderer.swift`:

```swift
import UIKit
import PencilKit

enum ThumbnailRenderer {
    /// Renders a page (template background + ink) scaled to `thumbnailWidth`, returns PNG data.
    static func render(
        drawing: PKDrawing,
        template: PageTemplateKind,
        pageSize: CGSize,
        thumbnailWidth: CGFloat,
        isDark: Bool
    ) -> Data {
        let scale = thumbnailWidth / pageSize.width
        let targetSize = CGSize(
            width: thumbnailWidth,
            height: (pageSize.height * scale).rounded()
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let image = renderer.image { ctx in
            // 1. Background template scaled to thumb size.
            let bg = PageTemplate.render(kind: template, size: targetSize, isDark: isDark)
            bg.draw(in: CGRect(origin: .zero, size: targetSize))

            // 2. Ink rendered from drawing, scaled.
            if !drawing.bounds.isEmpty {
                let inkImage = drawing.image(
                    from: CGRect(origin: .zero, size: pageSize),
                    scale: scale
                )
                inkImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }
        return image.pngData() ?? Data()
    }
}
```

- [ ] **Step 3: Run tests**

Expected: both **PASS**.

- [ ] **Step 4: Commit**

```bash
git add ios/NotesApp/Canvas/ThumbnailRenderer.swift ios/NotesAppTests/ThumbnailRendererTests.swift
git commit -m "feat(canvas): thumbnail renderer composites template + ink"
```

---

## Task 8: PDF exporter

**Files:**
- Create: `ios/NotesApp/Canvas/PDFExporter.swift`
- Create: `ios/NotesAppTests/PDFExporterTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ios/NotesAppTests/PDFExporterTests.swift`:

```swift
import XCTest
import PencilKit
@testable import NotesApp

final class PDFExporterTests: XCTestCase {
    func test_export_single_empty_page_produces_valid_pdf() {
        let page = RenderablePage(
            drawing: PKDrawing(),
            template: .line,
            size: CGSize(width: 612, height: 792) // US Letter
        )
        let pdf = PDFExporter.export(pages: [page], isDark: false)
        XCTAssertFalse(pdf.isEmpty)
        // PDF magic: "%PDF-"
        XCTAssertEqual(pdf.prefix(5), Data("%PDF-".utf8))
    }

    func test_export_multiple_pages_is_larger_than_single() {
        let size = CGSize(width: 612, height: 792)
        let one = PDFExporter.export(
            pages: [RenderablePage(drawing: PKDrawing(), template: .blank, size: size)],
            isDark: false
        )
        let three = PDFExporter.export(
            pages: Array(repeating:
                RenderablePage(drawing: PKDrawing(), template: .blank, size: size),
                count: 3
            ),
            isDark: false
        )
        XCTAssertGreaterThan(three.count, one.count)
    }
}
```

- [ ] **Step 2: Implement `PDFExporter.swift`**

Create `ios/NotesApp/Canvas/PDFExporter.swift`:

```swift
import UIKit
import PencilKit

struct RenderablePage {
    let drawing: PKDrawing
    let template: PageTemplateKind
    let size: CGSize
}

enum PDFExporter {
    /// Renders pages into a single PDF. PDFs always export in LIGHT theme
    /// regardless of the app's current dark mode — printed notes should be dark-on-light.
    static func export(pages: [RenderablePage], isDark: Bool) -> Data {
        guard let first = pages.first else { return Data() }
        let pageRect = CGRect(origin: .zero, size: first.size)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            for page in pages {
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: page.size), pageInfo: [:])
                // Background: always light for export readability.
                let bg = PageTemplate.render(kind: page.template, size: page.size, isDark: false)
                bg.draw(in: CGRect(origin: .zero, size: page.size))
                // Ink.
                if !page.drawing.bounds.isEmpty {
                    let ink = page.drawing.image(
                        from: CGRect(origin: .zero, size: page.size),
                        scale: 2.0
                    )
                    ink.draw(in: CGRect(origin: .zero, size: page.size))
                }
            }
        }
    }
}
```

- [ ] **Step 3: Run tests**

Expected: both **PASS**.

- [ ] **Step 4: Commit**

```bash
git add ios/NotesApp/Canvas/PDFExporter.swift ios/NotesAppTests/PDFExporterTests.swift
git commit -m "feat(canvas): PDF exporter via UIGraphicsPDFRenderer"
```

---

## Task 9: PencilKit canvas view (SwiftUI wrapper)

**Files:**
- Create: `ios/NotesApp/Canvas/CanvasView.swift`

PencilKit is UIKit; we wrap it with `UIViewRepresentable`. This task is NOT unit-tested — manually verified in the smoke checklist (Task 15).

- [ ] **Step 1: Implement `CanvasView.swift`**

Create `ios/NotesApp/Canvas/CanvasView.swift`:

```swift
import SwiftUI
import PencilKit

/// SwiftUI host for a single `PKCanvasView`. Owns the ink, not the background.
/// Background is rendered separately (SwiftUI `Image` under the canvas) so the
/// canvas can stay transparent and the template can react to dark mode changes.
struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let allowsFingerDrawing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        canvas.alwaysBounceVertical = false

        // Tool picker is attached when canvas becomes first responder.
        DispatchQueue.main.async {
            if let window = canvas.window,
               let picker = PKToolPicker.shared(for: window) {
                picker.setVisible(true, forFirstResponder: canvas)
                picker.addObserver(canvas)
                canvas.becomeFirstResponder()
            }
        }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
        uiView.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        init(_ parent: CanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
```

- [ ] **Step 2: Build (no new tests, Swift must still compile)**

```bash
xcodebuild build -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (4th generation)'
```

Expected: build **SUCCEEDS**. If it fails, fix typos until it builds before committing.

- [ ] **Step 3: Commit**

```bash
git add ios/NotesApp/Canvas/CanvasView.swift
git commit -m "feat(canvas): SwiftUI wrapper around PKCanvasView"
```

---

## Task 10: App container (wire repositories into SwiftUI environment)

**Files:**
- Create: `ios/NotesApp/App/AppContainer.swift`
- Modify: `ios/NotesApp/App/NotesAppApp.swift`

- [ ] **Step 1: Implement `AppContainer.swift`**

Create `ios/NotesApp/App/AppContainer.swift`:

```swift
import Foundation
import SwiftUI

/// Single composition root. Holds the long-lived database and repositories so
/// views can reach them via `@Environment(AppContainer.self)`.
@Observable
final class AppContainer {
    let database: Database
    let notebooks: NotebookRepository
    let pages: PageRepository

    init(database: Database) {
        self.database = database
        self.notebooks = NotebookRepository(pool: database.pool)
        self.pages = PageRepository(pool: database.pool)
    }

    static func makeDefault() -> AppContainer {
        do {
            let db = try Database.makeDefault()
            return AppContainer(database: db)
        } catch {
            // A broken database on first launch is catastrophic and unrecoverable —
            // surface it immediately instead of limping along with a corrupt store.
            fatalError("Failed to open database: \(error)")
        }
    }
}
```

- [ ] **Step 2: Update `NotesAppApp.swift` to host the container**

Replace the contents of `ios/NotesApp/App/NotesAppApp.swift` with:

```swift
import SwiftUI

@main
struct NotesAppApp: App {
    @State private var container = AppContainer.makeDefault()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(container)
        }
    }
}
```

- [ ] **Step 3: Build**

Expected: build **FAILS** — `LibraryView` does not exist yet. That's expected; next task creates it.

- [ ] **Step 4: Commit (WIP — resolved next task)**

```bash
git add ios/NotesApp/App/AppContainer.swift ios/NotesApp/App/NotesAppApp.swift
git commit -m "feat(app): composition root with AppContainer"
```

---

## Task 11: Library screen

**Files:**
- Create: `ios/NotesApp/Features/Library/LibraryViewModel.swift`
- Create: `ios/NotesApp/Features/Library/LibraryView.swift`

- [ ] **Step 1: Implement `LibraryViewModel.swift`**

```swift
import Foundation
import SwiftUI

@Observable
final class LibraryViewModel {
    private(set) var notebooks: [Notebook] = []
    var errorMessage: String?

    private let repo: NotebookRepository

    init(repo: NotebookRepository) {
        self.repo = repo
    }

    func reload() {
        do {
            notebooks = try repo.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createNotebook(title: String) {
        let color = Self.randomCoverColor()
        do {
            _ = try repo.create(title: title, coverColor: color)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ notebook: Notebook) {
        do {
            try repo.delete(id: notebook.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func randomCoverColor() -> String {
        let palette = ["#4A90E2", "#F5A623", "#7ED321", "#D0021B", "#9013FE", "#50E3C2"]
        return palette.randomElement() ?? "#4A90E2"
    }
}
```

- [ ] **Step 2: Implement `LibraryView.swift`**

```swift
import SwiftUI

struct LibraryView: View {
    @Environment(AppContainer.self) private var container
    @State private var viewModel: LibraryViewModel?
    @State private var showingNewNotebookSheet = false
    @State private var newNotebookTitle = ""

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 24)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let vm = viewModel {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(vm.notebooks) { notebook in
                            NavigationLink(value: notebook) {
                                NotebookCoverTile(notebook: notebook)
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    vm.delete(notebook)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newNotebookTitle = ""
                        showingNewNotebookSheet = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .navigationDestination(for: Notebook.self) { notebook in
                NotebookView(notebook: notebook)
            }
            .sheet(isPresented: $showingNewNotebookSheet) {
                newNotebookSheet
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = LibraryViewModel(repo: container.notebooks)
                }
                viewModel?.reload()
            }
        }
    }

    private var newNotebookSheet: some View {
        NavigationStack {
            Form {
                TextField("Notebook title", text: $newNotebookTitle)
            }
            .navigationTitle("New notebook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingNewNotebookSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let title = newNotebookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        viewModel?.createNotebook(title: title)
                        showingNewNotebookSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct NotebookCoverTile: View {
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: notebook.coverColor) ?? .blue)
                .aspectRatio(3.0/4.0, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    Text(notebook.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(12)
                }
                .shadow(radius: 4, y: 2)
            Text(notebook.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension Color {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red:   Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >> 8)  & 0xFF) / 255.0,
            blue:  Double( v        & 0xFF) / 255.0
        )
    }
}
```

- [ ] **Step 3: Build**

Expected: build still **FAILS** — `NotebookView` and `SettingsView` not yet defined. Carry on.

- [ ] **Step 4: Commit**

```bash
git add ios/NotesApp/Features/Library
git commit -m "feat(library): grid of notebook covers with create/delete"
```

---

## Task 12: Notebook screen — page strip + canvas host

**Files:**
- Create: `ios/NotesApp/Features/Notebook/NotebookViewModel.swift`
- Create: `ios/NotesApp/Features/Notebook/NotebookView.swift`

- [ ] **Step 1: Implement `NotebookViewModel.swift`**

```swift
import Foundation
import PencilKit
import SwiftUI

@Observable
final class NotebookViewModel {
    let notebook: Notebook
    private(set) var pages: [Page] = []
    var currentPageIndex: Int = 0
    var currentDrawing = PKDrawing() {
        didSet { scheduleSave() }
    }
    var errorMessage: String?

    private let repo: PageRepository
    private var saveWorkItem: DispatchWorkItem?

    init(notebook: Notebook, repo: PageRepository) {
        self.notebook = notebook
        self.repo = repo
    }

    var currentPage: Page? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        return pages[currentPageIndex]
    }

    func load() {
        do {
            pages = try repo.fetchAll(notebookId: notebook.id)
            if pages.isEmpty {
                _ = try repo.append(notebookId: notebook.id, template: .line)
                pages = try repo.fetchAll(notebookId: notebook.id)
            }
            currentPageIndex = 0
            loadDrawingForCurrentPage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectPage(index: Int) {
        flushSave()
        currentPageIndex = max(0, min(index, pages.count - 1))
        loadDrawingForCurrentPage()
    }

    func addPage(template: PageTemplateKind) {
        flushSave()
        do {
            _ = try repo.append(notebookId: notebook.id, template: template)
            pages = try repo.fetchAll(notebookId: notebook.id)
            currentPageIndex = pages.count - 1
            loadDrawingForCurrentPage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCurrentPage() {
        guard let page = currentPage else { return }
        saveWorkItem?.cancel()
        do {
            try repo.delete(id: page.id)
            pages = try repo.fetchAll(notebookId: notebook.id)
            if pages.isEmpty {
                _ = try repo.append(notebookId: notebook.id, template: .line)
                pages = try repo.fetchAll(notebookId: notebook.id)
            }
            currentPageIndex = min(currentPageIndex, pages.count - 1)
            loadDrawingForCurrentPage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Force-write the current drawing immediately. Call on background / dismiss.
    func flushSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        persistCurrentDrawing()
    }

    // MARK: - Private

    private func loadDrawingForCurrentPage() {
        guard let page = currentPage else {
            currentDrawing = PKDrawing()
            return
        }
        if let blob = page.drawingBlob, let restored = try? PKDrawing(data: blob) {
            currentDrawing = restored
        } else {
            currentDrawing = PKDrawing()
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistCurrentDrawing()
        }
        saveWorkItem = work
        // Debounce: coalesce fast pen strokes into one write.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func persistCurrentDrawing() {
        guard let page = currentPage else { return }
        let drawing = currentDrawing
        let data = drawing.dataRepresentation()
        let thumbSize = CGSize(width: 1024, height: 1366)
        let thumb = ThumbnailRenderer.render(
            drawing: drawing,
            template: page.template,
            pageSize: thumbSize,
            thumbnailWidth: 160,
            isDark: false
        )
        do {
            try repo.updateDrawing(pageId: page.id, drawing: data, thumbnail: thumb)
            // Refresh local page record so the strip thumbnail updates.
            if let refreshed = try repo.fetch(id: page.id),
               let idx = pages.firstIndex(where: { $0.id == page.id }) {
                pages[idx] = refreshed
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Implement `NotebookView.swift`**

```swift
import SwiftUI
import PencilKit

struct NotebookView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let notebook: Notebook
    @State private var viewModel: NotebookViewModel?
    @State private var showingShareSheet = false
    @State private var pdfData: Data?

    var body: some View {
        HStack(spacing: 0) {
            if let vm = viewModel {
                pageStrip(vm: vm)
                    .frame(width: 140)
                    .background(Color(.secondarySystemBackground))
                Divider()
                canvasArea(vm: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let vm = viewModel {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Line") { vm.addPage(template: .line) }
                        Button("Grid") { vm.addPage(template: .grid) }
                        Button("Blank") { vm.addPage(template: .blank) }
                    } label: {
                        Label("Add page", systemImage: "plus.square")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportPDF(vm: vm)
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        vm.deleteCurrentPage()
                    } label: {
                        Label("Delete page", systemImage: "trash")
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                let vm = NotebookViewModel(notebook: notebook, repo: container.pages)
                vm.load()
                viewModel = vm
            }
        }
        .onDisappear {
            viewModel?.flushSave()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let data = pdfData {
                ShareSheet(items: [PDFActivityItem(data: data, title: notebook.title)])
            }
        }
    }

    private func pageStrip(vm: NotebookViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(vm.pages.enumerated()), id: \.element.id) { index, page in
                    Button {
                        vm.selectPage(index: index)
                    } label: {
                        pageStripThumb(page: page, isSelected: index == vm.currentPageIndex)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private func pageStripThumb(page: Page, isSelected: Bool) -> some View {
        VStack(spacing: 4) {
            Group {
                if let blob = page.thumbnailBlob, let img = UIImage(data: blob) {
                    Image(uiImage: img).resizable().scaledToFit()
                } else {
                    Rectangle().fill(Color(.systemBackground))
                }
            }
            .aspectRatio(3.0/4.0, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                            lineWidth: isSelected ? 2 : 1)
            )
            Text("\(page.pageIndex + 1)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func canvasArea(vm: NotebookViewModel) -> some View {
        GeometryReader { geo in
            ZStack {
                if let page = vm.currentPage {
                    Image(uiImage: PageTemplate.render(
                        kind: page.template,
                        size: geo.size,
                        isDark: colorScheme == .dark
                    ))
                    .resizable()
                    CanvasView(
                        drawing: Binding(
                            get: { vm.currentDrawing },
                            set: { vm.currentDrawing = $0 }
                        ),
                        allowsFingerDrawing: false
                    )
                } else {
                    Text("No page")
                }
            }
        }
    }

    private func exportPDF(vm: NotebookViewModel) {
        vm.flushSave()
        let pageSize = CGSize(width: 1024, height: 1366)
        let renderables: [RenderablePage] = vm.pages.map { p in
            let drawing = (p.drawingBlob.flatMap { try? PKDrawing(data: $0) }) ?? PKDrawing()
            return RenderablePage(drawing: drawing, template: p.template, size: pageSize)
        }
        pdfData = PDFExporter.export(pages: renderables, isDark: false)
        showingShareSheet = pdfData != nil
    }
}

// MARK: - UIKit share sheet bridge

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private final class PDFActivityItem: NSObject, UIActivityItemSource {
    let data: Data
    let title: String
    init(data: Data, title: String) {
        self.data = data
        self.title = title
    }
    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        "\(title).pdf"
    }
    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType type: UIActivity.ActivityType?) -> Any? {
        // Write to a temp file so the share sheet presents it as a PDF attachment.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(title).pdf")
        try? data.write(to: url)
        return url
    }
}
```

- [ ] **Step 3: Build**

Still needs `SettingsView` — next task.

- [ ] **Step 4: Commit**

```bash
git add ios/NotesApp/Features/Notebook
git commit -m "feat(notebook): page strip + PencilKit canvas + PDF export"
```

---

## Task 13: Settings screen (placeholder for Plan C)

**Files:**
- Create: `ios/NotesApp/Features/Settings/SettingsView.swift`

Only Plan B-relevant settings exist here. Plan C will add API key fields, PC server URL, voice language, etc.

- [ ] **Step 1: Implement `SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultTemplate") private var defaultTemplateRaw: String = PageTemplateKind.line.rawValue
    @AppStorage("themePreference") private var themePreference: String = "system"

    var body: some View {
        Form {
            Section("Paper") {
                Picker("Default template", selection: $defaultTemplateRaw) {
                    Text("Line").tag(PageTemplateKind.line.rawValue)
                    Text("Grid").tag(PageTemplateKind.grid.rawValue)
                    Text("Blank").tag(PageTemplateKind.blank.rawValue)
                }
            }
            Section("Appearance") {
                Picker("Theme", selection: $themePreference) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }
            Section("AI") {
                Text("Plan C will add PC server URL, Groq keys, and voice language here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
```

- [ ] **Step 2: Build**

Expected: project **BUILDS** cleanly. If red squigglies remain, fix them before committing.

- [ ] **Step 3: Run full test suite**

```bash
xcodebuild test -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (4th generation)'
```

Expected: **ALL tests pass** (Database, NotebookRepository, PageRepository, PageTemplate, ThumbnailRenderer, PDFExporter — around 16 tests total).

- [ ] **Step 4: Commit**

```bash
git add ios/NotesApp/Features/Settings
git commit -m "feat(settings): paper + theme preferences (AI section placeholder)"
```

---

## Task 14: Theme plumbing — apply user theme preference to window

**Files:**
- Create: `ios/NotesApp/Theme/Theme.swift`
- Modify: `ios/NotesApp/App/NotesAppApp.swift`

- [ ] **Step 1: Implement `Theme.swift`**

```swift
import SwiftUI

enum ThemePreference: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    static func fromStorage(_ raw: String) -> ThemePreference {
        ThemePreference(rawValue: raw) ?? .system
    }
}
```

- [ ] **Step 2: Update `NotesAppApp.swift`**

```swift
import SwiftUI

@main
struct NotesAppApp: App {
    @State private var container = AppContainer.makeDefault()
    @AppStorage("themePreference") private var themePreference: String = "system"

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(container)
                .preferredColorScheme(ThemePreference.fromStorage(themePreference).colorScheme)
        }
    }
}
```

- [ ] **Step 3: Build and test**

```bash
xcodebuild test -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (4th generation)'
```

Expected: still all green.

- [ ] **Step 4: Commit**

```bash
git add ios/NotesApp/Theme ios/NotesApp/App/NotesAppApp.swift
git commit -m "feat(theme): honor user theme preference at window scope"
```

---

## Task 15: Wire CI to the complete project + manual smoke test checklist

**Files:**
- Modify: `ios/README.md` (append smoke checklist)
- Create: `docs/smoke-checklist.md`

At this point CI should produce a green build + an `NotesApp.ipa` artifact. Use it.

- [ ] **Step 1: Push the branch**

```bash
git push origin HEAD
```

Expected: GitHub Actions workflow runs, test step passes, archive + IPA artifact is attached.

- [ ] **Step 2: Download IPA and install via KSign**

1. On GitHub: Actions tab → latest run → download `NotesApp-ipa` artifact.
2. Unzip → `NotesApp.ipa`.
3. Transfer to iPad (AirDrop / Files / browser download).
4. Open in KSign → sign with your cert → install.

- [ ] **Step 3: Create `docs/smoke-checklist.md`**

```markdown
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
```

- [ ] **Step 4: Append link to README**

Add to `ios/README.md` bottom:

```markdown
## Smoke testing

After each install, run `docs/smoke-checklist.md` end-to-end before relying on the build.
```

- [ ] **Step 5: Commit**

```bash
git add docs/smoke-checklist.md ios/README.md
git commit -m "docs: manual smoke test checklist for Plan B builds"
```

- [ ] **Step 6: Run the smoke checklist end-to-end**

Walk through every checkbox on the real iPad. If any fail, return to the relevant task and fix before declaring Plan B done.

---

## Self-Review

**Spec coverage** (against §3, §7, §8 of the spec):
- §3 Canvas (PKCanvasView + overlay + templates) → Tasks 6, 9, 12 ✓
- §3 Data model (Notebook, Page, AIMessage table, SyncState) → Tasks 3, 4, 5 ✓ (AIMessage table created empty; repository deferred to Plan C)
- §3 Screens (Library, Notebook view, Page, Settings) → Tasks 11, 12, 13 (side panel chat deferred to Plan C as noted) ✓
- §3 Dark mode → Tasks 6 (templates), 13 (picker), 14 (window scope) ✓
- §3 Offline behavior (non-AI works fully offline) → implicit: no network calls in Plan B ✓
- §7 Repo layout → matches ✓
- §7 GitHub Actions build-ipa.yml → Task 2 ✓
- §7 KSign sideload → Task 15 ✓
- §8 Tier 1 tests (SQLite, PDF export; sync diff, Groq client, chat history → Plan C) → Tasks 3–8 ✓
- §8 Tier 2 smoke test → Task 15 ✓

**Gaps deferred to Plan C (explicitly out of scope here):**
- AIMessage CRUD and side-panel chat
- Voice input / mic button
- Sync push/pull client
- Lasso transforms
- Groq fallback client + key pool
- Baked-prompt snapshot in the bundle

**Placeholder scan:** No TBDs, no "handle appropriately," no missing code blocks. Every step that touches code shows the exact code.

**Type consistency check:**
- `PageTemplateKind` used consistently across `Page.swift`, `PageTemplate`, `ThumbnailRenderer`, `PDFExporter`, `NotebookViewModel`, `SettingsView` ✓
- `Database.makeDefault()` / `makeInMemory()` used consistently in tests and `AppContainer` ✓
- `NotebookRepository.create(title:coverColor:)` signature matches call sites in `LibraryViewModel` ✓
- `PageRepository.append(notebookId:template:)` / `updateDrawing(pageId:drawing:thumbnail:)` / `delete(id:)` — consistent ✓
- `PKDrawing(data:)` throwing initializer handled with `try?` everywhere ✓

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-07-plan-b-ipad-core.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best for a plan this size (15 tasks).

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach? (Note: Plan C — AI integration — is still to be written. Say "write Plan C" to continue planning, or pick an execution mode for Plan A / B.)
