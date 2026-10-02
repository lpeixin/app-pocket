//
//  AppPickerSheet.swift
//  AppPocket
//
//  Multi-select list used to put apps into a category.
//

import SwiftUI

struct AppPickerSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var catalog: AppCatalog
    @Environment(\.dismiss) private var dismiss

    let category: AppCategory

    @State private var searchText = ""

    private var candidates: [AppInfo] {
        let visible = catalog.apps.filter { !store.isHidden($0.id) }
        let sorted = AppQuery.sorted(visible, mode: .name)
        return AppQuery.filter(sorted, query: searchText)
    }

    private var memberIDs: Set<String> {
        Set(store.appIDs(inCategory: category.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 520, height: 540)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: category.symbolName)
                .categoryBadge(color: Color(hex: category.colorHex), size: 26, corner: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(category.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(
                    String(
                        format: NSLocalizedString("picker.selectedCount", comment: "Selected count"),
                        memberIDs.count
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()

            SearchField(text: $searchText)
                .frame(width: 190)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(candidates) { app in
                    row(for: app)
                }
            }
            .padding(.vertical, 6)
        }
        .overlay {
            if candidates.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "empty.noSearchResults",
                    message: "empty.noSearchResultsMessage"
                )
            }
        }
    }

    private func row(for app: AppInfo) -> some View {
        let isMember = memberIDs.contains(app.id)
        return Button {
            store.toggle(appID: app.id, inCategory: category.id)
        } label: {
            HStack(spacing: 10) {
                AppIconView(app: app, side: 26)

                VStack(alignment: .leading, spacing: 0) {
                    Text(app.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(app.path)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isMember ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !candidates.isEmpty {
                Button("picker.addAllResults") {
                    store.add(appIDs: candidates.map(\.id), toCategory: category.id)
                }
                .controlSize(.small)
            }

            Spacer()

            Button("action.done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
