//
//  AppQuery.swift
//  AppPocket
//
//  Pure filtering and ordering helpers, kept free of UI so they can be tested
//  directly.
//

import Foundation

nonisolated enum AppQuery {

    // MARK: - Search

    /// Filters by a free-text query, best match first.
    ///
    /// An empty query returns the input untouched so the caller's ordering is
    /// preserved.
    static func filter(_ apps: [AppInfo], query: String) -> [AppInfo] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return apps }

        return apps
            .compactMap { app -> (AppInfo, Int)? in
                let score = score(app, query: needle)
                return score > 0 ? (app, score) : nil
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
            }
            .map(\.0)
    }

    static func matches(_ app: AppInfo, query: String) -> Bool {
        score(app, query: query.lowercased()) > 0
    }

    /// Higher is a better match. Zero means "no match".
    ///
    /// The tiers matter more than the exact numbers: a prefix match on the name
    /// should always beat a substring match inside the bundle identifier.
    static func score(_ app: AppInfo, query: String) -> Int {
        guard !query.isEmpty else { return 1 }

        let name = app.name.lowercased()
        let bundleID = (app.bundleID ?? "").lowercased()

        if name == query { return 1000 }
        if name.hasPrefix(query) { return 900 - min(99, name.count - query.count) }
        if name.contains(" " + query) { return 800 }
        if name.contains(query) { return 700 - min(99, name.count - query.count) }
        if bundleID == query { return 650 }
        if bundleID.hasSuffix("." + query) { return 600 }
        if bundleID.contains(query) { return 500 }
        if app.path.lowercased().contains(query) { return 300 }
        if let ratio = subsequenceRatio(haystack: name, needle: query), ratio >= 0.6 {
            return 100 + Int(ratio * 100)
        }
        return 0
    }

    /// Fraction of the query's characters that appear in order inside `haystack`.
    private static func subsequenceRatio(haystack: String, needle: String) -> Double? {
        guard !needle.isEmpty else { return nil }
        var matched = 0
        var index = needle.startIndex
        for character in haystack where index < needle.endIndex {
            if character == needle[index] {
                matched += 1
                index = needle.index(after: index)
            }
        }
        guard index == needle.endIndex else { return nil }
        return Double(matched) / Double(needle.count)
    }

    // MARK: - Ordering

    /// Applies the user's sort mode.
    ///
    /// `manualOrder` and `recentOrder` are the identifier lists that define the
    /// two non-alphabetical modes. Anything missing from those lists falls back
    /// to alphabetical order and is appended at the end, so a newly installed
    /// app never disappears.
    static func sorted(
        _ apps: [AppInfo],
        mode: AppSortMode,
        manualOrder: [String] = [],
        recentOrder: [String] = []
    ) -> [AppInfo] {
        switch mode {
        case .name:
            return apps.sortedByName()

        case .manual:
            return ordered(apps, by: manualOrder)

        case .recent:
            let byRecency = ordered(apps, by: recentOrder)
            let ranked = Set(recentOrder)
            // Apps never launched come last, alphabetically.
            let never = byRecency.filter { !ranked.contains($0.id) }
            let rankedApps = byRecency.filter { ranked.contains($0.id) }
            return rankedApps + never.sortedByName()
        }
    }

    private static func ordered(_ apps: [AppInfo], by order: [String]) -> [AppInfo] {
        var position: [String: Int] = [:]
        for (index, id) in order.enumerated() where position[id] == nil {
            position[id] = index
        }
        return apps.sorted { lhs, rhs in
            switch (position[lhs.id], position[rhs.id]) {
            case let (left?, right?):
                return left < right
            case (nil, nil):
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }
    }
}
