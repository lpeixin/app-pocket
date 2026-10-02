//
//  LibraryFormatTests.swift
//  AppPocketTests
//
//  The on-disk format's tolerance for change.
//
//  `LibraryFile.load` treats *any* decode failure as corruption: it renames the
//  file to `library.json.corrupt` and hands the app an empty document. That
//  makes every decoding decision a data-loss decision, and it is why each type
//  in the document decodes field by field instead of leaning on the synthesised
//  decoder.
//
//  These tests exist because that was not always true. `LauncherSettings`,
//  `AppCategory` and `HotKeySpec` used to rely on the synthesised `Codable`,
//  which ignores property default values and calls `decode` for every
//  non-optional property. The result was that adding a single field in a future
//  version would make every existing library fail to decode — and be silently
//  moved aside as corrupt.
//

import XCTest
@testable import AppPocket

final class LibraryFormatTests: XCTestCase {

    /// A document with every field the current build writes.
    private let completeDocument = """
    {
      "schemaVersion": 1,
      "categories": [
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Development",
          "symbolName": "hammer.fill",
          "colorHex": "#0A84FF",
          "appIDs": ["com.apple.dt.Xcode"],
          "createdAt": "2026-01-01T00:00:00.000Z"
        }
      ],
      "hiddenAppIDs": ["com.apple.Safari"],
      "recentAppIDs": ["com.apple.dt.Xcode"],
      "settings": {
        "columnCount": 5,
        "iconSize": "large",
        "sortMode": "manual",
        "closeAfterLaunch": false,
        "launchAtLogin": true,
        "showMenuBarExtra": false,
        "globalHotKeyEnabled": true,
        "globalHotKey": { "keyCode": 49, "modifiers": 2304 }
      }
    }
    """

    // MARK: - Helpers

    private func decode(_ json: String) throws -> LibraryDocument {
        try LibraryCoding.decode(Data(json.utf8))
    }

    /// Writes `json` to a scratch `library.json` and loads it the way the app
    /// does on launch.
    private func loadFromDisk(_ json: String) throws -> (document: LibraryDocument, directory: URL) {
        let directory = try Fixture.makeTemporaryDirectory()
        let url = directory.appendingPathComponent(LibraryFile.fileName)
        try Data(json.utf8).write(to: url)
        return (LibraryFile.load(from: url), directory)
    }

