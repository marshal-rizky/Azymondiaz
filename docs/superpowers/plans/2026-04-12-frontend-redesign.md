# Frontend Redesign — Gold & Black Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign every iOS screen to a premium Gold & Black dark theme matching the approved mockups, add folder support to the Library, replace PKToolPicker with an integrated action bar, and convert the chat side panel to a bottom sheet.

**Architecture:** Design tokens first (`DesignSystem.swift`) → data model changes (`Folder` table, `folder_id` on notebooks) → screen-by-screen redesign following the token system. Each task is independently testable or smoke-testable.

**Tech Stack:** Swift 5.10, SwiftUI, PencilKit, GRDB.swift 6.x, iOS 17+

---

## File Map

| Action | File |
|---|---|
| **Create** | `ios/NotesApp/Theme/DesignSystem.swift` |
| **Create** | `ios/NotesApp/Data/Folder.swift` |
| **Create** | `ios/NotesApp/Data/FolderRepository.swift` |
| **Create** | `ios/NotesApp/Features/Library/FolderView.swift` |
| **Create** | `ios/NotesAppTests/FolderRepositoryTests.swift` |
| **Modify** | `ios/NotesApp/Theme/Theme.swift` |
| **Modify** | `ios/NotesApp/App/NotesAppApp.swift` |
| **Modify** | `ios/NotesApp/App/AppContainer.swift` |
| **Modify** | `ios/NotesApp/Data/Migrations.swift` |
| **Modify** | `ios/NotesApp/Data/Notebook.swift` |
| **Modify** | `ios/NotesApp/Data/NotebookRepository.swift` |
| **Modify** | `ios/NotesApp/Features/Library/LibraryView.swift` |
| **Modify** | `ios/NotesApp/Features/Library/LibraryViewModel.swift` |
| **Modify** | `ios/NotesApp/Features/Notebook/NotebookView.swift` |
| **Modify** | `ios/NotesApp/Canvas/CanvasView.swift` |
| **Modify** | `ios/NotesApp/Features/Chat/ChatPanelView.swift` |
| **Modify** | `ios/NotesApp/Features/Notebook/TransformResultView.swift` |
| **Modify** | `ios/NotesApp/Features/Notebook/LassoMenuView.swift` |
| **Modify** | `ios/NotesApp/Features/Settings/SettingsView.swift` |
| **Modify** | `ios/NotesApp/AI/MathWebView.swift` |

---

## Task 1: Design Tokens

**Files:**
- Create: `ios/NotesApp/Theme/DesignSystem.swift`
- Modify: `ios/NotesApp/Features/Library/LibraryView.swift` (remove duplicate `Color(hex:)`)

- [ ] **Step 1: Create DesignSystem.swift**

```swift
// ios/NotesApp/Theme/DesignSystem.swift
import SwiftUI

enum AppColors {
    // Backgrounds
    static let bg       = Color(hex: "#0A0A0C")!
    static let surface  = Color(hex: "#141416")!
    static let surface2 = Color(hex: "#1C1C1E")!
    static let surface3 = Color(hex: "#242426")!

    // Borders
    static let border  = Color(hex: "#2A2A2E")!
    static let border2 = Color(hex: "#333338")!

    // Gold accent
    static let gold      = Color(hex: "#C9A84C")!
    static let goldDark  = Color(hex: "#A87C28")!
    static let goldLight = Color(hex: "#E8C96A")!
    static var goldGradient: LinearGradient {
        LinearGradient(colors: [gold, goldDark],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Text
    static let textPrimary   = Color(hex: "#F0EDE6")!
    static let textSecondary = Color(hex: "#A0A0A8")!
    static let textTertiary  = Color(hex: "#606068")!

    // Canvas — always light so ink is readable
    static let canvasPaper = Color(hex: "#FAF8F3")!
    static let canvasRuled = Color(hex: "#C8D4D8")!
}

enum AppFonts {
    static let navTitle     = Font.system(size: 17, weight: .bold)
    static let sectionHeader = Font.system(size: 11, weight: .semibold)
    static let body         = Font.system(size: 14, weight: .regular)
    static let bodyBold     = Font.system(size: 14, weight: .semibold)
    static let caption      = Font.system(size: 11, weight: .regular)
    static let micro        = Font.system(size: 9,  weight: .regular)
}

enum AppRadius {
    static let card:   CGFloat = 10
    static let button: CGFloat = 9
    static let chip:   CGFloat = 8
    static let thumb:  CGFloat = 6
}

enum AppSpacing {
    static let page:  CGFloat = 18
    static let grid:  CGFloat = 16
    static let stack: CGFloat = 10
}

// MARK: - Color hex initialiser (canonical, used everywhere)
extension Color {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >>  8) & 0xFF) / 255,
            blue:  Double( v        & 0xFF) / 255
        )
    }
}

// MARK: - Cover gradient helpers
/// Notebook covers store their gradient as "START_HEX|END_HEX".
/// Falls back to a solid color for legacy single-hex values.
extension String {
    var asCoverGradient: LinearGradient {
        let parts = self.split(separator: "|").map(String.init)
        if parts.count == 2,
           let c1 = Color(hex: parts[0]),
           let c2 = Color(hex: parts[1]) {
            return LinearGradient(colors: [c1, c2],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        let c = Color(hex: self) ?? AppColors.gold
        return LinearGradient(colors: [c, c],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
```

- [ ] **Step 2: Remove duplicate `Color(hex:)` from LibraryView.swift**

Delete the entire `extension Color { init?(hex:) ... }` block at the bottom of `ios/NotesApp/Features/Library/LibraryView.swift` (lines 109–120). `DesignSystem.swift` is now the single definition.

- [ ] **Step 3: Commit**

```bash
git add ios/NotesApp/Theme/DesignSystem.swift ios/NotesApp/Features/Library/LibraryView.swift
git commit -m "feat: add DesignSystem.swift — gold/black tokens and cover gradient helpers"
```

---

## Task 2: Folder Model + Migration

**Files:**
- Create: `ios/NotesApp/Data/Folder.swift`
- Modify: `ios/NotesApp/Data/Migrations.swift`
- Modify: `ios/NotesApp/Data/Notebook.swift`

- [ ] **Step 1: Create Folder.swift**

```swift
// ios/NotesApp/Data/Folder.swift
import Foundation
import GRDB

struct Folder: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var parentFolderID: String?
    var title: String
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "folders"

    enum CodingKeys: String, CodingKey {
        case id
        case parentFolderID = "parent_folder_id"
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

- [ ] **Step 2: Add `folderID` to Notebook.swift**

Replace the full content of `ios/NotesApp/Data/Notebook.swift`:

```swift
// ios/NotesApp/Data/Notebook.swift
import Foundation
import GRDB

struct Notebook: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var folderID: String?
    var title: String
    var coverColor: String
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "notebooks"

    enum CodingKeys: String, CodingKey {
        case id
        case folderID   = "folder_id"
        case title
        case coverColor = "cover_color"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
    }
}
```

- [ ] **Step 3: Add v2 migration to Migrations.swift**

Add the following **before** `try migrator.migrate(writer)` in `ios/NotesApp/Data/Migrations.swift`:

```swift
migrator.registerMigration("v2_folders") { db in
    try db.create(table: "folders") { t in
        t.column("id", .text).primaryKey()
        t.column("parent_folder_id", .text)
            .references("folders", onDelete: .cascade)
        t.column("title", .text).notNull()
        t.column("created_at", .datetime).notNull()
        t.column("updated_at", .datetime).notNull()
    }
    try db.alter(table: "notebooks") { t in
        t.add(column: "folder_id", .text)
            .references("folders", onDelete: .setNull)
    }
}
```

- [ ] **Step 4: Run existing tests to confirm migration doesn't break anything**

```bash
cd ios && xcodebuild test -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad (10th generation)' 2>&1 | tail -20
```

Expected: all existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/NotesApp/Data/Folder.swift ios/NotesApp/Data/Notebook.swift ios/NotesApp/Data/Migrations.swift
git commit -m "feat: add Folder model and v2 migration (folder_id on notebooks)"
```

