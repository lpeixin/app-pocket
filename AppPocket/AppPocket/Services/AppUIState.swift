//
//  AppUIState.swift
//  AppPocket
//
//  Selection state that more than one scene needs to reach: the main window,
//  the menu bar extra and the menu commands.
//

import Combine
import Foundation

/// Which category the editor sheet should be showing.
nonisolated enum CategoryEditorRequest: Identifiable, Hashable {
    case create
    case edit(UUID)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let id): return id.uuidString
        }
    }
}

@MainActor
final class AppUIState: ObservableObject {
    @Published var selection: SidebarSelection = .default
    @Published var searchText: String = ""
    @Published var selectedAppIDs: Set<String> = []
    @Published var editorRequest: CategoryEditorRequest?

    /// Switches the sidebar to a category. Used by the menu bar shortcuts.
    func reveal(categoryID: UUID) {
        selection = .category(categoryID)
        searchText = ""
        selectedAppIDs.removeAll()
    }

    func reveal(smartGroup: SmartGroup) {
        selection = .smart(smartGroup)
        searchText = ""
        selectedAppIDs.removeAll()
    }
}
