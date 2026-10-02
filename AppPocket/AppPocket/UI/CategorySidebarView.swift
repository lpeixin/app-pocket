//
//  CategorySidebarView.swift
//  AppPocket
//
//  The category list on the left.
//

import SwiftUI

struct CategorySidebarView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var catalog: AppCatalog

    @Binding var selection: SidebarSelection
    var onCreateCategory: () -> Void
    var onEditCategory: (AppCategory) -> Void

    @State private var dropTarget: SidebarSelection?
    @State private var pendingDeletion: AppCategory?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var renameTarget: AppCategory?

    private var smartGroups: [SmartGroup] {
        SmartGroup.allCases.filter { $0.isAlwaysVisible || !store.hiddenAppIDs.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    ForEach(smartGroups) { group in
                        smartRow(group)
                    }
                } header: {
                    Text("sidebar.smartGroups")
                }

                Section {
                    ForEach(store.categories) { category in
                        categoryRow(category)
                    }
                } header: {
                    Text("sidebar.myCategories")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
            footer
        }
        .alert(
            "sidebar.deleteCategoryTitle",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { category in
            Button("action.delete", role: .destructive) {
                deleteCategory(category)
            }
            Button("action.cancel", role: .cancel) {}
        } message: { category in
            Text(
                String(
                    format: NSLocalizedString("sidebar.deleteCategoryMessage", comment: "Delete confirmation"),
                    category.name,
                    category.appCount
                )
            )
        }
        .alert("sidebar.renameTitle", isPresented: $isRenaming) {
            TextField("category.name", text: $renameText)
            Button("action.cancel", role: .cancel) { renameTarget = nil }
            Button("action.rename") { commitRename() }
        } message: {
            Text("sidebar.renameMessage")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func smartRow(_ group: SmartGroup) -> some View {
        HStack(spacing: 8) {
            Image(systemName: group.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(group == .hidden ? Color.secondary : Color.accentColor)
                .frame(width: 20)

            Text(LocalizedStringKey(group.titleKey))
                .lineLimit(1)

            Spacer(minLength: 4)

            CountBadge(count: count(for: group))
        }
        .tag(SidebarSelection.smart(group))
        .listRowBackground(rowBackground(for: .smart(group)))
        .dropDestination(for: AppDragPayload.self) { payloads, _ in
            assign(payloads, to: .smart(group))
        } isTargeted: { targeted in
            dropTarget = targeted ? .smart(group) : nil
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: AppCategory) -> some View {
        HStack(spacing: 8) {
            Image(systemName: category.symbolName)
                .categoryBadge(color: Color(hex: category.colorHex))

            Text(category.name)
                .lineLimit(1)

            Spacer(minLength: 4)

            CountBadge(count: category.appCount)
        }
        .tag(SidebarSelection.category(category.id))
        .listRowBackground(rowBackground(for: .category(category.id)))
        .draggable(CategoryDragPayload(categoryID: category.id)) {
            HStack(spacing: 6) {
                Image(systemName: category.symbolName)
                    .categoryBadge(color: Color(hex: category.colorHex), size: 16, corner: 5)
                Text(category.name).font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
        }
        .dropDestination(for: AppDragPayload.self) { payloads, _ in
            assign(payloads, to: .category(category.id))
        } isTargeted: { targeted in
            dropTarget = targeted ? .category(category.id) : nil
        }
        .dropDestination(for: CategoryDragPayload.self) { payloads, _ in
            guard let moved = payloads.first else { return false }
            store.moveCategory(id: moved.categoryID, before: category.id)
            return true
        }
        .contextMenu {
            Button("sidebar.editCategory") { onEditCategory(category) }
            Button("sidebar.renameCategory") { beginRename(category) }
            Divider()
            Button("sidebar.duplicateCategory") { store.duplicateCategory(id: category.id) }
            Divider()
            Button("sidebar.deleteCategory", role: .destructive) { pendingDeletion = category }
        }
    }

    @ViewBuilder
    private func rowBackground(for target: SidebarSelection) -> some View {
        if dropTarget == target {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.22))
        } else {
            Color.clear
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onCreateCategory) {
                Label("sidebar.newCategory", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("sidebar.newCategoryHelp")

            Spacer()

            if catalog.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            } else {
                Text("\(catalog.appCount)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .help("sidebar.appCountHelp")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func count(for group: SmartGroup) -> Int {
        LibrarySnapshot.count(
            for: group,
            allApps: catalog.apps,
            hiddenIDs: store.hiddenAppIDs,
            categories: store.categories,
            recentIDs: store.recentAppIDs
        )
    }

    /// Apps dropped on a category join it; dropped on "Uncategorized" they leave
    /// every category. The other smart groups are read-only views.
    private func assign(_ payloads: [AppDragPayload], to target: SidebarSelection) -> Bool {
        let appIDs = payloads.flatMap(\.appIDs)
        guard !appIDs.isEmpty else { return false }

        switch target {
        case .category(let categoryID):
            store.add(appIDs: appIDs, toCategory: categoryID)
            return true
        case .smart(.uncategorized):
            store.removeFromAllCategories(appIDs: appIDs)
            return true
        default:
            return false
        }
    }

    private func beginRename(_ category: AppCategory) {
        renameTarget = category
        renameText = category.name
        isRenaming = true
    }

    private func commitRename() {
        defer { renameTarget = nil }
        guard let target = renameTarget else { return }
        do {
            try store.renameCategory(id: target.id, to: renameText)
        } catch {
            // A rejected name simply leaves the old one in place; the editor
            // sheet is where the user gets a detailed explanation.
            NSSound.beep()
        }
    }

    private func deleteCategory(_ category: AppCategory) {
        if selection == .category(category.id) {
            selection = .smart(.all)
        }
        store.deleteCategory(id: category.id)
        pendingDeletion = nil
    }
}

/// Small grey number shown at the trailing edge of a sidebar row.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(Color.primary.opacity(0.06))
            )
    }
}