---

## Task 3: FolderRepository (TDD)

**Files:**
- Create: `ios/NotesApp/Data/FolderRepository.swift`
- Create: `ios/NotesAppTests/FolderRepositoryTests.swift`

- [ ] **Step 1: Write failing tests first**

```swift
// ios/NotesAppTests/FolderRepositoryTests.swift
import XCTest
import GRDB
@testable import NotesApp

final class FolderRepositoryTests: XCTestCase {
    private var db: AppDatabase!
    private var repo: FolderRepository!

    override func setUpWithError() throws {
        db = try AppDatabase.makeInMemory()
        repo = FolderRepository(writer: db.writer)
    }

    func test_create_root_folder_then_fetchRoots_returns_it() throws {
        let f = try repo.create(title: "Science", parentFolderID: nil)
        let roots = try repo.fetchChildren(of: nil)
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].id, f.id)
        XCTAssertNil(roots[0].parentFolderID)
    }

    func test_create_subfolder_then_fetchChildren_returns_it() throws {
        let parent = try repo.create(title: "Science", parentFolderID: nil)
        let child  = try repo.create(title: "Semester 1", parentFolderID: parent.id)
        let children = try repo.fetchChildren(of: parent.id)
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0].id, child.id)
        XCTAssertEqual(children[0].parentFolderID, parent.id)
    }

    func test_fetchRoots_excludes_subfolders() throws {
        let parent = try repo.create(title: "Science", parentFolderID: nil)
        _ = try repo.create(title: "Semester 1", parentFolderID: parent.id)
        let roots = try repo.fetchChildren(of: nil)
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].id, parent.id)
    }

    func test_rename_persists() throws {
        var f = try repo.create(title: "Old", parentFolderID: nil)
        f.title = "New"
        try repo.update(f)
        let reloaded = try XCTUnwrap(repo.fetch(id: f.id))
        XCTAssertEqual(reloaded.title, "New")
    }

    func test_delete_cascades_to_subfolders() throws {
        let parent = try repo.create(title: "Science", parentFolderID: nil)
        _ = try repo.create(title: "Semester 1", parentFolderID: parent.id)
        try repo.delete(id: parent.id)
        let remaining = try repo.fetchChildren(of: nil)
        XCTAssertTrue(remaining.isEmpty)
        let children = try repo.fetchChildren(of: parent.id)
        XCTAssertTrue(children.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests — confirm they fail with "cannot find type FolderRepository"**

```bash
cd ios && xcodebuild test -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad (10th generation)' 2>&1 | grep -E "error:|FAILED"
```

Expected: compile error about missing `FolderRepository`.

- [ ] **Step 3: Implement FolderRepository**

```swift
// ios/NotesApp/Data/FolderRepository.swift
import Foundation
import GRDB

final class FolderRepository {
    private let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    func create(title: String, parentFolderID: String?) throws -> Folder {
        let now = Date()
        let folder = Folder(
            id: UUID().uuidString,
            parentFolderID: parentFolderID,
            title: title,
            createdAt: now,
            updatedAt: now
        )
        try writer.write { db in try folder.insert(db) }
        return folder
    }

    /// Fetches direct children of a folder. Pass nil for root-level folders.
    func fetchChildren(of parentID: String?) throws -> [Folder] {
        try writer.read { db in
            if let pid = parentID {
                return try Folder
                    .filter(Column("parent_folder_id") == pid)
                    .order(Column("title"))
                    .fetchAll(db)
            } else {
                return try Folder
                    .filter(Column("parent_folder_id") == nil)
                    .order(Column("title"))
                    .fetchAll(db)
            }
        }
    }

    func fetch(id: String) throws -> Folder? {
        try writer.read { db in try Folder.fetchOne(db, key: id) }
    }

    func update(_ folder: Folder) throws {
        var copy = folder
        copy.updatedAt = Date()
        try writer.write { db in try copy.update(db) }
    }

    func delete(id: String) throws {
        _ = try writer.write { db in try Folder.deleteOne(db, key: id) }
    }
}
```

- [ ] **Step 4: Run tests — confirm all 5 pass**

```bash
cd ios && xcodebuild test -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad (10th generation)' 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/NotesApp/Data/FolderRepository.swift ios/NotesAppTests/FolderRepositoryTests.swift
git commit -m "feat: FolderRepository with TDD — CRUD + nested fetch"
```

---

## Task 4: LibraryViewModel + AppContainer Update

**Files:**
- Modify: `ios/NotesApp/Features/Library/LibraryViewModel.swift`
- Modify: `ios/NotesApp/App/AppContainer.swift`
- Modify: `ios/NotesApp/Data/NotebookRepository.swift`

- [ ] **Step 1: Add `fetchAll(folderID:)` to NotebookRepository**

Add this method to `ios/NotesApp/Data/NotebookRepository.swift` after `fetchAll()`:

```swift
/// Fetches notebooks in a specific folder. Pass nil for root-level notebooks.
func fetchAll(folderID: String?) throws -> [Notebook] {
    try writer.read { db in
        if let fid = folderID {
            return try Notebook
                .filter(Column("folder_id") == fid)
                .order(Column("updated_at").desc)
                .fetchAll(db)
        } else {
            return try Notebook
                .filter(Column("folder_id") == nil)
                .order(Column("updated_at").desc)
                .fetchAll(db)
        }
    }
}
```

Also update `create` to accept an optional `folderID`:

```swift
func create(title: String, coverColor: String, folderID: String? = nil) throws -> Notebook {
    let now = Date()
    let nb = Notebook(
        id: UUID().uuidString,
        folderID: folderID,
        title: title,
        coverColor: coverColor,
        createdAt: now,
        updatedAt: now
    )
    try writer.write { db in try nb.insert(db) }
    return nb
}
```

- [ ] **Step 2: Rewrite LibraryViewModel**

Replace the full content of `ios/NotesApp/Features/Library/LibraryViewModel.swift`:

```swift
// ios/NotesApp/Features/Library/LibraryViewModel.swift
import Foundation
import SwiftUI

@Observable
final class LibraryViewModel {
    private(set) var folders: [Folder] = []
    private(set) var notebooks: [Notebook] = []
    var errorMessage: String?

    /// The folder this view is scoped to. nil = Library root.
    let currentFolderID: String?

    private let notebookRepo: NotebookRepository
    private let folderRepo: FolderRepository

    init(notebookRepo: NotebookRepository,
         folderRepo: FolderRepository,
         currentFolderID: String? = nil) {
        self.notebookRepo = notebookRepo
        self.folderRepo = folderRepo
        self.currentFolderID = currentFolderID
    }

