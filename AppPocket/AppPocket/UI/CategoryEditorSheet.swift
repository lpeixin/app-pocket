//
//  CategoryEditorSheet.swift
//  AppPocket
//
//  Create or edit a category: name, symbol, colour and members, all in one
//  place so organising never means bouncing between dialogs.
//

import SwiftUI

struct CategoryEditorSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var catalog: AppCatalog
    @Environment(\.dismiss) private var dismiss

    /// `nil` means "create a new category".
    let existing: AppCategory?

    @State private var name: String = ""
    @State private var symbol: String = AppCategory.defaultSymbol
    @State private var colorHex: String = AppCategory.palette[0]
    @State private var memberIDs: [String] = []
    @State private var searchText: String = ""
    @State private var isConfirmingDelete = false
    @FocusState private var isNameFocused: Bool

    private var isEditing: Bool { existing != nil }

    private var validationError: LibraryError? {
        store.validationError(for: name, excluding: existing?.id)
    }

    private var canSave: Bool { validationError == nil }

    private var candidates: [AppInfo] {
        let visible = catalog.apps.filter { !store.isHidden($0.id) }
        return AppQuery.filter(AppQuery.sorted(visible, mode: .name), query: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(alignment: .top, spacing: 0) {
                appearancePane
                    .frame(width: 268)
                Divider()
                membershipPane
            }
            .frame(maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 760, height: 560)
        .onAppear(perform: load)
        .alert("sidebar.deleteCategoryTitle", isPresented: $isConfirmingDelete) {
            Button("action.delete", role: .destructive) { performDelete() }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("sidebar.deleteCategoryMessageShort")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .categoryBadge(color: Color(hex: colorHex), size: 28, corner: 8)

            Text(isEditing ? "editor.titleEdit" : "editor.titleNew")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Text(
                String(
                    format: NSLocalizedString("editor.memberCount", comment: "Member count"),
                    memberIDs.count
                )
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Left pane

    private var appearancePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("editor.name")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("editor.namePlaceholder", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFocused)
                        .onSubmit { if canSave { save() } }

                    if let validationError {
                        Text(validationError.errorDescription ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("editor.symbol")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8),
                        spacing: 4
                    ) {
                        ForEach(AppCategory.symbolChoices, id: \.self) { candidate in
                            Button {
                                symbol = candidate
                            } label: {
                                Image(systemName: candidate)
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 24, height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(
                                                candidate == symbol
                                                    ? Color(hex: colorHex).opacity(0.22)
                                                    : Color.primary.opacity(0.05)
                                            )
                                    )
                                    .foregroundStyle(candidate == symbol ? Color(hex: colorHex) : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(candidate)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("editor.color")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5),
                        spacing: 6
                    ) {
                        ForEach(AppCategory.palette, id: \.self) { candidate in
                            Button {
                                colorHex = candidate
                            } label: {
                                Circle()
                                    .fill(Color(hex: candidate).gradient)
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(Color.primary.opacity(0.9), lineWidth: candidate == colorHex ? 2 : 0)
                                            .padding(-3)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    // MARK: - Right pane

    private var membershipPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchField(text: $searchText)
                    .frame(maxWidth: .infinity)

                Menu {
                    Button("editor.selectAllResults") {
                        addToMembers(candidates.map(\.id))
                    }
                    .disabled(candidates.isEmpty)

                    Button("editor.clearSelection") {
                        memberIDs.removeAll()
                    }
                    .disabled(memberIDs.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(candidates) { app in
                        membershipRow(app)
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
    }

    private func membershipRow(_ app: AppInfo) -> some View {
        let isMember = memberIDs.contains(app.id)
        return Button {
            if isMember {
                memberIDs.removeAll { $0 == app.id }
            } else {
                memberIDs.append(app.id)
            }
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
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if isEditing {
                Button("action.delete", role: .destructive) {
                    isConfirmingDelete = true
                }
            }

            Spacer()

            Button("action.cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button(isEditing ? "action.save" : "action.create") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Actions

    private func load() {
        guard let existing else {
            name = ""
            symbol = AppCategory.symbolChoices[store.categories.count % AppCategory.symbolChoices.count]
            colorHex = AppCategory.palette[store.categories.count % AppCategory.palette.count]
            memberIDs = []
            isNameFocused = true
            return
        }
        name = existing.name
        symbol = existing.symbolName
        colorHex = existing.colorHex
        memberIDs = existing.appIDs
    }

    private func addToMembers(_ ids: [String]) {
        var known = Set(memberIDs)
        for id in ids where known.insert(id).inserted {
            memberIDs.append(id)
        }
    }

    private func save() {
        guard canSave else { return }
        do {
            if let existing {
                try store.updateCategory(
                    id: existing.id,
                    name: name,
                    symbolName: symbol,
                    colorHex: colorHex,
                    appIDs: memberIDs
                )
            } else {
                try store.createCategory(
                    name: name,
                    symbolName: symbol,
                    colorHex: colorHex,
                    appIDs: memberIDs
                )
            }
            dismiss()
        } catch {
            NSSound.beep()
        }
    }

    private func performDelete() {
        guard let existing else { return }
        store.deleteCategory(id: existing.id)
        dismiss()
    }
}
