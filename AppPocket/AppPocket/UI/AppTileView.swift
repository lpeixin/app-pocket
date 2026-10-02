//
//  AppTileView.swift
//  AppPocket
//
//  One application in the grid.
//

import AppKit
import SwiftUI

/// The application's icon, or a monogram placeholder until it has loaded.
struct AppIconView: View {
    let app: AppInfo
    let side: CGFloat

    @State private var loaded: NSImage?

    private var resolved: NSImage? {
        loaded ?? IconCache.shared.cached(for: app.id, size: side)
    }

    var body: some View {
        Group {
            if let image = resolved {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder
            }
        }
        .frame(width: side, height: side)
        .task(id: "\(app.id)|\(Int(side))") {
            guard IconCache.shared.cached(for: app.id, size: side) == nil else { return }
            loaded = await IconCache.shared.image(for: app, size: side)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: side * Metrics.iconCornerRadiusRatio, style: .continuous)
            .fill(.background.secondary)
            .overlay {
                Text(app.monogram)
                    .font(.system(size: side * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: side * Metrics.iconCornerRadiusRatio, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

struct AppTileView: View {
    let app: AppInfo
    let side: CGFloat
    let isSelected: Bool
    let isFocused: Bool
    /// Set when the grid is showing a user category, which unlocks
    /// "remove from this category".
    let currentCategoryID: UUID?
    let onLaunch: (_ keepWindowOpen: Bool) -> Void
    let onToggleSelection: () -> Void

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var catalog: AppCatalog

    @State private var isHovering = false

    private var labelHeight: CGFloat { 28 }
    private var tileWidth: CGFloat { side + 30 }
    private var tileHeight: CGFloat { side + labelHeight + 26 }

    var body: some View {
        VStack(spacing: 4) {
            AppIconView(app: app, side: side)
                .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 1.5)

            Text(app.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(width: tileWidth - 12, height: labelHeight, alignment: .top)

            // Reserved slot keeps every tile the same height whether or not the
            // app happens to be running.
            Circle()
                .fill(Color.accentColor)
                .frame(width: 4, height: 4)
                .opacity(isRunning ? 1 : 0)
        }
        .padding(5)
        .frame(width: tileWidth, height: tileHeight)
        .tileSurface(isSelected: isSelected, isFocused: isFocused, isHovering: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.tileCornerRadius, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            let modifiers = NSEvent.modifierFlags
            if modifiers.contains(.command) {
                onToggleSelection()
            } else {
                onLaunch(modifiers.contains(.option))
            }
        }
        .draggable(AppDragPayload(appIDs: [app.id])) {
            dragPreview
        }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(app.name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .help(app.path)
    }

    private var isRunning: Bool {
        guard let bundleID = app.bundleID else { return false }
        return catalog.runningBundleIDs.contains(bundleID)
    }

    private var dragPreview: some View {
        HStack(spacing: 8) {
            AppIconView(app: app, side: 32)
            Text(app.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        Button("action.open") { onLaunch(false) }

        if isRunning {
            Button("action.quit") { AppLauncher.quit(app) }
        }

        Divider()

        Button("action.revealInFinder") { AppLauncher.reveal(app) }
        Button("action.copyPath") { AppLauncher.copyPath(app) }

        Divider()

        if !store.categories.isEmpty {
            Menu("action.addToCategory") {
                ForEach(store.categories) { category in
                    Toggle(category.name, isOn: membershipBinding(category.id))
                }
            }
        }

        Button("action.newCategoryWithApp") {
            // The generated name is de-duplicated, so this cannot fail in
            // practice; there is nothing useful to show the user if it did.
            _ = try? store.createCategory(containing: [app.id])
        }

        if let currentCategoryID, let category = store.category(id: currentCategoryID) {
            Button(
                String(
                    format: NSLocalizedString("action.removeFromCategory", comment: "Remove from category"),
                    category.name
                )
            ) {
                store.remove(appIDs: [app.id], fromCategory: currentCategoryID)
            }
        }

        Divider()

        Button(store.isHidden(app.id) ? "action.unhide" : "action.hide") {
            store.setHidden(!store.isHidden(app.id), appIDs: [app.id])
        }
    }

    private func membershipBinding(_ categoryID: UUID) -> Binding<Bool> {
        Binding(
            get: { store.categoryIDs(containing: app.id).contains(categoryID) },
            set: { shouldBeMember in
                let isMember = store.categoryIDs(containing: app.id).contains(categoryID)
                if shouldBeMember != isMember {
                    store.toggle(appID: app.id, inCategory: categoryID)
                }
            }
        )
    }
}