    private func assertNotQuarantined(_ directory: URL, file: StaticString = #filePath, line: UInt = #line) {
        let quarantined = directory
            .appendingPathComponent(LibraryFile.fileName)
            .appendingPathExtension("corrupt")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: quarantined.path),
            "the library was quarantined as corrupt instead of being read",
            file: file, line: line
        )
    }

    // MARK: - The regression

    /// The whole point: a file written before a field existed must still load.
    @MainActor
    func testSettingsWrittenBeforeAFieldExistedStillLoads() throws {
        let json = completeDocument.replacingOccurrences(of: "\"columnCount\": 5,\n", with: "")
        let document = try decode(json)

        // The field that is missing falls back to its default...
        XCTAssertEqual(document.settings.columnCount, 0)
        // ...and everything else is preserved rather than reset.
        XCTAssertEqual(document.settings.iconSize, .large)
        XCTAssertEqual(document.settings.sortMode, .manual)
        XCTAssertFalse(document.settings.closeAfterLaunch)
        XCTAssertTrue(document.settings.launchAtLogin)
        XCTAssertTrue(document.settings.globalHotKeyEnabled)
    }

    @MainActor
    func testCategoryWrittenBeforeAFieldExistedStillLoads() throws {
        let json = completeDocument.replacingOccurrences(of: "\"colorHex\": \"#0A84FF\",\n", with: "")
        let document = try decode(json)

        XCTAssertEqual(document.categories.count, 1)
        XCTAssertEqual(document.categories[0].colorHex, AppCategory.palette[0])
        XCTAssertEqual(document.categories[0].name, "Development")
        XCTAssertEqual(document.categories[0].appIDs, ["com.apple.dt.Xcode"])
    }

    @MainActor
    func testHotKeyWrittenBeforeAFieldExistedStillLoads() throws {
        let json = completeDocument.replacingOccurrences(
            of: "\"globalHotKey\": { \"keyCode\": 49, \"modifiers\": 2304 }",
            with: "\"globalHotKey\": { \"keyCode\": 36 }"
        )
        let document = try decode(json)

        XCTAssertEqual(document.settings.globalHotKey.keyCode, 36)
        XCTAssertEqual(document.settings.globalHotKey.modifiers, HotKeySpec.default.modifiers)
    }

    /// A value the current build does not know about — a new enum case, say —
    /// must degrade to the default rather than fail the whole document.
    @MainActor
    func testUnknownEnumCasesFallBackInsteadOfFailing() throws {
        let json = completeDocument
            .replacingOccurrences(of: "\"sortMode\": \"manual\"", with: "\"sortMode\": \"alphabetical\"")
            .replacingOccurrences(of: "\"iconSize\": \"large\"", with: "\"iconSize\": \"enormous\"")
        let document = try decode(json)

        XCTAssertEqual(document.settings.sortMode, .name)
        XCTAssertEqual(document.settings.iconSize, .medium)
    }

    /// `createdAt` is only used for ordering, and this format already has a
    /// history of date-strategy mismatches making every library unreadable.
    @MainActor
    func testMalformedTimestampFallsBackInsteadOfFailing() throws {
        let json = completeDocument.replacingOccurrences(
            of: "\"createdAt\": \"2026-01-01T00:00:00.000Z\"",
            with: "\"createdAt\": \"whenever\""
        )
        let document = try decode(json)

        XCTAssertEqual(document.categories.count, 1)
        XCTAssertEqual(document.categories[0].name, "Development")
    }

    /// The user-visible consequence, end to end: the file must be read, and it
    /// must not be moved aside as corrupt.
    @MainActor
    func testAnOldFileKeepsItsCategoriesAndIsNotQuarantined() throws {
        let json = completeDocument.replacingOccurrences(of: "\"columnCount\": 5,\n", with: "")
        let (document, directory) = try loadFromDisk(json)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(document.categories.count, 1, "the category was lost")
        XCTAssertEqual(document.categories[0].appIDs, ["com.apple.dt.Xcode"])
        XCTAssertEqual(document.hiddenAppIDs, ["com.apple.Safari"])
        XCTAssertEqual(document.recentAppIDs, ["com.apple.dt.Xcode"])
        assertNotQuarantined(directory)
    }

    // MARK: - The other direction

    /// The decoder is hand-written; the encoder is still synthesised. A typo in
    /// a coding key would silently reset that field to its default on the next
    /// launch, so round-trip the non-default values.
    @MainActor
    func testEveryFieldSurvivesARoundTrip() throws {
        let original = try decode(completeDocument)
        let reencoded = try LibraryCoding.decode(LibraryCoding.encode(original))

        XCTAssertEqual(reencoded, original)
    }

    /// Pins the wire format. If a property is renamed, this fails rather than
    /// quietly changing what existing files are expected to contain.
    @MainActor
    func testEncodedKeysAreStable() throws {
        let document = try decode(completeDocument)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: LibraryCoding.encode(document)) as? [String: Any]
        )

        XCTAssertEqual(
            Set(object.keys),
            ["schemaVersion", "categories", "hiddenAppIDs", "recentAppIDs", "settings"]
        )

        let settings = try XCTUnwrap(object["settings"] as? [String: Any])
        XCTAssertEqual(
            Set(settings.keys),
            [
                "columnCount", "iconSize", "sortMode", "closeAfterLaunch",
                "launchAtLogin", "showMenuBarExtra", "globalHotKeyEnabled", "globalHotKey",
            ]
        )

        let categories = try XCTUnwrap(object["categories"] as? [[String: Any]])
        XCTAssertEqual(
            Set(try XCTUnwrap(categories.first).keys),
            ["id", "name", "symbolName", "colorHex", "appIDs", "createdAt"]
        )
    }

    // MARK: - Schema version

    /// `schemaVersion` is written and read but nothing acts on it. This test
    /// records the current behaviour rather than asserting it is correct: a file
    /// claiming a version this build has never heard of is accepted as if it
    /// were version 1. See DESIGN_DOCUMENT.md, known limitations.
    @MainActor
    func testAHigherSchemaVersionIsCurrentlyAcceptedUnchecked() throws {
        let json = completeDocument.replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 99")
        let document = try decode(json)

        XCTAssertEqual(document.schemaVersion, 99)
        XCTAssertEqual(document.categories.count, 1)
    }
}
