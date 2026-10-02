//
//  AppInfo.swift
//  AppPocket
//
//  A discovered application bundle.
//

import Foundation

/// Where an application bundle lives.
///
/// Used both for de-duplication priority and for labelling system apps in the UI.
nonisolated enum AppLocation: String, Codable, Hashable, Sendable, CaseIterable {
    /// `~/Applications`
    case user
    /// `/Applications` and its subfolders
    case local
    /// Anything under `/System`
    case system
    /// A location we did not anticipate (e.g. an app dragged in from a disk image)
    case other

    /// Higher wins when two bundles claim the same identity.
    var priority: Int {
        switch self {
        case .local: return 3
        case .user: return 2
        case .system: return 1
        case .other: return 0
        }
    }

    /// Localization key for the short label shown in the app inspector.
    var titleKey: String {
        switch self {
        case .user: return "location.user"
        case .local: return "location.local"
        case .system: return "location.system"
        case .other: return "location.other"
        }
    }

    /// Derives the location from an absolute path.
    static func forPath(_ path: String, homeDirectory: String) -> AppLocation {
        if path.hasPrefix("/System/") { return .system }
        if path.hasPrefix("/Applications/") { return .local }
        if path.hasPrefix(homeDirectory + "/Applications/") { return .user }
        return .other
    }
}

/// An application bundle found on disk.
///
/// `id` is the bundle identifier whenever the bundle declares one, otherwise the
/// absolute path. Keying on the bundle identifier means a category membership
/// survives the user moving an app between folders — which happens far more
/// often than an app changing its bundle identifier.
nonisolated struct AppInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let bundleID: String?
    let path: String
    let version: String?
    let location: AppLocation

    var url: URL { URL(fileURLWithPath: path) }
    var isSystemApp: Bool { location == .system }

    /// First letter used by the placeholder tile while the real icon loads.
    var monogram: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    init(
        id: String,
        name: String,
        bundleID: String?,
        path: String,
        version: String?,
        location: AppLocation
    ) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.version = version
        self.location = location
    }
}

// MARK: - Sorting

extension Sequence where Element == AppInfo {
    /// Alphabetical order that respects the user's locale (so `Ä` sorts next to `A`).
    ///
    /// `nonisolated` because the scan, the query layer and the snapshot builder
    /// all run off the main actor.
    nonisolated func sortedByName() -> [AppInfo] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
