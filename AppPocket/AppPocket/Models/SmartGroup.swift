//
//  SmartGroup.swift
//  AppPocket
//
//  Virtual categories that are computed rather than stored.
//

import Foundation

/// Built-in groupings that always exist and cannot be deleted.
nonisolated enum SmartGroup: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    /// Every visible application.
    case all
    /// Visible applications that belong to no user category.
    case uncategorized
    /// Most recently launched applications, newest first.
    case recent
    /// Applications the user hid from the main grid.
    case hidden

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "smart.all"
        case .uncategorized: return "smart.uncategorized"
        case .recent: return "smart.recent"
        case .hidden: return "smart.hidden"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .uncategorized: return "tray.fill"
        case .recent: return "clock.arrow.circlepath"
        case .hidden: return "eye.slash.fill"
        }
    }

    /// The hidden group is only worth showing once something has been hidden.
    var isAlwaysVisible: Bool {
        self != .hidden
    }

    var supportsEditing: Bool { false }

    /// The hidden group is the only one where destructive actions are expected,
    /// so it does not offer "add to category" bulk actions.
    var allowsBulkAssignment: Bool { self != .hidden }
}

/// What the sidebar currently has selected.
nonisolated enum SidebarSelection: Hashable, Sendable {
    case smart(SmartGroup)
    case category(UUID)

    static let `default` = SidebarSelection.smart(.all)

    var smartGroup: SmartGroup? {
        if case .smart(let group) = self { return group }
        return nil
    }

    var categoryID: UUID? {
        if case .category(let id) = self { return id }
        return nil
    }
}
