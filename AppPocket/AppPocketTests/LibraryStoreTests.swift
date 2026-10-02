//
//  LibraryStoreTests.swift
//  AppPocketTests
//
//  Category lifecycle, membership and persistence.
//

import XCTest
@testable import AppPocket

final class LibraryStoreTests: XCTestCase {

    // MARK: - Creating

    @MainActor
    func testCreateCategoryStoresNameSymbolColourAndMembers() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        let category = try store.createCategory(
            name: "Development",
            symbolName: "hammer.fill",
            colorHex: "#0A84FF",
            appIDs: ["com.apple.dt.Xcode"]
        )

        XCTAssertEqual(store.categories.count, 1)
        XCTAssertEqual(category.name, "Development")
        XCTAssertEqual(category.symbolName, "hammer.fill")
        XCTAssertEqual(category.colorHex, "#0A84FF")
        XCTAssertEqual(store.appIDs(inCategory: category.id), ["com.apple.dt.Xcode"])
    }

    @MainActor
    func testCreateCategoryRejectsEmptyName() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }

        XCTAssertThrowsError(try harness.store.createCategory(name: "   ")) { error in
            XCTAssertEqual(error as? LibraryError, .emptyName)
        }
        XCTAssertTrue(harness.store.categories.isEmpty)
    }

    @MainActor
    func testCreateCategoryRejectsDuplicateNameIgnoringCaseAndDiacritics() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        try store.createCategory(name: "Games")

        XCTAssertThrowsError(try store.createCategory(name: "games")) { error in
            XCTAssertEqual(error as? LibraryError, .duplicateName("games"))
        }
        XCTAssertEqual(store.categories.count, 1)
    }

    @MainActor
    func testCreateCategoryCollapsesInternalWhitespace() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }

        let category = try harness.store.createCategory(name: "  My    Tools  ")
        XCTAssertEqual(category.name, "My Tools")
    }

    @MainActor
    func testCreateCategoryDropsDuplicateMemberIDs() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }

        let category = try harness.store.createCategory(
            name: "Tools",
            appIDs: ["a", "b", "a"]
        )
        XCTAssertEqual(category.appIDs, ["a", "b"])
    }

    // MARK: - Editing

    @MainActor
    func testUpdateCategoryKeepsItsOwnName() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        let category = try store.createCategory(name: "Games")
        // Renaming to its own name must not trip the duplicate check.
        XCTAssertNoThrow(
            try store.updateCategory(
                id: category.id,
                name: "Games",
                symbolName: "gamecontroller.fill",
                colorHex: "#30D158",
                appIDs: ["x"]
            )
        )
        XCTAssertEqual(store.category(id: category.id)?.symbolName, "gamecontroller.fill")
        XCTAssertEqual(store.appIDs(inCategory: category.id), ["x"])
    }

    @MainActor
    func testUpdateCategoryRejectsNameTakenByAnotherCategory() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        let first = try store.createCategory(name: "Games")
        let second = try store.createCategory(name: "Work")

        XCTAssertThrowsError(
            try store.updateCategory(
                id: second.id,
                name: "Games",
                symbolName: "folder.fill",
                colorHex: "#0A84FF",
                appIDs: []
            )
        )
        XCTAssertEqual(store.category(id: second.id)?.name, "Work")
        XCTAssertEqual(store.category(id: first.id)?.name, "Games")
    }

    @MainActor
    func testDeleteCategoryRemovesItAndLeavesOthersAlone() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        let keep = try store.createCategory(name: "Keep")
        let drop = try store.createCategory(name: "Drop")

        store.deleteCategory(id: drop.id)

        XCTAssertEqual(store.categories.map(\.id), [keep.id])
    }

    @MainActor
    func testDuplicateCategoryInsertsBesideTheOriginalWithAFreeName() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        let original = try store.createCategory(name: "Games", appIDs: ["a", "b"])
        store.duplicateCategory(id: original.id)

        XCTAssertEqual(store.categories.count, 2)
        XCTAssertEqual(store.categories[0].id, original.id)
        XCTAssertEqual(store.categories[1].name, "Games 2")
        XCTAssertEqual(store.categories[1].appIDs, ["a", "b"])
        XCTAssertNotEqual(store.categories[1].id, original.id)
    }

    // MARK: - Membership

    @MainActor
    func testAddIsIdempotentAndAppendsInOrder() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store
        let category = try store.createCategory(name: "Tools", appIDs: ["a"])

        store.add(appIDs: ["b", "a", "c"], toCategory: category.id)

        XCTAssertEqual(store.appIDs(inCategory: category.id), ["a", "b", "c"])
    }

    @MainActor
    func testAnAppCanBelongToSeveralCategories() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        let work = try store.createCategory(name: "Work", appIDs: ["app"])
        let tools = try store.createCategory(name: "Tools", appIDs: ["app"])

        XCTAssertEqual(store.categoryIDs(containing: "app"), [work.id, tools.id])
    }

    @MainActor
    func testToggleAddsThenRemoves() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store
        let category = try store.createCategory(name: "Tools")

        store.toggle(appID: "x", inCategory: category.id)
        XCTAssertEqual(store.appIDs(inCategory: category.id), ["x"])

        store.toggle(appID: "x", inCategory: category.id)
        XCTAssertTrue(store.appIDs(inCategory: category.id).isEmpty)
    }

    @MainActor
    func testRemoveFromAllCategoriesTouchesEveryCategory() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        let first = try store.createCategory(name: "One", appIDs: ["a", "b"])
        let second = try store.createCategory(name: "Two", appIDs: ["b", "c"])

        store.removeFromAllCategories(appIDs: ["b"])

        XCTAssertEqual(store.appIDs(inCategory: first.id), ["a"])
        XCTAssertEqual(store.appIDs(inCategory: second.id), ["c"])
    }

    @MainActor
    func testMoveAppReordersWithinACategory() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store
        let category = try store.createCategory(name: "Tools", appIDs: ["a", "b", "c"])

        store.moveApp(id: "c", toIndex: 0, inCategory: category.id)

        XCTAssertEqual(store.appIDs(inCategory: category.id), ["c", "a", "b"])
    }

    @MainActor
    func testMoveCategoryBeforeAnother() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        let a = try store.createCategory(name: "A")
        let b = try store.createCategory(name: "B")
        let c = try store.createCategory(name: "C")

        store.moveCategory(id: c.id, before: a.id)

        XCTAssertEqual(store.categories.map(\.id), [c.id, a.id, b.id])
    }

    // MARK: - Hidden apps

    @MainActor
    func testHideAndUnhide() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        store.setHidden(true, appIDs: ["a"])
        XCTAssertTrue(store.isHidden("a"))
        XCTAssertEqual(store.hiddenAppIDs, ["a"])

        // Hiding twice must not duplicate the entry.
        store.setHidden(true, appIDs: ["a"])
        XCTAssertEqual(store.hiddenAppIDs.count, 1)

        store.setHidden(false, appIDs: ["a"])
        XCTAssertFalse(store.isHidden("a"))
    }

    @MainActor
    func testSelectedAreAllHiddenReflectsMixedSelection() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        store.setHidden(true, appIDs: ["a", "b"])

        XCTAssertTrue(store.selectedAreAllHidden(["a", "b"]))
        XCTAssertFalse(store.selectedAreAllHidden(["a", "c"]))
        XCTAssertFalse(store.selectedAreAllHidden([]))
    }

    // MARK: - Launch history

    @MainActor
    func testNoteLaunchedKeepsNewestFirstWithoutDuplicates() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        store.noteLaunched("a")
        store.noteLaunched("b")
        store.noteLaunched("a")

        XCTAssertEqual(store.recentAppIDs, ["a", "b"])
    }

    @MainActor
    func testRecentHistoryIsCapped() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        for index in 0..<(LibraryDocument.recentHistoryLimit + 20) {
            store.noteLaunched("app-\(index)")
        }

        XCTAssertEqual(store.recentAppIDs.count, LibraryDocument.recentHistoryLimit)
        XCTAssertEqual(store.recentAppIDs.first, "app-\(LibraryDocument.recentHistoryLimit + 19)")
    }

    // MARK: - Undo

    @MainActor
    func testUndoRestoresThePreviousDocument() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        XCTAssertFalse(store.canUndo)
        let category = try store.createCategory(name: "Games")
        XCTAssertTrue(store.canUndo)

        store.deleteCategory(id: category.id)
        XCTAssertTrue(store.categories.isEmpty)

        store.undo()
        XCTAssertEqual(store.categories.map(\.id), [category.id])
    }

    @MainActor
    func testLaunchHistoryIsNotRecordedOnTheUndoStack() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        store.noteLaunched("a")
        XCTAssertFalse(store.canUndo, "Recording a launch should not create an undo step")
    }

    // MARK: - Persistence

    @MainActor
    func testDocumentSurvivesAReopen() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }

        let category: AppCategory
        do {
            let store = harness.store
            category = try store.createCategory(
                name: "Development",
                symbolName: "hammer.fill",
                colorHex: "#BF5AF2",
                appIDs: ["com.apple.dt.Xcode"]
            )
            store.setHidden(true, appIDs: ["com.apple.Safari"])
            store.updateSettings { $0.iconSize = .large }
        }

        let reloaded = LibraryStore(fileURL: harness.directory.appendingPathComponent("library.json"))

        XCTAssertEqual(reloaded.categories.count, 1)
        XCTAssertEqual(reloaded.categories.first?.id, category.id)
        XCTAssertEqual(reloaded.categories.first?.symbolName, "hammer.fill")
        XCTAssertEqual(reloaded.categories.first?.appIDs, ["com.apple.dt.Xcode"])
        XCTAssertEqual(reloaded.hiddenAppIDs, ["com.apple.Safari"])
        XCTAssertEqual(reloaded.settings.iconSize, .large)
    }

    @MainActor
    func testUnreadableFileIsPreservedRatherThanOverwritten() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let url = harness.directory.appendingPathComponent("library.json")
        try Data("this is not json".utf8).write(to: url)

        let store = LibraryStore(fileURL: url)

        XCTAssertTrue(store.categories.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path),
            "The unreadable file should be kept for manual recovery"
        )
    }

    // MARK: - Pruning

    @MainActor
    func testPruneRemovesMembershipsForUninstalledApps() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        let category = try store.createCategory(name: "Tools", appIDs: ["keep", "gone"])
        store.setHidden(true, appIDs: ["gone"])
        store.noteLaunched("gone")

        store.prune(keeping: ["keep"])

        XCTAssertEqual(store.appIDs(inCategory: category.id), ["keep"])
        XCTAssertTrue(store.hiddenAppIDs.isEmpty)
        XCTAssertTrue(store.recentAppIDs.isEmpty)
    }

    @MainActor
    func testPruneRefusesToRunOnAnEmptyScan() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        let category = try store.createCategory(name: "Tools", appIDs: ["a", "b"])
        store.prune(keeping: [])

        XCTAssertEqual(
            store.appIDs(inCategory: category.id),
            ["a", "b"],
            "A scan that found nothing must not be treated as 'everything was uninstalled'"
        )
    }

    // MARK: - Import / export / reset

    @MainActor
    func testExportThenImportRoundTrips() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        try store.createCategory(name: "Games", symbolName: "gamecontroller.fill", appIDs: ["a"])
        let data = try store.exportData()

        store.reset()
        XCTAssertTrue(store.categories.isEmpty)

        try store.importDocument(from: data)
        XCTAssertEqual(store.categories.count, 1)
        XCTAssertEqual(store.categories.first?.name, "Games")
        XCTAssertEqual(store.categories.first?.appIDs, ["a"])
    }

    @MainActor
    func testResetKeepsSettings() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        store.updateSettings { $0.sortMode = .manual }
        try store.createCategory(name: "Games", appIDs: ["a"])
        store.setHidden(true, appIDs: ["b"])

        store.reset()

        XCTAssertTrue(store.categories.isEmpty)
        XCTAssertTrue(store.hiddenAppIDs.isEmpty)
        XCTAssertEqual(store.settings.sortMode, .manual)
    }

    @MainActor
    func testValidationReportsDuplicates() throws {
        let harness = try TemporaryStore()
        defer { harness.cleanUp() }
        let store = harness.store

        let category = try store.createCategory(name: "Games")

        XCTAssertNil(store.validationError(for: "Work"))
        XCTAssertNil(
            store.validationError(for: "Games", excluding: category.id),
            "A category may keep its own name while being edited"
        )
        XCTAssertEqual(store.validationError(for: ""), .emptyName)
        XCTAssertEqual(store.validationError(for: "games"), .duplicateName("games"))
    }
}

// MARK: - Array helper

final class ArrayMoveTests: XCTestCase {
    func testMoveForward() {
        var values = ["A", "B", "C", "D"]
        values.moveElements(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(values, ["B", "A", "C", "D"])
    }

    func testMoveToTheFront() {
        var values = ["A", "B", "C", "D"]
        values.moveElements(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(values, ["D", "A", "B", "C"])
    }

    func testMoveToTheEnd() {
        var values = ["A", "B", "C", "D"]
        values.moveElements(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        XCTAssertEqual(values, ["B", "C", "D", "A"])
    }

    func testMoveSeveralAtOnce() {
        var values = ["A", "B", "C", "D", "E"]
        values.moveElements(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        XCTAssertEqual(values, ["B", "D", "A", "C", "E"])
    }

    func testMovingToTheSamePlaceChangesNothing() {
        var values = ["A", "B", "C"]
        values.moveElements(fromOffsets: IndexSet(integer: 1), toOffset: 2)
        XCTAssertEqual(values, ["A", "B", "C"])
    }
}
