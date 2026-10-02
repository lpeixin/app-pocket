//
//  LauncherRootView.swift
//  AppPocket
//
//  The main window: categories on the left, applications on the right.
//

import SwiftUI

struct LauncherRootView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var catalog: AppCatalog
    @EnvironmentObject private var uiState: AppUIState
    @Environment(\.openWindow) private var openWindow

    @State private var hasBootstrapped = false

    var body: some View {
        NavigationSplitView {
            CategorySidebarView(
                selection: $uiState.selection,
                onCreateCategory: { uiState.editorRequest = .create },
                onEditCategory: { uiState.editorRequest = .edit($0.id) }
            )
            .navigationSplitViewColumnWidth(
                min: Metrics.sidebarWidth.min,
                ideal: Metrics.sidebarWidth.ideal,
                max: Metrics.sidebarWidth.max
            )
        } detail: {
            CategoryDetailView(
                selection: uiState.selection,
                searchText: $uiState.searchText,
                selectedAppIDs: $uiState.selectedAppIDs,
                onEditCategory: { uiState.editorRequest = .edit($0.id) },
                onCreateCategory: { uiState.editorRequest = .create },
                onLaunch: launch
            )
        }
        .navigationTitle("AppPocket")
        .sheet(item: $uiState.editorRequest) { request in
            editorSheet(for: request)
        }
        .captureLauncherWindow()
        .task { await bootstrap() }
        .onChange(of: catalog.scanGeneration) { _, _ in
            // Deferred: `onChange` runs inside a view update, and mutating the
            // store there publishes changes from within that update.
            let liveIDs = Set(catalog.apps.map(\.id))
            Task { @MainActor in
                store.prune(keeping: liveIDs)
            }
        }
        .onChange(of: store.settings.globalHotKeyEnabled) { _, _ in
            Task { @MainActor in configureGlobalHotKey() }
        }
        .onChange(of: store.settings.globalHotKey) { _, _ in
            Task { @MainActor in configureGlobalHotKey() }
        }
        .onAppear {
            // Lets the hot key and the menu bar bring the window back after ⌘W.
            WindowBridge.shared.reopen = { openWindow(id: WindowID.launcher) }
        }
    }

    @ViewBuilder
    private func editorSheet(for request: CategoryEditorRequest) -> some View {
        switch request {
        case .create:
            CategoryEditorSheet(existing: nil)
                .environmentObject(store)
                .environmentObject(catalog)
        case .edit(let id):
            CategoryEditorSheet(existing: store.category(id: id))
                .environmentObject(store)
                .environmentObject(catalog)
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        catalog.start()
        await catalog.refreshAndWait()

        // Migration needs the scan results to translate legacy paths into
        // bundle identifiers, so it has to run after the first scan.
        LegacyMigrator.migrateIfNeeded(into: store, apps: catalog.apps)
        store.prune(keeping: Set(catalog.apps.map(\.id)))
        configureGlobalHotKey()
    }

    private func configureGlobalHotKey() {
        let settings = store.settings
        guard settings.globalHotKeyEnabled else {
            GlobalHotKeyCenter.shared.unregister()
            return
        }
        let registered = GlobalHotKeyCenter.shared.register(settings.globalHotKey) {
            WindowBridge.shared.toggle()
        }
        if !registered {
            // The combination is already taken by something else; put the switch
            // back rather than leaving a setting that does nothing.
            store.updateSettings { $0.globalHotKeyEnabled = false }
        }
    }

    // MARK: - Launching

    private func launch(_ app: AppInfo, keepWindowOpen: Bool) {
        store.noteLaunched(app.id)
        AppLauncher.open(app)

        guard !keepWindowOpen, store.settings.closeAfterLaunch else { return }
        // Let the target app come forward before the launcher gets out of the
        // way, otherwise the wrong window can end up in front.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            WindowBridge.shared.hideAfterLaunch()
        }
    }
}

enum WindowID {
    static let launcher = "launcher"
}