    func reload() {
        do {
            folders   = try folderRepo.fetchChildren(of: currentFolderID)
            notebooks = try notebookRepo.fetchAll(folderID: currentFolderID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createNotebook(title: String, coverColor: String) {
        do {
            _ = try notebookRepo.create(title: title,
                                        coverColor: coverColor,
                                        folderID: currentFolderID)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createFolder(title: String) {
        do {
            _ = try folderRepo.create(title: title, parentFolderID: currentFolderID)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ notebook: Notebook) {
        do {
            try notebookRepo.delete(id: notebook.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ folder: Folder) {
        do {
            try folderRepo.delete(id: folder.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 8 dark cover gradient presets stored as "START|END".
    static let coverPalette: [String] = [
        "#2A1F08|#1A1205",  // dark amber
        "#C9A84C|#A87C28",  // full gold
        "#1A1A2A|#0D0D1A",  // dark navy
        "#0A1A18|#051210",  // dark teal
        "#1A0A1A|#0D050D",  // dark plum
        "#1A0808|#0D0404",  // dark crimson
        "#0A1A0A|#051205",  // dark forest
        "#0F0F18|#080810",  // dark slate
    ]
}
```

- [ ] **Step 3: Add FolderRepository to AppContainer**

In `ios/NotesApp/App/AppContainer.swift`, add `folders: FolderRepository` after the `notebooks` property:

```swift
let folders: FolderRepository
```

And in `init(database:)`, add after the `notebooks` line:

```swift
self.folders = FolderRepository(writer: database.writer)
```

- [ ] **Step 4: Run tests**

```bash
cd ios && xcodebuild test -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad (10th generation)' 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/NotesApp/Data/NotebookRepository.swift \
        ios/NotesApp/Features/Library/LibraryViewModel.swift \
        ios/NotesApp/App/AppContainer.swift
git commit -m "feat: LibraryViewModel supports folders; NotebookRepository folder-scoped fetch"
```

---

## Task 5: LibraryView Redesign + FolderView

**Files:**
- Modify: `ios/NotesApp/Features/Library/LibraryView.swift`
- Create: `ios/NotesApp/Features/Library/FolderView.swift`

- [ ] **Step 1: Replace LibraryView.swift entirely**

```swift
// ios/NotesApp/Features/Library/LibraryView.swift
import SwiftUI

struct LibraryView: View {
    @Environment(AppContainer.self) private var container
    /// nil = Library root.  Set by FolderView when drilling in.
    var currentFolder: Folder? = nil

    @State private var viewModel: LibraryViewModel?
    @State private var showingCreationSheet = false
    @State private var newTitle = ""
    @State private var selectedCoverIndex = 0
    @State private var creatingFolder = false
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: AppSpacing.grid)]

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        searchBar
                        if let vm = viewModel {
                            if !vm.folders.isEmpty {
                                sectionHeader("Folders")
                                folderRows(vm: vm)
                            }
                            sectionHeader(currentFolder == nil ? "Notebooks" : "Notebooks — \(vm.notebooks.count)")
                            notebookGrid(vm: vm)
                        }
                    }
                }
            }
            .navigationTitle(currentFolder?.title ?? "My Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if currentFolder == nil {
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gear")
                                .foregroundStyle(AppColors.gold)
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCreationSheet = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 30, height: 30)
                            .background(AppColors.goldGradient)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
                    }
                }
            }
            .sheet(isPresented: $showingCreationSheet) { creationSheet }
            .onAppear {
                if viewModel == nil {
                    viewModel = LibraryViewModel(
                        notebookRepo: container.notebooks,
                        folderRepo: container.folders,
                        currentFolderID: currentFolder?.id
                    )
                }
                viewModel?.reload()
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)
                .font(.system(size: 14))
            Text("Search notebooks…")
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(AppColors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.chip).stroke(AppColors.border, lineWidth: 0.5))
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(AppFonts.sectionHeader)
            .tracking(1.0)
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, AppSpacing.page)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    // MARK: - Folder rows

    private func folderRows(vm: LibraryViewModel) -> some View {
        VStack(spacing: AppSpacing.stack / 2) {
            ForEach(vm.folders) { folder in
                NavigationLink(destination: FolderView(folder: folder, ancestors: ancestorList())) {
                    folderRow(folder)
                }
                .contextMenu {
                    Button("Delete", role: .destructive) { vm.delete(folder) }
                }
            }
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.bottom, 4)
    }

    private func folderRow(_ folder: Folder) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.surface3)
                .frame(width: 30, height: 30)
                .overlay(Text("📁").font(.system(size: 15)))
            Text(folder.title)
                .font(AppFonts.bodyBold)
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            Text("\(subCount(folder)) items")
                .font(AppFonts.caption)
                .foregroundStyle(AppColors.textTertiary)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.border2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(AppColors.border, lineWidth: 0.5))
    }

    // MARK: - Notebook grid

    private func notebookGrid(vm: LibraryViewModel) -> some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.grid) {
            ForEach(vm.notebooks) { notebook in
                NavigationLink(value: notebook) {
                    NotebookCoverTile(notebook: notebook)
                }
                .contextMenu {
                    Button("Delete", role: .destructive) { vm.delete(notebook) }
                }
            }
            // "New" tile inline at end of grid
            Button { showingCreationSheet = true } label {
                newTile
            }
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.bottom, 24)
        .navigationDestination(for: Notebook.self) { notebook in
            NotebookView(notebook: notebook)
        }
    }

    private var newTile: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: AppRadius.card)
                .fill(Color.clear)
                .aspectRatio(3.0/4.0, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.card)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .foregroundStyle(AppColors.border2)
                )
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .light))
                        Text("New").font(AppFonts.micro).fontWeight(.semibold)
                    }
                    .foregroundStyle(AppColors.gold)
                )
            Text(" ").font(AppFonts.micro)  // spacer matching date label height
        }
    }

    // MARK: - Creation sheet

    private var creationSheet: some View {
        NavigationStack {
            ZStack {
                AppColors.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    // Title field
                    TextField("Title", text: $newTitle)
                        .font(AppFonts.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(12)
                        .background(AppColors.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
                        .overlay(RoundedRectangle(cornerRadius: AppRadius.chip).stroke(AppColors.border, lineWidth: 0.5))

                    // Folder/Notebook toggle
                    Toggle(isOn: $creatingFolder) {
                        Text("Create a folder instead")
                            .font(AppFonts.body)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .tint(AppColors.gold)

                    // Cover color swatches (only for notebooks)
                    if !creatingFolder {
                        Text("Cover".uppercased())
                            .font(AppFonts.sectionHeader)
                            .tracking(1)
                            .foregroundStyle(AppColors.textTertiary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(0..<LibraryViewModel.coverPalette.count, id: \.self) { i in
                                    let gradient = LibraryViewModel.coverPalette[i].asCoverGradient
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(gradient)
                                        .frame(width: 44, height: 60)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(i == selectedCoverIndex ? AppColors.gold : Color.clear,
                                                        lineWidth: 2)
                                        )
                                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                                        .onTapGesture { selectedCoverIndex = i }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Spacer()
                }
                .padding(AppSpacing.page)
            }
            .navigationTitle(creatingFolder ? "New Folder" : "New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCreationSheet = false
                        newTitle = ""
                    }
                    .foregroundStyle(AppColors.gold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        if creatingFolder {
                            viewModel?.createFolder(title: title)
                        } else {
                            viewModel?.createNotebook(
                                title: title,
                                coverColor: LibraryViewModel.coverPalette[selectedCoverIndex]
                            )
                        }
                        showingCreationSheet = false
                        newTitle = ""
                        selectedCoverIndex = 0
                        creatingFolder = false
                    }
                    .font(AppFonts.bodyBold)
                    .foregroundStyle(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColors.textTertiary : AppColors.gold)
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .presentationDetents([.medium])
            .presentationBackground(AppColors.bg)
        }
    }

    // MARK: - Helpers

    /// Returns the list of ancestor folders for breadcrumb construction in FolderView.
    private func ancestorList() -> [Folder] {
        guard let f = currentFolder else { return [] }
        // LibraryView at root has no ancestors; FolderView passes its own ancestor list
        return [f]
    }

    private func subCount(_ folder: Folder) -> Int {
        // Placeholder — actual counts loaded lazily inside FolderView
        0
    }
}

// MARK: - Notebook cover tile

private struct NotebookCoverTile: View {
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            coverRect
            Text(notebook.updatedAt.formatted(date: .abbreviated, time: .omitted))
                .font(AppFonts.micro)
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var coverRect: some View {
        RoundedRectangle(cornerRadius: AppRadius.card)
            .fill(notebook.coverColor.asCoverGradient)
            .aspectRatio(3.0/4.0, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                // Subtle ruled lines
                VStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule().fill(Color.white.opacity(0.18)).frame(height: 1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }
            .overlay(alignment: .bottomLeading) {
                Text(notebook.title)
                    .font(AppFonts.caption).fontWeight(.bold)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .padding(10)
            }
            .overlay(alignment: .leading) {
                // Spine shadow
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: 5)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                    .frame(maxHeight: .infinity)
            }
            .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
    }
}
```

- [ ] **Step 2: Create FolderView.swift**

```swift
// ios/NotesApp/Features/Library/FolderView.swift
import SwiftUI

/// Drilled-in view for a specific folder. Reuses LibraryView's layout and view model.
struct FolderView: View {
    let folder: Folder
    /// All ancestor folders from root to the folder ABOVE this one.
    let ancestors: [Folder]

    @Environment(AppContainer.self) private var container
    @State private var viewModel: LibraryViewModel?
    @State private var showingCreationSheet = false
    @State private var newTitle = ""
    @State private var selectedCoverIndex = 0
    @State private var creatingFolder = false

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: AppSpacing.grid)]

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                breadcrumb
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let vm = viewModel {
                            if !vm.folders.isEmpty {
                                sectionHeader("Subfolders")
                                folderRows(vm: vm)
                            }
                            sectionHeader("Notebooks — \(vm.notebooks.count)")
                            notebookGrid(vm: vm)
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.surface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCreationSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(AppColors.goldGradient)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
                }
            }
        }
        .sheet(isPresented: $showingCreationSheet) { creationSheet }
        .onAppear {
            if viewModel == nil {
                viewModel = LibraryViewModel(
                    notebookRepo: container.notebooks,
                    folderRepo: container.folders,
                    currentFolderID: folder.id
                )
            }
            viewModel?.reload()
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // All ancestors are navigation hops already on the stack; tapping
                // uses NavigationStack's built-in pop-to-root — not implemented here,
                // label only shows path for orientation.
                Text("Library")
                    .font(AppFonts.micro)
                    .foregroundStyle(AppColors.textTertiary)
                ForEach(ancestors) { ancestor in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(ancestor.title)
                        .font(AppFonts.micro)
                        .foregroundStyle(AppColors.textTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.textTertiary)
                Text(folder.title)
                    .font(AppFonts.micro).fontWeight(.semibold)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.horizontal, AppSpacing.page)
            .padding(.vertical, 6)
        }
        .background(AppColors.surface.opacity(0.9))
        .overlay(alignment: .bottom) {
            Divider().background(AppColors.border)
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(AppFonts.sectionHeader)
            .tracking(1.0)
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, AppSpacing.page)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    // MARK: - Folder rows

    private func folderRows(vm: LibraryViewModel) -> some View {
        VStack(spacing: AppSpacing.stack / 2) {
            ForEach(vm.folders) { subfolder in
                NavigationLink(destination: FolderView(folder: subfolder,
                                                       ancestors: ancestors + [folder])) {
                    folderRow(subfolder)
                }
                .contextMenu {
                    Button("Delete", role: .destructive) { vm.delete(subfolder) }
                }
            }
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.bottom, 4)
    }

    private func folderRow(_ f: Folder) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.surface3)
                .frame(width: 30, height: 30)
                .overlay(Text("📁").font(.system(size: 15)))
            Text(f.title)
                .font(AppFonts.bodyBold)
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.border2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(AppColors.border, lineWidth: 0.5))
    }

    // MARK: - Notebook grid

    private func notebookGrid(vm: LibraryViewModel) -> some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.grid) {
            ForEach(vm.notebooks) { notebook in
                NavigationLink(value: notebook) {
                    NotebookCoverTileInternal(notebook: notebook)
                }
                .contextMenu {
                    Button("Delete", role: .destructive) { vm.delete(notebook) }
                }
            }
            Button { showingCreationSheet = true } label: {
                newTile
            }
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.bottom, 24)
        .navigationDestination(for: Notebook.self) { notebook in
            NotebookView(notebook: notebook)
        }
    }

    private var newTile: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: AppRadius.card)
                .fill(Color.clear)
                .aspectRatio(3.0/4.0, contentMode: .fit)
                .overlay(RoundedRectangle(cornerRadius: AppRadius.card)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .foregroundStyle(AppColors.border2))
                .overlay(VStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 22, weight: .light))
                    Text("New").font(AppFonts.micro).fontWeight(.semibold)
                }.foregroundStyle(AppColors.gold))
            Text(" ").font(AppFonts.micro)
        }
    }

    // MARK: - Creation sheet

    private var creationSheet: some View {
        NavigationStack {
            ZStack {
                AppColors.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Title", text: $newTitle)
                        .font(AppFonts.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(12)
                        .background(AppColors.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
                        .overlay(RoundedRectangle(cornerRadius: AppRadius.chip).stroke(AppColors.border, lineWidth: 0.5))
                    Toggle(isOn: $creatingFolder) {
                        Text("Create a folder instead").font(AppFonts.body).foregroundStyle(AppColors.textPrimary)
                    }.tint(AppColors.gold)
                    if !creatingFolder {
                        Text("Cover".uppercased()).font(AppFonts.sectionHeader).tracking(1).foregroundStyle(AppColors.textTertiary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(0..<LibraryViewModel.coverPalette.count, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LibraryViewModel.coverPalette[i].asCoverGradient)
                                        .frame(width: 44, height: 60)
                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                            .stroke(i == selectedCoverIndex ? AppColors.gold : Color.clear, lineWidth: 2))
                                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                                        .onTapGesture { selectedCoverIndex = i }
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                    Spacer()
                }.padding(AppSpacing.page)
            }
            .navigationTitle(creatingFolder ? "New Folder" : "New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCreationSheet = false; newTitle = "" }
                        .foregroundStyle(AppColors.gold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        if creatingFolder {
                            viewModel?.createFolder(title: title)
                        } else {
                            viewModel?.createNotebook(title: title, coverColor: LibraryViewModel.coverPalette[selectedCoverIndex])
                        }
                        showingCreationSheet = false; newTitle = ""; selectedCoverIndex = 0; creatingFolder = false
                    }
                    .font(AppFonts.bodyBold)
                    .foregroundStyle(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColors.textTertiary : AppColors.gold)
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .presentationDetents([.medium])
            .presentationBackground(AppColors.bg)
        }
    }
}

// Internal copy of NotebookCoverTile for use in FolderView without access to the private struct in LibraryView.
private struct NotebookCoverTileInternal: View {
    let notebook: Notebook
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: AppRadius.card)
                .fill(notebook.coverColor.asCoverGradient)
                .aspectRatio(3.0/4.0, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    VStack(spacing: 6) {
                        ForEach(0..<4, id: \.self) { _ in
                            Capsule().fill(Color.white.opacity(0.18)).frame(height: 1)
                        }
                    }.padding(.horizontal, 10).padding(.top, 10)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(notebook.title)
                        .font(AppFonts.caption).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .padding(10)
                }
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.black.opacity(0.2)).frame(width: 5)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                        .frame(maxHeight: .infinity)
                }
                .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
            Text(notebook.updatedAt.formatted(date: .abbreviated, time: .omitted))
                .font(AppFonts.micro).foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
