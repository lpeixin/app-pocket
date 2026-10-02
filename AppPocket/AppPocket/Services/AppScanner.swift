//
//  AppScanner.swift
//  AppPocket
//
//  Finds application bundles on disk.
//

import Foundation

nonisolated struct ScanOutcome: Sendable {
    var apps: [AppInfo] = []
    /// Directories that existed but could not be listed, so the UI can say so
    /// instead of silently showing fewer apps than the user expects.
    var unreadableRoots: [String] = []
    var duration: TimeInterval = 0
}

/// Walks the standard application locations and turns each `.app` bundle into
/// an `AppInfo`.
///
/// Everything here is `nonisolated` so it can run on a background thread: the
/// scan touches hundreds of files and must never block the UI.
nonisolated enum AppScanner {

    /// Locations macOS uses for launchable applications, in the order a user
    /// would expect to find them.
    static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    /// How deep to descend below each root.
    ///
    /// Two levels covers the common `/Applications/<Vendor>/<App>.app` layout
    /// without turning the scan into a full disk crawl.
    static let defaultMaxDepth = 2

    static func scan(
        roots: [URL] = AppScanner.defaultRoots,
        maxDepth: Int = AppScanner.defaultMaxDepth
    ) -> ScanOutcome {
        let started = Date()
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        var bundleURLs: [URL] = []
        var unreadable: [String] = []

        for root in roots {
            walk(root, depth: 0, maxDepth: maxDepth, into: &bundleURLs, unreadable: &unreadable)
        }

        var discovered: [AppInfo] = []
        discovered.reserveCapacity(bundleURLs.count)
        for url in bundleURLs {
            if let app = makeAppInfo(at: url, homeDirectory: home) {
                discovered.append(app)
            }
        }

        return ScanOutcome(
            apps: deduplicate(discovered).sortedByName(),
            unreadableRoots: unreadable,
            duration: Date().timeIntervalSince(started)
        )
    }

    // MARK: - Directory walk

    private static func walk(
        _ directory: URL,
        depth: Int,
        maxDepth: Int,
        into paths: inout [URL],
        unreadable: inout [String]
    ) {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        // A missing root (no `~/Applications`, for instance) is normal, not an error.
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        } catch {
            unreadable.append(directory.path)
            return
        }

        for entry in entries {
            if entry.pathExtension.lowercased() == "app" {
                paths.append(entry)
                continue
            }
            guard depth < maxDepth else { continue }
            var entryIsDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: entry.path, isDirectory: &entryIsDirectory),
               entryIsDirectory.boolValue {
                walk(entry, depth: depth + 1, maxDepth: maxDepth, into: &paths, unreadable: &unreadable)
            }
        }
    }

    // MARK: - Bundle inspection

    /// Builds an `AppInfo` from a bundle path, or returns `nil` when the bundle
    /// is not something a user would launch from a launcher.
    static func makeAppInfo(at bundleURL: URL, homeDirectory: String) -> AppInfo? {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            return nil
        }

        // Background agents and menu bar extras are not launchable "apps" in the
        // Launchpad sense; showing them just adds noise.
        if boolValue(info["LSUIElement"]) || boolValue(info["LSBackgroundOnly"]) {
            return nil
        }
        // No executable means there is nothing to launch.
        guard let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty else {
            return nil
        }

        let fallbackName = bundleURL.deletingPathExtension().lastPathComponent
        let name = (info["CFBundleDisplayName"] as? String).flatMap(nonEmpty)
            ?? (info["CFBundleName"] as? String).flatMap(nonEmpty)
            ?? fallbackName

        let bundleID = (info["CFBundleIdentifier"] as? String).flatMap(nonEmpty)
        let version = (info["CFBundleShortVersionString"] as? String).flatMap(nonEmpty)
        let path = bundleURL.path

        return AppInfo(
            id: bundleID ?? path,
            name: name,
            bundleID: bundleID,
            path: path,
            version: version,
            location: AppLocation.forPath(path, homeDirectory: homeDirectory)
        )
    }

    // MARK: - Helpers

    /// Two bundles can claim the same identity (an app installed in both
    /// `/Applications` and `~/Applications`, for example). Keep the one from the
    /// location a user is most likely to have launched.
    static func deduplicate(_ apps: [AppInfo]) -> [AppInfo] {
        var best: [String: AppInfo] = [:]
        for app in apps {
            guard let existing = best[app.id] else {
                best[app.id] = app
                continue
            }
            if isPreferred(app, over: existing) {
                best[app.id] = app
            }
        }
        return Array(best.values)
    }

    private static func isPreferred(_ candidate: AppInfo, over existing: AppInfo) -> Bool {
        if candidate.location.priority != existing.location.priority {
            return candidate.location.priority > existing.location.priority
        }
        // Same priority: the shallower path is the canonical install.
        let candidateDepth = candidate.path.split(separator: "/").count
        let existingDepth = existing.path.split(separator: "/").count
        if candidateDepth != existingDepth {
            return candidateDepth < existingDepth
        }
        return candidate.path < existing.path
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Info.plist booleans are sometimes written as `1` or `"YES"`.
    private static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.boolValue
        case let text as String: return ["1", "true", "yes"].contains(text.lowercased())
        default: return false
        }
    }
}
