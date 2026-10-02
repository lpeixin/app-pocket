//
//  CategoryDetailView.swift
//  AppPocket
//
//  The grid of applications for whatever the sidebar has selected.
//

import AppKit
import SwiftUI

struct CategoryDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var catalog: AppCatalog

    let selection: SidebarSelection
    @Binding var searchText: String
    @Binding var selectedAppIDs: Set<String>
    var onEditCategory: (AppCategory) -> Void
    var onCreateCategory: () -> Void
    /// Launches an app. The flag is "keep the launcher window open".
    var onLaunch: (AppInfo, Bool) -> Void

    @State private var focusedIndex = 0
    @State private var isShowingAppPicker = false
    @FocusState private var isGridFocused: Bool

    // MARK: - Derived state

    private var currentCategory: AppCategory? {
        selection.categoryID.flatMap { store.category(id: $0) }
    }

    /// Category names come from the user, so they are shown verbatim; the smart
    /// groups go through the localization table.
    private var titleText: String {
        if let category = currentCategory { return category.name }
        let key = selection.smartGroup?.titleKey ?? SmartGroup.all.titleKey
        return NSLocalizedString(key, comment: "")
    }

    private var apps: [AppInfo] {
        let base = LibrarySnapshot.apps(
            for: selection,
            allApps: catalog.apps,
            hiddenIDs: store.hiddenAppIDs,
            categories: store.categories,
            recentIDs: store.recentAppIDs
        )

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // While searching, relevance beats the user's chosen ordering.
            return AppQuery.filter(base, query: trimmed)
        }

        return AppQuery.sorted(
            base,
            mode: store.settings.sortMode,
            manualOrder: currentCategory?.appIDs ?? [],
            recentOrder: store.recentAppIDs
        )
    }

    private var subtitle: String {
        let count = apps.count
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(format: NSLocalizedString("detail.matchCount", comment: "Search result count"), count)
        }
        if currentCategory != nil {
            return String(format: NSLocalizedString("detail.appCount", comment: "Category app count"), count)
        }
        return String(format: NSLocalizedString("detail.appCountTotal", comment: "Total app count"), count, catalog.appCount)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selection) { _, _ in
            selectedAppIDs.removeAll()
            focusedIndex = 0
        }
        .onChange(of: apps.count) { _, newCount in
            if focusedIndex >= newCount { focusedIndex = max(0, newCount - 1) }
        }
        .sheet(isPresented: $isShowingAppPicker) {
            if let category = currentCategory {
                AppPickerSheet(category: category)
                    .environmentObject(store)
                    .environmentObject(catalog)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            headerBadge

            VStack(alignment: .leading, spacing: 1) {
                Text(titleText)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if currentCategory != nil {
                Button {
                    isShowingAppPicker = true
                } label: {
                    Label("detail.addApps", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("detail.addAppsHelp")
            }

            sortMenu
            moreMenu
            SearchField(text: $searchText)
        }
        .padding(.horizontal, Metrics.gridPadding)
        .frame(height: Metrics.headerHeight)
    }

    @ViewBuilder
    private var headerBadge: some View {
        if let category = currentCategory {
            Image(systemName: category.symbolName)
                .categoryBadge(color: Color(hex: category.colorHex), size: 30, corner: 8)
        } else if let group = selection.smartGroup {
            Image(systemName: group.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.gradient)
                )
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("detail.sortBy", selection: sortModeBinding) {
                ForEach(AppSortMode.allCases) { mode in
                    Label(LocalizedStringKey(mode.titleKey), systemImage: mode.symbolName)
                        .tag(mode)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("detail.iconSize", selection: iconSizeBinding) {
                ForEach(AppIconSize.allCases) { size in
                    Text(LocalizedStringKey(size.titleKey)).tag(size)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("detail.sortAndLayout")
    }

    private var moreMenu: some View {
        Menu {
            if let category = currentCategory {
                Button("sidebar.editCategory") { onEditCategory(category) }
                Button("sidebar.duplicateCategory") { store.duplicateCategory(id: category.id) }
                Divider()
                Button("action.delete", role: .destructive) {
                    store.deleteCategory(id: category.id)
                }
                Divider()
            }

            Button("detail.rescan") { catalog.refresh() }
                .disabled(catalog.isScanning)

            if selection.smartGroup == .hidden {
                Button("detail.unhideAll") { store.setAllHiddenVisible() }
                    .disabled(store.hiddenAppIDs.isEmpty)
            }

            if selection.smartGroup == .recent {
                Button("detail.clearRecent") { store.clearRecentHistory() }
                    .disabled(store.recentAppIDs.isEmpty)
            }

            Divider()

            Button("detail.newCategory") { onCreateCategory() }

            if store.canUndo {
                Divider()
                Button("detail.undo") { store.undo() }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("detail.more")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if catalog.isScanning && catalog.apps.isEmpty {
            loadingState
        } else if apps.isEmpty {
            emptyState
        } else {
            grid
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text("detail.scanning")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass",
                title: "empty.noSearchResults",
                message: "empty.noSearchResultsMessage",
                actionTitle: "search.clear"
            ) {
                searchText = ""
            }
        } else if selection.smartGroup == .hidden {
            EmptyStateView(
                symbol: "eye",
                title: "empty.noHiddenApps",
                message: "empty.noHiddenAppsMessage"
            )
        } else if selection.smartGroup == .uncategorized {
            EmptyStateView(
                symbol: "checkmark.circle",
                title: "empty.everythingCategorized",
                message: "empty.everythingCategorizedMessage"
            )
        } else if let category = currentCategory {
            EmptyStateView(
                symbol: "tray",
                title: "empty.emptyCategory",
                message: "empty.emptyCategoryMessage",
                actionTitle: "detail.addApps"
            ) {
                isShowingAppPicker = true
            }
            .id(category.id)
        } else {            EmptyStateView(
                symbol: "square.grid.2x2",
                title: "empty.noApps",
                message: "empty.noAppsMessage",
                actionTitle: "detail.rescan"
            ) {
                catalog.refresh()
            }
        }
    }

    private var grid: some View {
        GeometryReader { proxy in
            let columns = columnCount(for: proxy.size.width)
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: Metrics.tileSpacing),
                            count: columns
                        ),
                        spacing: Metrics.tileSpacing
                    ) {
                        ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                            AppTileView(
                                app: app,
                                side: store.settings.iconSize.side,
                                isSelected: selectedAppIDs.contains(app.id),
                                isFocused: isGridFocused && index == focusedIndex,
                                currentCategoryID: selection.categoryID,
                                onLaunch: { keepOpen in onLaunch(app, keepOpen) },
                                onToggleSelection: { toggleSelection(app) }
                            )
                            .id(app.id)
                        }
                    }
                    .padding(Metrics.gridPadding)
                }
                // Inset rather than overlay: the bar floats over the grid, but
                // the scrollable area grows so the last row can always be
                // scrolled clear of it.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    selectionBar
                }
                .onChange(of: focusedIndex) { _, newValue in
                    guard apps.indices.contains(newValue) else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        scroller.scrollTo(apps[newValue].id, anchor: nil)
                    }
                }
            }
            .focusable()
            .focused($isGridFocused)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                move(direction, columns: columns)
            }
            .onKeyPress(.return) {
                guard apps.indices.contains(focusedIndex) else { return .ignored }
                onLaunch(apps[focusedIndex], false)
                return .handled
            }
            .onKeyPress(.escape) {
                if !selectedAppIDs.isEmpty {
                    selectedAppIDs.removeAll()
                    return .handled
                }
                if !searchText.isEmpty {
                    searchText = ""
                    return .handled
                }
                return .ignored
            }
            .onAppear { isGridFocused = true }
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        if let fixed = store.settings.effectiveColumnCount { return fixed }
        let available = max(160, width - Metrics.gridPadding * 2)
        let tile = store.settings.iconSize.tileWidth + Metrics.tileSpacing
        return max(1, min(14, Int((available + Metrics.tileSpacing) / tile)))
    }

    private func move(_ direction: MoveCommandDirection, columns: Int) {
        guard !apps.isEmpty else { return }
        let step: Int
        switch direction {
        case .left: step = -1
        case .right: step = 1
        case .up: step = -columns
        case .down: step = columns
        default: return
        }
        let next = focusedIndex + step
        guard apps.indices.contains(next) else { return }
        focusedIndex = next
    }

    private func toggleSelection(_ app: AppInfo) {
        if selectedAppIDs.contains(app.id) {
            selectedAppIDs.remove(app.id)
        } else {
            selectedAppIDs.insert(app.id)
        }
    }

    // MARK: - Selection bar

    @ViewBuilder
    private var selectionBar: some View {
        if !selectedAppIDs.isEmpty {
            HStack(spacing: 12) {
                Text(String(format: NSLocalizedString("selection.count", comment: "Selected count"), selectedAppIDs.count))
                    .font(.system(size: 12, weight: .medium))

                Divider().frame(height: 16)

                if !store.categories.isEmpty {
                    Menu("selection.addTo") {
                        ForEach(store.categories) { category in
                            Button(category.name) {
                                store.add(appIDs: Array(selectedAppIDs), toCategory: category.id)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                if let categoryID = selection.categoryID {
                    Button("selection.removeFromCategory") {
                        store.remove(appIDs: Array(selectedAppIDs), fromCategory: categoryID)
                    }
                    .buttonStyle(.plain)
                }

                Button("selection.removeFromAll") {
                    store.removeFromAllCategories(appIDs: Array(selectedAppIDs))
                }
                .buttonStyle(.plain)

                Button(store.selectedAreAllHidden(selectedAppIDs) ? "selection.unhide" : "selection.hide") {
                    let shouldHide = !store.selectedAreAllHidden(selectedAppIDs)
                    store.setHidden(shouldHide, appIDs: Array(selectedAppIDs))
                }
                .buttonStyle(.plain)

                Divider().frame(height: 16)

                Button("selection.clear") { selectedAppIDs.removeAll() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeOut(duration: 0.18), value: selectedAppIDs.count)
        }
    }

    // MARK: - Bindings

    private var sortModeBinding: Binding<AppSortMode> {
        Binding(
            get: { store.settings.sortMode },
            set: { newValue in store.updateSettings { $0.sortMode = newValue } }
        )
    }

    private var iconSizeBinding: Binding<AppIconSize> {
        Binding(
            get: { store.settings.iconSize },
            set: { newValue in store.updateSettings { $0.iconSize = newValue } }
        )
    }
}