```

- [ ] **Step 3: Build and check for compile errors**

```bash
cd ios && xcodebuild build -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad (10th generation)' 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 4: Commit**

```bash
git add ios/NotesApp/Features/Library/LibraryView.swift ios/NotesApp/Features/Library/FolderView.swift
git commit -m "feat: LibraryView + FolderView — gold/black redesign with nested folder support"
```

---

## Task 6: NotebookView — Two-Row Toolbar + Dark Chrome

**Files:**
- Modify: `ios/NotesApp/Features/Notebook/NotebookView.swift`

- [ ] **Step 1: Add tool/color state and rewrite the view**

At the top of `NotebookView`, add these `@State` properties after the existing ones:

```swift
// Tool picker state (replaces PKToolPicker)
@State private var activePenType: PKInkingTool.InkType = .pen
@State private var activeColor: Color = AppColors.textPrimary
```

Replace the `toolbar` modifier and `mainContent` computed property. The full file is long — here are the specific sections to change:

**Replace `.toolbar { ... }` block** (removes all existing toolbar items):

```swift
// No .toolbar modifier — toolbar lives in the action bar row instead
```

**Replace `mainContent` computed property:**

```swift
private var mainContent: some View {
    VStack(spacing: 0) {
        // Row 1: Navigation bar chrome is handled by SwiftUI navigationBar.
        // Row 2: Action bar
        actionBar
        // AI hint banner
        if aiSelectionMode {
            aiBanner
        }
        // Routing badge (non-blocking, only when degraded)
        else if container.aiRouter.activeLabel == "groq" {
            routingBadge(text: "Groq fallback")
        } else if !container.aiRouter.isConfigured {
            routingBadge(text: "AI offline — configure in Settings")
        }
        HStack(spacing: 0) {
            if let vm = viewModel {
                pageStrip(vm: vm)
                    .frame(width: 88)
                    .background(AppColors.surface)
                Divider().background(AppColors.border)
                canvasArea(vm: vm)
            } else {
                ProgressView().tint(AppColors.gold)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
```

