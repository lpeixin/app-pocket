//
//  AppScannerTests.swift
//  AppPocketTests
//

import XCTest
@testable import AppPocket

final class AppScannerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = try Fixture.makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    private let home = "/Users/tester"

    // MARK: - Reading a bundle

    func testReadsDisplayNameBundleIDAndVersion() throws {
        let bundle = try Fixture.writeBundle(
            at: root,
            name: "Fancy.app",
            info: [
                "CFBundleDisplayName": "Fancy Name",
                "CFBundleName": "Fancy",
                "CFBundleIdentifier": "com.example.fancy",
                "CFBundleExecutable": "Fancy",
                "CFBundleShortVersionString": "3.1.4",
            ]
        )

        let app = AppScanner.makeAppInfo(at: bundle, homeDirectory: home)

        XCTAssertEqual(app?.name, "Fancy Name")
        XCTAssertEqual(app?.bundleID, "com.example.fancy")
        XCTAssertEqual(app?.id, "com.example.fancy")
        XCTAssertEqual(app?.version, "3.1.4")
    }

    func testFallsBackToBundleNameThenFolderName() throws {
        let named = try Fixture.writeBundle(
            at: root,
            name: "Named.app",
            info: Fixture.executableInfo(name: "Real Name")
        )
        XCTAssertEqual(AppScanner.makeAppInfo(at: named, homeDirectory: home)?.name, "Real Name")

        let unnamed = try Fixture.writeBundle(
            at: root,
            name: "FolderName.app",
            info: ["CFBundleExecutable": "FolderName"]
        )
        XCTAssertEqual(AppScanner.makeAppInfo(at: unnamed, homeDirectory: home)?.name, "FolderName")
    }

    func testUsesPathAsIdentityWhenThereIsNoBundleIdentifier() throws {
        let bundle = try Fixture.writeBundle(
            at: root,
            name: "Anonymous.app",
            info: Fixture.executableInfo(name: "Anonymous")
        )
        let app = AppScanner.makeAppInfo(at: bundle, homeDirectory: home)
        XCTAssertNil(app?.bundleID)
        XCTAssertEqual(app?.id, bundle.path)
    }

    func testSkipsBackgroundAgentsAndMenuBarExtras() throws {
        let agent = try Fixture.writeBundle(
            at: root,
            name: "Agent.app",
            info: Fixture.executableInfo(name: "Agent", extra: ["LSUIElement": true])
        )
        XCTAssertNil(AppScanner.makeAppInfo(at: agent, homeDirectory: home))

        let legacyAgent = try Fixture.writeBundle(
            at: root,
            name: "OldAgent.app",
            info: Fixture.executableInfo(name: "OldAgent", extra: ["LSUIElement": "1"])
        )
        XCTAssertNil(AppScanner.makeAppInfo(at: legacyAgent, homeDirectory: home))

        let background = try Fixture.writeBundle(
            at: root,
            name: "Background.app",
            info: Fixture.executableInfo(name: "Background", extra: ["LSBackgroundOnly": true])
        )
        XCTAssertNil(AppScanner.makeAppInfo(at: background, homeDirectory: home))
    }

    func testSkipsBundlesWithoutAnExecutable() throws {
        let bundle = try Fixture.writeBundle(
            at: root,
            name: "NoExecutable.app",
            info: ["CFBundleName": "NoExecutable", "CFBundleIdentifier": "com.example.noexec"]
        )
        XCTAssertNil(AppScanner.makeAppInfo(at: bundle, homeDirectory: home))
    }

    func testSkipsBundlesWithNoInfoPlist() throws {
        let bundle = root.appendingPathComponent("Broken.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        XCTAssertNil(AppScanner.makeAppInfo(at: bundle.deletingLastPathComponent(), homeDirectory: home))
    }

    // MARK: - Location

    func testLocationIsDerivedFromThePath() {
        XCTAssertEqual(AppLocation.forPath("/Applications/X.app", homeDirectory: home), .local)
        XCTAssertEqual(AppLocation.forPath("/System/Applications/X.app", homeDirectory: home), .system)
        XCTAssertEqual(AppLocation.forPath(home + "/Applications/X.app", homeDirectory: home), .user)
        XCTAssertEqual(AppLocation.forPath("/Volumes/Disk/X.app", homeDirectory: home), .other)
    }

    // MARK: - Walking

    func testScanFindsBundlesInTheRootAndOneLevelDown() throws {
        try Fixture.writeBundle(at: root, name: "Direct.app", info: Fixture.executableInfo(name: "Direct"))
        let vendor = root.appendingPathComponent("Vendor", isDirectory: true)
        try FileManager.default.createDirectory(at: vendor, withIntermediateDirectories: true)
        try Fixture.writeBundle(at: vendor, name: "Nested.app", info: Fixture.executableInfo(name: "Nested"))

        let outcome = AppScanner.scan(roots: [root], maxDepth: 2)

        XCTAssertEqual(outcome.apps.map(\.name).sorted(), ["Direct", "Nested"])
    }

    func testScanDoesNotDescendIntoAppBundles() throws {
        let outer = try Fixture.writeBundle(
            at: root,
            name: "Outer.app",
            info: Fixture.executableInfo(name: "Outer")
        )
        try Fixture.writeBundle(
            at: outer.appendingPathComponent("Contents/Helpers", isDirectory: true),
            name: "Inner.app",
            info: Fixture.executableInfo(name: "Inner")
        )

        let outcome = AppScanner.scan(roots: [root], maxDepth: 3)

        XCTAssertEqual(outcome.apps.map(\.name), ["Outer"])
    }

    func testScanRespectsTheDepthLimit() throws {
        var deep = root!
        for level in 1...6 {
            deep.appendPathComponent("level\(level)", isDirectory: true)
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        }
        try Fixture.writeBundle(at: deep, name: "TooDeep.app", info: Fixture.executableInfo(name: "TooDeep"))

        let outcome = AppScanner.scan(roots: [root], maxDepth: 2)

        XCTAssertTrue(outcome.apps.isEmpty)
    }

    func testMissingRootIsNotReportedAsAnError() {
        let outcome = AppScanner.scan(
            roots: [root.appendingPathComponent("DoesNotExist")],
            maxDepth: 1
        )
        XCTAssertTrue(outcome.apps.isEmpty)
        XCTAssertTrue(outcome.unreadableRoots.isEmpty)
    }

    // MARK: - De-duplication

    func testDuplicateBundleIdentifiersKeepTheLocalCopy() {
        let local = Fixture.app(name: "Thing", bundleID: "com.example.thing", path: "/Applications/Thing.app", location: .local)
        let system = Fixture.app(name: "Thing", bundleID: "com.example.thing", path: "/System/Applications/Thing.app", location: .system)
        let user = Fixture.app(name: "Thing", bundleID: "com.example.thing", path: home + "/Applications/Thing.app", location: .user)

        let result = AppScanner.deduplicate([system, user, local])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.path, "/Applications/Thing.app")
    }

    func testDuplicateBundleIdentifiersPreferTheShallowerPath() {
        let shallow = Fixture.app(name: "Thing", bundleID: "com.example.thing", path: "/Applications/Thing.app", location: .local)
        let nested = Fixture.app(name: "Thing", bundleID: "com.example.thing", path: "/Applications/Vendor/Thing.app", location: .local)

        let result = AppScanner.deduplicate([nested, shallow])

        XCTAssertEqual(result.first?.path, "/Applications/Thing.app")
    }

    func testDifferentBundleIdentifiersAreKeptSeparately() {
        let a = Fixture.app(name: "One", bundleID: "com.example.one")
        let b = Fixture.app(name: "Two", bundleID: "com.example.two")
        XCTAssertEqual(AppScanner.deduplicate([a, b]).count, 2)
    }
}
