//
//  LibraryDocument.swift
//  AppPocket
//
//  The whole persisted state of the launcher, in one value type.
//

import Foundation

/// Root of `library.json`.
///
/// The document is deliberately a plain value type: it is trivial to diff,
/// trivial to snapshot for undo, trivial to export, and it decodes leniently so
/// a file written by a newer build never hard-fails on an older one.
nonisolated struct LibraryDocument: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    /// How many launches are remembered for the "Recently Used" group.
    static let recentHistoryLimit = 60

    var schemaVersion: Int
    var categories: [AppCategory]
    /// Applications the user removed from the grid without uninstalling.
    var hiddenAppIDs: [String]
    /// Most recently launched identifiers, newest first.
    var recentAppIDs: [String]
    var settings: LauncherSettings

    init(
        schemaVersion: Int = LibraryDocument.currentSchemaVersion,
        categories: [AppCategory] = [],
        hiddenAppIDs: [String] = [],
        recentAppIDs: [String] = [],
        settings: LauncherSettings = LauncherSettings()
    ) {
        self.schemaVersion = schemaVersion
        self.categories = categories
        self.hiddenAppIDs = hiddenAppIDs
        self.recentAppIDs = recentAppIDs
        self.settings = settings
    }

    static let empty = LibraryDocument()

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, categories, hiddenAppIDs, recentAppIDs, settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? LibraryDocument.currentSchemaVersion
        self.categories = try container.decodeIfPresent([AppCategory].self, forKey: .categories) ?? []
        self.hiddenAppIDs = try container.decodeIfPresent([String].self, forKey: .hiddenAppIDs) ?? []
        self.recentAppIDs = try container.decodeIfPresent([String].self, forKey: .recentAppIDs) ?? []
        self.settings = try container.decodeIfPresent(LauncherSettings.self, forKey: .settings)
            ?? LauncherSettings()
    }

    // MARK: - Lookups

    func category(id: UUID) -> AppCategory? {
        categories.first { $0.id == id }
    }

    func categoryIndex(id: UUID) -> Int? {
        categories.firstIndex { $0.id == id }
    }

    /// Every category that currently contains `appID`.
    func categoryIDs(containing appID: String) -> Set<UUID> {
        Set(categories.filter { $0.appIDs.contains(appID) }.map(\.id))
    }

    func isHidden(_ appID: String) -> Bool {
        hiddenAppIDs.contains(appID)
    }

    /// Drops identifiers that no longer correspond to anything on disk.
    ///
    /// Called after a scan so uninstalling an app does not leave stale entries
    /// behind forever. Returns `true` when something actually changed, which
    /// lets the caller skip a pointless write.
    mutating func prune(keeping liveIDs: Set<String>) -> Bool {
        let originalCategoryCounts = categories.map(\.appIDs.count)
        for index in categories.indices {
            categories[index].appIDs.removeAll { !liveIDs.contains($0) }
        }
        let hiddenBefore = hiddenAppIDs.count
        hiddenAppIDs.removeAll { !liveIDs.contains($0) }
        let recentBefore = recentAppIDs.count
        recentAppIDs.removeAll { !liveIDs.contains($0) }

        return originalCategoryCounts != categories.map(\.appIDs.count)
            || hiddenBefore != hiddenAppIDs.count
            || recentBefore != recentAppIDs.count
    }
}
