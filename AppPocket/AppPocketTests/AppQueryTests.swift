//
//  AppQueryTests.swift
//  AppPocketTests
//

import XCTest
@testable import AppPocket

final class AppQueryTests: XCTestCase {

    private let safari = Fixture.app(name: "Safari", bundleID: "com.apple.Safari")
    private let xcode = Fixture.app(name: "Xcode", bundleID: "com.apple.dt.Xcode")
    private let code = Fixture.app(name: "Code", bundleID: "com.microsoft.VSCode")
    private let terminal = Fixture.app(name: "Terminal", bundleID: "com.apple.Terminal")

    // MARK: - Filtering

    func testEmptyQueryReturnsInputUnchanged() {
        let apps = [xcode, safari]
        XCTAssertEqual(AppQuery.filter(apps, query: "   ").map(\.id), apps.map(\.id))
    }

    func testExactNameOutranksEverythingElse() {
        let apps = [xcode, code]
        XCTAssertEqual(AppQuery.filter(apps, query: "Code").first?.name, "Code")
    }

    func testPrefixMatchBeatsSubstringMatch() {
        let apps = [Fixture.app(name: "AirTerminal", bundleID: "a"), terminal]
        XCTAssertEqual(AppQuery.filter(apps, query: "term").first?.name, "Terminal")
    }

    func testWordBoundaryMatchBeatsMidWordMatch() {
        let apps = [
            Fixture.app(name: "MetaCode", bundleID: "a"),
            Fixture.app(name: "Code Editor", bundleID: "b"),
        ]
        XCTAssertEqual(AppQuery.filter(apps, query: "code").first?.name, "Code Editor")
    }

    func testMatchesBundleIdentifierSuffix() {
        XCTAssertEqual(AppQuery.filter([safari, xcode], query: "safari").map(\.name), ["Safari"])
    }

    func testMatchesSubsequenceOfName() {
        // "tmx" is not a substring of "TextMate X" but is a subsequence.
        let app = Fixture.app(name: "TextMate X", bundleID: "com.macro.mates")
        XCTAssertTrue(AppQuery.matches(app, query: "tmx"))
    }

    func testUnrelatedQueryMatchesNothing() {
        XCTAssertTrue(AppQuery.filter([safari, xcode], query: "zzzzz").isEmpty)
    }

    func testResultsAreOrderedByScoreThenName() {
        let apps = [
            Fixture.app(name: "Graphics Converter", bundleID: "a"),
            Fixture.app(name: "Graph", bundleID: "b"),
            Fixture.app(name: "Telegraph", bundleID: "c"),
        ]
        let names = AppQuery.filter(apps, query: "graph").map(\.name)
        XCTAssertEqual(names.first, "Graph")
        XCTAssertEqual(names.last, "Telegraph")
    }

    // MARK: - Sorting

    func testSortByNameUsesLocalizedComparison() {
        let apps = [
            Fixture.app(name: "zeta"),
            Fixture.app(name: "Alpha"),
            Fixture.app(name: "beta"),
        ]
        XCTAssertEqual(AppQuery.sorted(apps, mode: .name).map(\.name), ["Alpha", "beta", "zeta"])
    }

    func testSortManualFollowsTheStoredOrder() {
        let apps = [safari, xcode, terminal]
        let order = [terminal.id, safari.id, xcode.id]
        XCTAssertEqual(AppQuery.sorted(apps, mode: .manual, manualOrder: order).map(\.name),
                       ["Terminal", "Safari", "Xcode"])
    }

    func testSortManualAppendsUnknownAppsAlphabetically() {
        let apps = [safari, xcode, terminal, code]
        let order = [terminal.id]
        let result = AppQuery.sorted(apps, mode: .manual, manualOrder: order).map(\.name)
        XCTAssertEqual(result.first, "Terminal")
        XCTAssertEqual(Array(result.dropFirst()), ["Code", "Safari", "Xcode"])
    }

    func testSortRecentPutsNeverLaunchedAppsLast() {
        let apps = [safari, xcode, terminal]
        let result = AppQuery.sorted(apps, mode: .recent, recentOrder: [xcode.id])
        XCTAssertEqual(result.map(\.name), ["Xcode", "Safari", "Terminal"])
    }

    func testSortManualIgnoresUnknownIDsInTheOrder() {
        let apps = [safari, xcode]
        let result = AppQuery.sorted(apps, mode: .manual, manualOrder: ["com.gone.App", xcode.id])
        XCTAssertEqual(result.map(\.name), ["Xcode", "Safari"])
    }
}