**Add `actionBar` computed property:**

```swift
private var actionBar: some View {
    HStack(spacing: 3) {
        // Undo / Redo
        abBtn(icon: "arrow.uturn.backward") { /* TODO: undo via PKCanvasView */ }
        abBtn(icon: "arrow.uturn.forward")  { /* TODO: redo via PKCanvasView */ }
        abSep

        // Tools
        abToolBtn(icon: "pencil.tip",   penType: .pen)
        abToolBtn(icon: "pencil",        penType: .pencil)
        abToolBtn(icon: "square.and.pencil", penType: nil) // eraser handled separately
        abBtn(icon: "lasso") { /* lasso — set via PKLassoTool */ }
        abSep

        // Colors
        ForEach([AppColors.textPrimary, AppColors.gold,
                 Color(hex: "#5C6BC0")!, Color(hex: "#26A69A")!], id: \.self) { color in
            colorDot(color)
        }
        abSep

        // AI + Chat
        abBtn(icon: "sparkles", isActive: aiSelectionMode) {
            aiSelectionMode = true
        }
        abBtn(icon: "bubble.left.and.bubble.right", isActive: showingChat) {
            showingChat.toggle()
        }

        Spacer()

        // Page actions
        if let vm = viewModel {
            Menu {
                Button("Line")  { vm.addPage(template: .line) }
                Button("Grid")  { vm.addPage(template: .grid) }
                Button("Blank") { vm.addPage(template: .blank) }
            } label: {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 30, height: 30)
            }
            abBtn(icon: "trash", role: .destructive) { vm.deleteCurrentPage() }
        }
    }
    .padding(.horizontal, 12)
    .frame(height: 40)
    .background(AppColors.surface2)
    .overlay(alignment: .bottom) { Divider().background(AppColors.border) }
}

@ViewBuilder
private func abBtn(icon: String,
                   isActive: Bool = false,
                   role: ButtonRole? = nil,
                   action: @escaping () -> Void) -> some View {
    Button(role: role, action: action) {
        Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundStyle(isActive ? AppColors.gold : AppColors.textSecondary)
            .frame(width: 30, height: 30)
            .background(isActive ? AppColors.gold.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

@ViewBuilder
private func abToolBtn(icon: String, penType: PKInkingTool.InkType?) -> some View {
    let isActive = penType != nil && activePenType == penType
    Button {
        if let pt = penType {
            activePenType = pt
        }
    } label: {
        Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundStyle(isActive ? .black : AppColors.textSecondary)
            .frame(width: 30, height: 30)
            .background(isActive ? AppColors.goldGradient : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

@ViewBuilder
private func colorDot(_ color: Color) -> some View {
    let isActive = activeColor == color
    Circle()
        .fill(color)
        .frame(width: 14, height: 14)
        .overlay(Circle().stroke(isActive ? AppColors.gold : Color.clear, lineWidth: 2).padding(-2))
        .onTapGesture { activeColor = color }
}

private var abSep: some View {
    Rectangle()
        .fill(AppColors.border2)
        .frame(width: 1, height: 20)
        .padding(.horizontal, 4)
}

private var aiBanner: some View {
    HStack {
        Image(systemName: "sparkles").foregroundStyle(.black)
        Text("Drag with finger to select a region for AI")
            .font(AppFonts.caption).fontWeight(.semibold)
            .foregroundStyle(.black)
        Spacer()
        Button("Cancel") { aiSelectionMode = false }
            .font(AppFonts.caption)
            .foregroundStyle(.black.opacity(0.7))
    }
    .padding(.horizontal, 14)
    .frame(height: 36)
    .background(AppColors.goldGradient)
}

private func routingBadge(text: String) -> some View {
    HStack {
        Spacer()
        Text(text)
            .font(AppFonts.micro).fontWeight(.semibold)
            .foregroundStyle(AppColors.gold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppColors.gold.opacity(0.1))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AppColors.gold.opacity(0.2), lineWidth: 0.5))
        Spacer()
    }
    .padding(.vertical, 4)
    .background(AppColors.surface)
}
```

**Replace `pageStripThumb` to use dark theme + gold ring:**

```swift
private func pageStripThumb(page: Page, isSelected: Bool) -> some View {
    VStack(spacing: 3) {
        Group {
            if let blob = page.thumbnailBlob, let img = UIImage(data: blob) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                Rectangle().fill(AppColors.surface3)
            }
        }
        .aspectRatio(3.0/4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.thumb))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.thumb)
                .stroke(isSelected ? AppColors.gold : AppColors.border,
                        lineWidth: isSelected ? 2 : 0.5)
        )
        .shadow(color: isSelected ? AppColors.gold.opacity(0.25) : .black.opacity(0.3),
                radius: isSelected ? 4 : 2, y: 1)
        Text("\(page.pageIndex + 1)")
            .font(AppFonts.micro)
            .foregroundStyle(AppColors.textTertiary)
    }
}
```

