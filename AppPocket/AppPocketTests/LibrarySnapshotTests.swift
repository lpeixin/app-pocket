//
//  LibrarySnapshotTests.swift
//  AppPocketTests
//

import XCTest
@testable import AppPocket

final class LibrarySnapshotTests: XCTestCase {

    private let safari = Fixture.app(name: "Safari", bundleID: "com.apple.Safari")
    private let xcode = Fixture.app(name: "Xcode", bundleID: "com.apple.dt.Xcode")
    private let terminal = Fixture.app(name: "Terminal", bundleID: "com.apple.Terminal")
    private let notes = Fixture.app(name: "Notes", bundleID: "com.apple.Notes")

    private var allApps: [AppInfo] { [safari, xcode, terminal, notes] }

    // MARK: - All

    func testAllGroupExcludesHiddenApps() {
        let result = LibrarySnapshot.apps(
            for: .smart(.all),
            allApps: allApps,
            hiddenIDs: [notes.id],
            categories: [],
            recentIDs: []
        )
        XCTAssertEqual(result.map(\.name), ["Safari", "Xcode", "Terminal"])
    }

    func testHiddenGroupShowsOnlyHiddenApps() {
        let result = LibrarySnapshot.apps(
            for: .smart(.hidden),
            allApps: allApps,
            hiddenIDs: [notes.id, terminal.id],
            categories: [],
            recentIDs: []
        )
        XCTAssertEqual(result.map(\.name).sorted(), ["Notes", "Terminal"])
    }

    // MARK: - Uncategorized

    func testUncategorizedExcludesAppsThatBelongToACategory() {
        let category = AppCategory(name: "Dev", appIDs: [xcode.id])

        let result = LibrarySnapshot.apps(
            for: .smart(.uncategorized),
            allApps: allApps,
            hiddenIDs: [],
            categories: [category],
            recentIDs: []
        )
        XCTAssertEqual(result.map(\.name), ["Safari", "Terminal", "Notes"])
        XCTAssertFalse(result.contains { $0.id == xcode.id })
    }

    func testUncategorizedCountsHiddenAppsAsCategorizedToo() {
        let category = AppCategory(name: "Dev", appIDs: [xcode.id])
        let count = LibrarySnapshot.count(
            for: .uncategorized,
            allApps: allApps,
            hiddenIDs: [notes.id],
            categories: [category],
            recentIDs: []
        )
        // Safari and Terminal remain; Notes is hidden so it is not offered here.
        XCTAssertEqual(count, 2)
    }

    // MARK: - Category

    func testCategoryFollowsTheStoredOrder() {
        let category = AppCategory(name: "Favourites", appIDs: [terminal.id, safari.id])

        let result = LibrarySnapshot.apps(
            for: .category(category.id),
            allApps: allApps,
            hiddenIDs: [],
            categories: [category],
            recentIDs: []
        )
        XCTAssertEqual(result.map(\.name), ["Terminal", "Safari"])
    }

    func testCategorySkipsAppsThatAreNoLongerInstalled() {
        let category = AppCategory(name: "Favourites", appIDs: ["com.gone.App", safari.id])

        let result = LibrarySnapshot.apps(
            for: .category(category.id),
            allApps: allApps,
            hiddenIDs: [],
            categories: [category],
            recentIDs: []
        )
        XCTAssertEqual(result.map(\.name), ["Safari"])
    }

