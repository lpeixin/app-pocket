//
//  TestFixtures.swift
//  AppPocketTests
//

import Foundation
@testable import AppPocket

enum Fixture {
    static func app(
        id: String? = nil,
        name: String,
        bundleID: String? = nil,
        path: String? = nil,
        version: String? = "1.0",
        location: AppLocation = .local
    ) -> AppInfo {
        let resolvedPath = path ?? "/Applications/\(name).app"
        return AppInfo(
            id: id ?? bundleID ?? resolvedPath,
            name: name,
            bundleID: bundleID ?? "com.example.\(name.lowercased())",
            path: resolvedPath,
            version: version,
            location: location
        )
    }

    /// A scratch directory that is removed by the caller.
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppPocketTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a minimal but valid `.app` bundle so the scanner has something
    /// realistic to inspect.
    @discardableResult
    static func writeBundle(
        at directory: URL,
        name: String,
        info: [String: Any]
    ) throws -> URL {
        let bundle = directory.appendingPathComponent(name, isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = contents.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: plist)
        return bundle
    }

    static func executableInfo(
        name: String,
        bundleID: String? = nil,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var info: [String: Any] = [
            "CFBundleName": name,
            "CFBundleExecutable": name.replacingOccurrences(of: " ", with: ""),
            "CFBundlePackageType": "APPL",
        ]
        if let bundleID { info["CFBundleIdentifier"] = bundleID }
        for (key, value) in extra { info[key] = value }
        return info
    }
}

/// A `LibraryStore` backed by a throwaway file. Call `cleanUp()` when done.
@MainActor
final class TemporaryStore {
    let store: LibraryStore
    let directory: URL

    init() throws {
        directory = try Fixture.makeTemporaryDirectory()
        store = LibraryStore(fileURL: directory.appendingPathComponent("library.json"))
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