**Update `.navigationBarTitleDisplayMode` and toolbar background:**

Add these modifiers to the view (after `.navigationBarTitleDisplayMode(.inline)`):

```swift
.toolbarBackground(AppColors.surface, for: .navigationBar)
.toolbarColorScheme(.dark, for: .navigationBar)
```

And update the back button parent label — in the existing `.navigationTitle(notebook.title)` chain, add:

```swift
.navigationBarTitleDisplayMode(.inline)
```

- [ ] **Step 2: Build**

```bash
cd ios && xcodebuild build -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad (10th generation)' 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 3: Commit**

```bash
git add ios/NotesApp/Features/Notebook/NotebookView.swift
git commit -m "feat: NotebookView two-row toolbar — action bar with tools, colors, AI/chat, gold ring page strip"
```

---

## Task 7: CanvasView — Remove PKToolPicker, Add Tool Binding, Gold Selection

**Files:**
- Modify: `ios/NotesApp/Canvas/CanvasView.swift`

- [ ] **Step 1: Add `activeTool` binding to CanvasView struct**

Add this property after `onAIRegionSelected`:

```swift
/// The active drawing tool. Driven by the action bar. Setting this replaces PKToolPicker.
var activeTool: PKTool
```

Update the struct signature to accept the tool. The caller (`NotebookView.canvasArea`) will pass a computed `PKTool` based on `activePenType` and `activeColor`.

- [ ] **Step 2: Remove PKToolPicker setup from `makeUIView`**

Delete these 6 lines in `makeUIView` (inside the `DispatchQueue.main.async` block):

```swift
// DELETE:
if let window = canvas.window,
   let picker = PKToolPicker.shared(for: window) {
    picker.setVisible(true, forFirstResponder: canvas)
    picker.addObserver(canvas)
    canvas.becomeFirstResponder()
}
```

Replace with just:

```swift
canvas.tool = activeTool
```

- [ ] **Step 3: Apply tool in `updateUIView`**

At the end of `updateUIView`, add:

```swift
// Sync active tool from action bar binding
if canvas.tool !== activeTool {
    canvas.tool = activeTool
}
```

- [ ] **Step 4: Change AI selection highlight to gold**

In `handleAIRegionPan`, replace the `view.backgroundColor` and `view.layer.borderColor` lines:

```swift
// BEFORE:
view.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
view.layer.borderColor = UIColor.systemBlue.cgColor

// AFTER:
view.backgroundColor = UIColor(AppColors.gold).withAlphaComponent(0.08)
view.layer.borderColor = UIColor(AppColors.gold).cgColor
view.layer.borderWidth = 2
// Corner handles
for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
               CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)] {
    let handle = UIView(frame: CGRect(x: -4, y: -4, width: 8, height: 8))
    handle.backgroundColor = UIColor(AppColors.gold)
    handle.layer.cornerRadius = 2
    handle.tag = 999
    view.addSubview(handle)
    handle.autoresizingMask = corner.x == 0 ? [.flexibleRightMargin] : [.flexibleLeftMargin]
}
```

- [ ] **Step 5: Update `NotebookView.canvasArea` to pass the active tool**

In `NotebookView`, compute the `PKTool` from state and pass it to `CanvasView`:

```swift
// Add this computed property to NotebookView:
private var currentPKTool: PKTool {
    let uiColor = UIColor(activeColor)
    switch activePenType {
    case .pen:     return PKInkingTool(.pen,     color: uiColor, width: 2)
    case .pencil:  return PKInkingTool(.pencil,  color: uiColor, width: 2)
    case .marker:  return PKInkingTool(.marker,  color: uiColor, width: 10)
    default:       return PKInkingTool(.pen,     color: uiColor, width: 2)
    }
}
```

And update the `CanvasView(...)` call inside `canvasArea` to add:

```swift
activeTool: currentPKTool,
```

- [ ] **Step 6: Build and run**

```bash
cd ios && xcodebuild build -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad (10th generation)' 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 7: Commit**

```bash
git add ios/NotesApp/Canvas/CanvasView.swift ios/NotesApp/Features/Notebook/NotebookView.swift
git commit -m "feat: remove PKToolPicker — tool driven by action bar binding; gold AI selection rect"
```

---

## Task 8: ChatPanelView — Bottom Sheet

**Files:**
- Modify: `ios/NotesApp/Features/Chat/ChatPanelView.swift`
- Modify: `ios/NotesApp/Features/Notebook/NotebookView.swift`

- [ ] **Step 1: Rewrite ChatPanelView as a self-contained bottom sheet**

Replace the full content of `ios/NotesApp/Features/Chat/ChatPanelView.swift`:

