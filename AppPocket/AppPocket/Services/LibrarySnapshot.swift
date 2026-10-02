//
//  LibrarySnapshot.swift
//  AppPocket
//
//  Pure functions that answer "which apps does this sidebar row show?".
//  Kept free of UI so the answers can be tested directly.
//

import Foundation

nonisolated enum LibrarySnapshot {

    /// Everything the grid may show, in the order the category stored it.
    static func apps(
        for selection: SidebarSelection,
        allApps: [AppInfo],
        hiddenIDs: Set<String>,
        categories: [AppCategory],
        recentIDs: [String]
    ) -> [AppInfo] {
        switch selection {
        case .smart(.all):
            return visibleApps(allApps, hiddenIDs: hiddenIDs)

        case .smart(.uncategorized):
            let categorized = Set(categories.flatMap(\.appIDs))
            return visibleApps(allApps, hiddenIDs: hiddenIDs)
                .filter { !categorized.contains($0.id) }

        case .smart(.recent):
            let byID = index(visibleApps(allApps, hiddenIDs: hiddenIDs))
            return recentIDs.compactMap { byID[$0] }

        case .smart(.hidden):
            return allApps.filter { hiddenIDs.contains($0.id) }.sortedByName()

        case .category(let categoryID):
            guard let category = categories.first(where: { $0.id == categoryID }) else { return [] }
            let byID = index(visibleApps(allApps, hiddenIDs: hiddenIDs))
            return category.appIDs.compactMap { byID[$0] }
        }
    }

    /// Count shown next to a sidebar row. Uses the same rule as the grid, so a
    /// badge never disagrees with what the user sees after clicking it.
    static func count(
        for group: SmartGroup,
        allApps: [AppInfo],
        hiddenIDs: Set<String>,
        categories: [AppCategory],
        recentIDs: [String]
    ) -> Int {
        apps(
            for: .smart(group),
            allApps: allApps,
            hiddenIDs: hiddenIDs,
            categories: categories,
            recentIDs: recentIDs
        ).count
    }

    static func visibleApps(_ apps: [AppInfo], hiddenIDs: Set<String>) -> [AppInfo] {
        apps.filter { !hiddenIDs.contains($0.id) }
    }

    private static func index(_ apps: [AppInfo]) -> [String: AppInfo] {
        Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
