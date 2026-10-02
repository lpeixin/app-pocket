//
//  AppPocketApp.swift
//  AppPocket
//
//  A launcher for macOS 26, where Launchpad is no longer with us.
//

import AppKit
import SwiftUI

@main
struct AppPocketApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var store = LibraryStore()
    @StateObject private var catalog = AppCatalog()
    @StateObject private var uiState = AppUIState()

    var body: some Scene {
        Window("AppPocket", id: WindowID.launcher) {
            LauncherRootView()
                .environmentObject(store)
                .environmentObject(catalog)
                .environmentObject(uiState)
        }
        .defaultSize(width: 1040, height: 700)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            LauncherCommands(uiState: uiState, store: store, catalog: catalog)
        }

        MenuBarExtra(
            "AppPocket",
            systemImage: "square.grid.2x2.fill",
            isInserted: menuBarInserted
        ) {
            MenuBarContent()
                .environmentObject(store)
                .environmentObject(catalog)
                .environmentObject(uiState)
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(catalog)
        }
    }

    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { store.settings.showMenuBarExtra },
            set: { value in store.updateSettings { $0.showMenuBarExtra = value } }
        )
    }
}

// MARK: - Menu bar

struct MenuBarContent: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var catalog: AppCatalog
    @EnvironmentObject private var uiState: AppUIState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("menubar.openLauncher") { showLauncher() }
            .keyboardShortcut("o", modifiers: .command)

        Divider()

        Button("smart.all") {
            uiState.reveal(smartGroup: .all)
            showLauncher()
        }

        Button("smart.recent") {
            uiState.reveal(smartGroup: .recent)
            showLauncher()
        }

        if !store.hiddenAppIDs.isEmpty {
            Button("smart.hidden") {
                uiState.reveal(smartGroup: .hidden)
                showLauncher()
            }
        }

        if !store.categories.isEmpty {
            Divider()
            ForEach(store.categories.prefix(12)) { category in
                Button(category.name) {
                    uiState.reveal(categoryID: category.id)
                    showLauncher()
                }
            }
        }

        Divider()

        Button("menubar.newCategory") {
            uiState.editorRequest = .create
            showLauncher()
        }

        Button("menu.rescan") {
            catalog.refresh()
        }
        .disabled(catalog.isScanning)

        Divider()

        SettingsLink {
            Text("menubar.settings")
        }

        Button("menubar.quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func showLauncher() {
        NSApp.activate()
        if let window = WindowBridge.shared.window {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: WindowID.launcher)
        }
    }
}

// MARK: - Menu commands

struct LauncherCommands: Commands {
    @ObservedObject var uiState: AppUIState
    @ObservedObject var store: LibraryStore
    @ObservedObject var catalog: AppCatalog

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("menu.newCategory") {
                uiState.editorRequest = .create
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Divider()

            Button("menu.editCategory") {
                if let id = uiState.selection.categoryID {
                    uiState.editorRequest = .edit(id)
                }
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(uiState.selection.categoryID == nil)

            Button("menu.deleteCategory") {
                if let id = uiState.selection.categoryID {
                    store.deleteCategory(id: id)
                    uiState.selection = .smart(.all)
                }
            }
            .disabled(uiState.selection.categoryID == nil)

            Button("menu.duplicateCategory") {
                if let id = uiState.selection.categoryID {
                    store.duplicateCategory(id: id)
                }
            }
            .disabled(uiState.selection.categoryID == nil)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("menu.undo") { store.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndo)
        }

        CommandGroup(after: .sidebar) {
            Button("menu.selectAll") {
                uiState.selectedAppIDs = Set(catalog.apps.map(\.id))
            }
            .keyboardShortcut("a", modifiers: .command)

            Divider()

            Button("menu.rescan") { catalog.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(catalog.isScanning)
        }

        CommandGroup(replacing: .windowArrangement) {
            Button("menu.hideWindow") {
                WindowBridge.shared.hide()
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandMenu("menu.view") {
            ForEach(Array(SmartGroup.allCases.enumerated()), id: \.element.id) { index, group in
                if group.isAlwaysVisible || !store.hiddenAppIDs.isEmpty {
                    Button(LocalizedStringKey(group.titleKey)) {
                        uiState.reveal(smartGroup: group)
                    }
                    .keyboardShortcut(shortcut(for: index + 1), modifiers: .command)
                }
            }

            if !store.categories.isEmpty {
                Divider()
                ForEach(Array(store.categories.prefix(9).enumerated()), id: \.element.id) { index, category in
                    Button(category.name) {
                        uiState.reveal(categoryID: category.id)
                    }
                    .keyboardShortcut(shortcut(for: index + 5), modifiers: .command)
                }
            }
        }
    }

    private func shortcut(for number: Int) -> KeyEquivalent {
        KeyEquivalent(Character("\(number % 10)"))
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the launcher window must not quit the app: the menu bar extra and
    /// the global hot key stay available.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowBridge.shared.show()
        }
        return true
    }
}