```swift
// ios/NotesApp/Features/Chat/ChatPanelView.swift
import SwiftUI

struct ChatPanelView: View {
    @Bindable var viewModel: ChatViewModel
    let onClose: () -> Void

    @State private var panelHeight: CGFloat = 320
    @GestureState private var dragOffset: CGFloat = 0

    private let minHeight: CGFloat = 280
    private let maxHeight: CGFloat = UIScreen.main.bounds.height * 0.85
    private let handleHeight: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            Divider().background(AppColors.border)
            messages
            Divider().background(AppColors.border)
            inputBar
        }
        .frame(height: max(minHeight, min(maxHeight, panelHeight + dragOffset)))
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 20, y: -4)
        .onAppear { viewModel.load() }
        .alert("Chat error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        ), actions: { Button("OK") {} },
           message: { Text(viewModel.errorMessage ?? "") })
    }

    // MARK: - Handle

    private var handle: some View {
        VStack {
            Capsule()
                .fill(AppColors.border2)
                .frame(width: 36, height: 4)
        }
        .frame(height: handleHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = -value.translation.height
                }
                .onEnded { value in
                    panelHeight = max(minHeight, min(maxHeight,
                                                     panelHeight - value.translation.height))
                }
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Chat")
                    .font(AppFonts.bodyBold)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(AppColors.surface3)
                        .clipShape(Circle())
                }
            }
            // Scope toggle
            HStack(spacing: 2) {
                scopePill(label: "This page", scope: .page)
                scopePill(label: "Notebook",  scope: .notebook)
            }
            .padding(2)
            .background(AppColors.bg)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.chip)
                .stroke(AppColors.border, lineWidth: 0.5))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func scopePill(label: String, scope: ChatScope) -> some View {
        let isActive = viewModel.scope == scope
        Button { viewModel.scope = scope } label: {
            Text(label)
                .font(AppFonts.caption).fontWeight(.semibold)
                .foregroundStyle(isActive ? .black : AppColors.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isActive ? AppColors.goldGradient
                            : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip - 2))
        }
    }

    // MARK: - Messages

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if viewModel.messages.isEmpty {
                        welcomeChip
                    }
                    ForEach(viewModel.messages) { msg in
                        bubble(msg: msg).id(msg.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var welcomeChip: some View {
        Text("I can see your notes — ask me anything ✦")
            .font(AppFonts.caption)
            .foregroundStyle(AppColors.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AppColors.surface2)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.chip)
                .stroke(AppColors.border, lineWidth: 0.5))
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func bubble(msg: AIMessage) -> some View {
        let isUser = msg.role == .user
        HStack {
            if isUser { Spacer(minLength: 40) }
            bubbleContent(msg: msg, isUser: isUser)
            if !isUser { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private func bubbleContent(msg: AIMessage, isUser: Bool) -> some View {
        if isUser {
            Text(msg.text)
                .font(AppFonts.body)
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.goldGradient)
                .clipShape(
                    RoundedRectangle(cornerRadius: 14)
                        .union(other: RoundedRectangle(cornerRadius: 14)) // bottom-right tight
                )
                .clipShape(ChatBubbleShape(isUser: true))
        } else if containsMath(msg.text) {
            MathWebView(content: msg.text)
                .frame(minHeight: 80, maxHeight: 400)
                .background(AppColors.surface2)
                .clipShape(ChatBubbleShape(isUser: false))
                .overlay(ChatBubbleShape(isUser: false)
                    .stroke(AppColors.border, lineWidth: 0.5))
        } else {
            Text(markdownAttr(msg.text))
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.surface2)
                .clipShape(ChatBubbleShape(isUser: false))
                .overlay(ChatBubbleShape(isUser: false)
                    .stroke(AppColors.border, lineWidth: 0.5))
        }
    }

    private func containsMath(_ text: String) -> Bool {
        text.contains("$") || text.contains("\\")
    }

    private func markdownAttr(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            MicButton { audio in Task { await viewModel.transcribe(audio: audio) } }
                .frame(width: 32, height: 32)
                .background(AppColors.surface2)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.chip)
                    .stroke(AppColors.border, lineWidth: 0.5))
            TextField("Ask anything…", text: $viewModel.inputText, axis: .vertical)
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppColors.surface2)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.chip)
                    .stroke(AppColors.border, lineWidth: 0.5))
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(
                        viewModel.isSending || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? AppColors.surface3.asGradient
                        : AppColors.goldGradient
                    )
                    .clipShape(Circle())
                    .shadow(color: AppColors.gold.opacity(0.35), radius: 4, y: 2)
            }
            .disabled(viewModel.isSending || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppColors.surface)
    }
}

// MARK: - Chat bubble shape (rounded with one tight corner)

private struct ChatBubbleShape: Shape {
    let isUser: Bool
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 14
        let tight: CGFloat = 4
        var p = Path()
        if isUser {
            // tight corner: bottom-right
            p.addRoundedRect(in: rect, cornerRadii: .init(
                topLeading: r, bottomLeading: r, bottomTrailing: tight, topTrailing: r))
        } else {
            // tight corner: bottom-left
            p.addRoundedRect(in: rect, cornerRadii: .init(
                topLeading: r, bottomLeading: tight, bottomTrailing: r, topTrailing: r))
        }
        return p
    }
}

// MARK: - Extension helpers

private extension Color {
    var asGradient: LinearGradient {
        LinearGradient(colors: [self, self], startPoint: .top, endPoint: .bottom)
    }
}
```

- [ ] **Step 2: Update NotebookView to use bottom sheet overlay instead of side panel**

In `NotebookView.body`, replace the `HStack(spacing: 0)` that wraps `mainContent` + chat panel:

```swift
// BEFORE:
var body: some View {
    HStack(spacing: 0) {
        mainContent
        if showingChat, let cvm = chatVM {
            Divider()
            ChatPanelView(viewModel: cvm, onClose: { showingChat = false })
                .transition(.move(edge: .trailing))
        }
    }

// AFTER:
var body: some View {
    ZStack(alignment: .bottom) {
        mainContent
        if showingChat, let cvm = chatVM {
            ChatPanelView(viewModel: cvm, onClose: { showingChat = false })
                .transition(.move(edge: .bottom))
                .zIndex(10)
        }
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showingChat)
```

- [ ] **Step 3: Build**

```bash
cd ios && xcodebuild build -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad (10th generation)' 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Step 4: Commit**

```bash
git add ios/NotesApp/Features/Chat/ChatPanelView.swift ios/NotesApp/Features/Notebook/NotebookView.swift
git commit -m "feat: ChatPanelView as bottom sheet — gold bubbles, drag handle, scope toggle"
```

---

## Task 9: Dark Styling Pass — Transform, Lasso, Settings, MathWebView, App Theme

**Files:**
- Modify: `ios/NotesApp/Features/Notebook/TransformResultView.swift`
- Modify: `ios/NotesApp/Features/Notebook/LassoMenuView.swift`
- Modify: `ios/NotesApp/Features/Settings/SettingsView.swift`
- Modify: `ios/NotesApp/AI/MathWebView.swift`
- Modify: `ios/NotesApp/App/NotesAppApp.swift`

- [ ] **Step 1: Update TransformResultView**

Replace the full content:

```swift
// ios/NotesApp/Features/Notebook/TransformResultView.swift
import SwiftUI

struct TransformResultView: View {
    let response: TransformResponse
    let onInsertBelow: (String) -> Void
    let onReplace: (String) -> Void
    let onDismiss: () -> Void
    var onSendToChat: ((String) -> Void)? = nil

    var body: some View {
        ZStack {
            AppColors.surface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("AI result")
                        .font(AppFonts.bodyBold)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text(response.modelUsed)
                        .font(AppFonts.micro)
                        .foregroundStyle(AppColors.textTertiary)
                }
                MathWebView(content: payloadText)
                    .frame(minHeight: 120, maxHeight: 300)
                    .background(AppColors.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))

                HStack(spacing: 10) {
                    if let sendToChat = onSendToChat {
                        Button("Ask in Chat") { sendToChat(payloadText) }
                            .font(AppFonts.caption).fontWeight(.semibold)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(AppColors.goldGradient)
                            .clipShape(Capsule())
                    }
                    Button("Insert below") { onInsertBelow(payloadText) }
                        .font(AppFonts.caption).fontWeight(.semibold)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(AppColors.surface2)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppColors.border, lineWidth: 0.5))
                    Button("Replace") { onReplace(payloadText) }
                        .font(AppFonts.caption).fontWeight(.semibold)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(AppColors.surface2)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppColors.border, lineWidth: 0.5))
                    Spacer()
                    Button("Dismiss") { onDismiss() }
                        .font(AppFonts.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(16)
        }
        .frame(width: 420)
    }

    private var payloadText: String {
        response.text ?? response.markdown ?? response.svg ?? ""
    }
}
```

- [ ] **Step 2: Update LassoMenuView**

Replace the full content:

```swift
// ios/NotesApp/Features/Notebook/LassoMenuView.swift
import SwiftUI

