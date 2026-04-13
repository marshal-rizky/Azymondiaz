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