    func testUnknownCategoryShowsNothing() {
        let result = LibrarySnapshot.apps(
            for: .category(UUID()),
            allApps: allApps,
            hiddenIDs: [],
            categories: [],
            recentIDs: []
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Recent

    func testRecentFollowsTheHistoryOrder() {
        let result = LibrarySnapshot.apps(
            for: .smart(.recent),
            allApps: allApps,
            hiddenIDs: [],
            categories: [],
            recentIDs: [notes.id, safari.id]
        )
        XCTAssertEqual(result.map(\.name), ["Notes", "Safari"])
    }

    func testRecentSkipsAppsThatAreNoLongerInstalled() {
        let result = LibrarySnapshot.apps(
            for: .smart(.recent),
            allApps: allApps,
            hiddenIDs: [],
            categories: [],
            recentIDs: ["com.gone.App", safari.id]
        )
        XCTAssertEqual(result.map(\.name), ["Safari"])
    }

    // MARK: - Counting

    func testCountMatchesWhatTheGridWouldShow() {
        let category = AppCategory(name: "Dev", appIDs: [xcode.id])
        let count = LibrarySnapshot.count(
            for: .all,
            allApps: allApps,
            hiddenIDs: [notes.id],
            categories: [category],
            recentIDs: []
        )
        XCTAssertEqual(count, 3)
    }
}

// MARK: - Document decoding

final class LibraryDocumentTests: XCTestCase {

    func testDecodesAMinimalDocumentWithDefaults() throws {
        let json = Data(#"{"categories":[]}"#.utf8)
        let document = try JSONDecoder().decode(LibraryDocument.self, from: json)

        XCTAssertEqual(document.schemaVersion, LibraryDocument.currentSchemaVersion)
        XCTAssertTrue(document.categories.isEmpty)
        XCTAssertTrue(document.hiddenAppIDs.isEmpty)
        XCTAssertEqual(document.settings.iconSize, .medium)
        XCTAssertEqual(document.settings.sortMode, .name)
    }

    func testDecodesAnEmptyObject() throws {
        let document = try JSONDecoder().decode(LibraryDocument.self, from: Data("{}".utf8))
        XCTAssertEqual(document, LibraryDocument.empty)
    }

    func testIgnoresUnknownKeys() throws {
        let json = Data(#"{"categories":[],"somethingFromTheFuture":42}"#.utf8)
        XCTAssertNoThrow(try JSONDecoder().decode(LibraryDocument.self, from: json))
    }

    func testPruneReportsWhetherAnythingChanged() {
        var document = LibraryDocument()
        document.categories = [AppCategory(name: "Dev", appIDs: ["keep", "gone"])]
        document.hiddenAppIDs = ["keep"]
        document.recentAppIDs = ["keep"]

        XCTAssertFalse(document.prune(keeping: ["keep", "gone"]))

        XCTAssertTrue(document.prune(keeping: ["keep"]))
        XCTAssertEqual(document.categories.first?.appIDs, ["keep"])
        XCTAssertEqual(document.hiddenAppIDs, ["keep"])
    }

    func testLookups() {
        let category = AppCategory(name: "Dev", appIDs: ["a"])
        var document = LibraryDocument()
        document.categories = [category]

        XCTAssertEqual(document.category(id: category.id)?.name, "Dev")
        XCTAssertEqual(document.categoryIndex(id: category.id), 0)
        XCTAssertEqual(document.categoryIDs(containing: "a"), [category.id])
        XCTAssertTrue(document.categoryIDs(containing: "b").isEmpty)
    }

    /// Regression: the encoder once wrote ISO 8601 dates while the decoder
    /// expected numeric ones, so nothing that was saved could be read back.
    func testSavingAndLoadingAgreeOnDates() throws {
        var document = LibraryDocument()
        document.categories = [AppCategory(name: "Dev", appIDs: ["a"])]
        document.recentAppIDs = ["a"]
        document.settings.iconSize = .large

        let data = try LibraryCoding.encode(document)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("createdAt"), "The document should record when a category was made")
        XCTAssertTrue(
            text.contains("20"),
            "Dates should be written as readable ISO 8601 strings, not opaque numbers"
        )

        let reloaded = try LibraryCoding.decode(data)

        // ISO 8601 keeps milliseconds, so the timestamp is compared with a
        // tolerance rather than bit-for-bit. Everything else must survive intact.
        let original = try XCTUnwrap(document.categories.first)
        let restored = try XCTUnwrap(reloaded.categories.first)
        XCTAssertLessThan(
            abs(original.createdAt.timeIntervalSince(restored.createdAt)),
            0.001,
            "Timestamps should survive a save and load to millisecond precision"
        )

        var normalized = reloaded
        normalized.categories[0].createdAt = original.createdAt
        XCTAssertEqual(normalized, document)
    }

    func testDecodingAcceptsTimestampsWithoutFractionalSeconds() throws {
        let json = Data("""
        {"categories":[{"appIDs":[],"colorHex":"#0A84FF","createdAt":"2025-01-02T03:04:05Z",\
        "id":"5E5CE6A0-0000-4000-8000-000000000001","name":"Old","symbolName":"folder.fill"}]}
        """.utf8)

        let document = try LibraryCoding.decode(json)

        XCTAssertEqual(document.categories.first?.name, "Old")
    }
}