struct LassoMenuView: View {
    let onSelect: (AIAction) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(.cleanup,   "Clean up handwriting", "wand.and.stars")
            row(.typedText, "Convert to typed text", "textformat")
            Divider().background(AppColors.border)
            row(.math,      "Math mode",      "function")
            row(.physics,   "Physics mode",   "atom")
            row(.chemistry, "Chemistry mode", "flask")
            Divider().background(AppColors.border)
            row(.explain,   "Explain this",   "lightbulb")
            row(.list,      "Turn into list", "list.bullet")
        }
        .padding(.vertical, 8)
        .frame(width: 260)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }

    private func row(_ action: AIAction, _ title: String, _ icon: String) -> some View {
        Button {
            onSelect(action)
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(AppColors.gold)
                Text(title)
                    .font(AppFonts.body)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Update SettingsView**

Replace the `Form { ... }` with a styled dark list. Replace full content of `ios/NotesApp/Features/Settings/SettingsView.swift`:

```swift
// ios/NotesApp/Features/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    @AppStorage("defaultTemplate") private var defaultTemplateRaw: String = PageTemplateKind.line.rawValue
    @AppStorage("voiceLanguage")   private var voiceLanguage: String = "auto"

    @State private var pcURL: String = ""
    @State private var keysText: String = ""
    @State private var savedMessage: String?
    @State private var syncStatus: String = "idle"

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()
            List {
                settingsSection("Paper") {
                    Picker("Default template", selection: $defaultTemplateRaw) {
                        Text("Line").tag(PageTemplateKind.line.rawValue)
                        Text("Grid").tag(PageTemplateKind.grid.rawValue)
                        Text("Blank").tag(PageTemplateKind.blank.rawValue)
                    }
                    .tint(AppColors.gold)
                }
                settingsSection("AI routing") {
                    HStack {
                        Text("Active").font(AppFonts.body).foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Text(container.aiRouter.activeLabel)
                            .font(AppFonts.caption).fontWeight(.semibold)
                            .foregroundStyle(AppColors.gold)
                    }
                }
                settingsSection("PC companion server") {
                    TextField("http://192.168.1.10:8000", text: $pcURL)
                        .font(AppFonts.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                settingsSection("Groq API keys (one per line)") {
                    TextEditor(text: $keysText)
                        .frame(minHeight: 100)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                settingsSection("Voice") {
                    Picker("Language", selection: $voiceLanguage) {
                        Text("Auto detect").tag("auto")
                        Text("English").tag("en")
                        Text("Indonesian").tag("id")
                        Text("Code-switching (id+en)").tag("id,en")
                    }
                    .tint(AppColors.gold)
                }
                settingsSection("") {
                    Button("Save AI configuration") { saveConfig() }
                        .font(AppFonts.bodyBold)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppColors.goldGradient)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
                    if let msg = savedMessage {
                        Text(msg)
                            .font(AppFonts.caption)
                            .foregroundStyle(msg.contains("failed") ? .red : AppColors.gold)
                    }
                }
                settingsSection("Sync") {
                    HStack {
                        Text("Status").font(AppFonts.body).foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Text(syncStatus).font(AppFonts.caption).foregroundStyle(AppColors.textTertiary)
                    }
                    Button("Sync now") {
                        Task {
                            await container.syncScheduler?.syncNow()
                            syncStatus = container.syncScheduler?.status ?? "idle"
                        }
                    }
                    .font(AppFonts.body)
                    .foregroundStyle(container.syncClient == nil ? AppColors.textTertiary : AppColors.gold)
                    .disabled(container.syncClient == nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.surface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { loadConfig() }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
        } header: {
            Text(title.uppercased())
                .font(AppFonts.sectionHeader)
                .tracking(0.8)
                .foregroundStyle(AppColors.textTertiary)
        }
        .listRowBackground(AppColors.surface2)
        .listRowSeparatorTint(AppColors.border)
    }

    private func loadConfig() {
        pcURL = (try? KeychainStore.shared.getPCServerURL()) ?? ""
        let keys = (try? KeychainStore.shared.getGroqKeys()) ?? []
        keysText = keys.joined(separator: "\n")
        syncStatus = container.syncScheduler?.status ?? "not configured"
    }

    private func saveConfig() {
        do {
            try KeychainStore.shared.setPCServerURL(pcURL)
            let keys = keysText
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            try KeychainStore.shared.setGroqKeys(keys)
            container.reloadAI()
            savedMessage = "Saved — \(container.aiRouter.activeLabel)"
        } catch {
            savedMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 4: Update MathWebView dark mode colors**

In `ios/NotesApp/AI/MathWebView.swift`, replace the `<style>` block inside `html()`:

```swift
// Replace the existing <style>...</style> block with:
<style>
html,body{background:transparent;margin:0}
body{font-family:-apple-system,sans-serif;font-size:16px;
     padding:8px 12px;word-wrap:break-word;visibility:hidden;
     color:#F0EDE6}
pre{background:#1C1C1E;padding:8px;border-radius:6px;overflow-x:auto;
    border:1px solid #2A2A2E}
code{font-family:menlo,monospace;font-size:.88em;background:#1C1C1E;
     padding:1px 4px;border-radius:3px;color:#C9A84C}
pre code{background:none;padding:0;color:#F0EDE6}
.katex-display{overflow-x:auto;overflow-y:hidden}
.katex{color:#F0EDE6}
</style>
```

Note: remove the `@media (prefers-color-scheme: dark)` block — the app is always dark now, so we apply the dark styles unconditionally.

- [ ] **Step 5: Force dark theme in NotesAppApp.swift**

Replace the full content of `ios/NotesApp/App/NotesAppApp.swift`:

```swift
// ios/NotesApp/App/NotesAppApp.swift
import SwiftUI

@main
struct NotesAppApp: App {
    @State private var container = AppContainer.makeDefault()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(container)
                .preferredColorScheme(.dark)
        }
    }
}
```

- [ ] **Step 6: Build + run all tests**

```bash
cd ios && xcodebuild test -scheme NotesApp -destination 'platform=iOS Simulator,name=iPad (10th generation)' 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add ios/NotesApp/Features/Notebook/TransformResultView.swift \
        ios/NotesApp/Features/Notebook/LassoMenuView.swift \
        ios/NotesApp/Features/Settings/SettingsView.swift \
        ios/NotesApp/AI/MathWebView.swift \
        ios/NotesApp/App/NotesAppApp.swift
git commit -m "feat: dark styling pass — TransformResult, LassoMenu, Settings, MathWebView, force dark theme"
```

---

## Smoke Test Checklist

After sideloading the IPA, run through these manually:

**Library**
- [ ] App launches to dark Library (black background, gold `+` button)
- [ ] Create a notebook — creation sheet appears dark, 8 cover swatches visible
- [ ] Notebook cover renders gradient correctly
- [ ] Create a folder — "Create a folder instead" toggle works
- [ ] Folder row appears with chevron, tap drills in
- [ ] Nested folder: create a subfolder inside a folder, breadcrumb shows path
- [ ] Long-press notebook → Delete removes it
- [ ] Long-press folder → Delete removes it and all children

**Notebook / Canvas**
- [ ] Opens with dark nav bar and action bar (gold `+` button)
- [ ] Pen, pencil, eraser icons in action bar — active tool shows gold fill
- [ ] 4 color dots — tapping changes ink color on canvas
- [ ] Undo/redo buttons present
- [ ] Page strip: dark background, gold ring on selected thumb
- [ ] Add page menu works, strip updates
- [ ] Canvas paper is cream/white — ink is legible

**AI selection**
- [ ] Sparkles button → gold banner appears at top
- [ ] Finger drag draws gold selection rectangle
- [ ] Cancel button dismisses banner, clears rect
- [ ] After drag → lasso menu popover appears (dark, gold icons)

**Chat panel**
- [ ] Chat button toggles bottom sheet (slides up)
- [ ] Drag handle resizes panel
- [ ] User bubbles gold, bot bubbles dark surface
- [ ] Scope toggle (This page / Notebook) — active tab gold fill
- [ ] Mic button present, send button gold
- [ ] Close button dismisses sheet

**Settings**
- [ ] Opens dark inset grouped list
- [ ] Pickers tinted gold
- [ ] Save button gold gradient
- [ ] Sync status visible

**MathWebView**
- [ ] Send a math question → LaTeX renders in cream text on dark background
- [ ] Transform result sheet dark with gold "Ask in Chat" button
