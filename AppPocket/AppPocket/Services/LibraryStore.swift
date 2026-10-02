//
//  LibraryStore.swift
//  AppPocket
//
//  Category, membership and preference state, plus its persistence.
//

import Foundation
import Combine

nonisolated enum LibraryError: LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)
    case categoryNotFound

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return NSLocalizedString("error.emptyCategoryName", comment: "Category name is empty")
        case .duplicateName(let name):
            return String(
                format: NSLocalizedString("error.duplicateCategoryName", comment: "Duplicate category name"),
                name
            )
        case .categoryNotFound:
            return NSLocalizedString("error.categoryNotFound", comment: "Category no longer exists")
        }
    }
}

/// The single source of truth for everything the user has configured.
///
/// Every mutation snapshots the previous document onto an undo stack and writes
/// the file straight away. The document is a few kilobytes, so an atomic write
/// costs well under a millisecond and buys us "never lose the user's work".
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var document: LibraryDocument
    @Published private(set) var canUndo = false

    private let fileURL: URL
    private var undoStack: [LibraryDocument] = []
    private static let undoLimit = 30

    init(fileURL: URL = LibraryFile.defaultURL) {
        self.fileURL = fileURL
        self.document = LibraryFile.load(from: fileURL)
    }

    // MARK: - Reads

    var categories: [AppCategory] { document.categories }
    var settings: LauncherSettings { document.settings }
    var recentAppIDs: [String] { document.recentAppIDs }
    var hiddenAppIDs: Set<String> { Set(document.hiddenAppIDs) }
    var fileLocation: URL { fileURL }

    func category(id: UUID) -> AppCategory? { document.category(id: id) }

    func categoryIDs(containing appID: String) -> Set<UUID> {
        document.categoryIDs(containing: appID)
    }

    func isHidden(_ appID: String) -> Bool { document.isHidden(appID) }

    func appIDs(inCategory id: UUID) -> [String] {
        document.category(id: id)?.appIDs ?? []
    }

    /// Returns a validation failure for a proposed category name, or `nil` when
    /// the name is acceptable. `excluding` is the category being renamed.
    func validationError(for rawName: String, excluding excludedID: UUID? = nil) -> LibraryError? {
        let name = AppCategory.normalizedName(rawName)
        guard !name.isEmpty else { return .emptyName }
        let clash = document.categories.contains { candidate in
            candidate.id != excludedID && AppCategory.namesCollide(candidate.name, name)
        }
        return clash ? .duplicateName(name) : nil
    }

    // MARK: - Category lifecycle

    @discardableResult
    func createCategory(
        name: String,
        symbolName: String = AppCategory.defaultSymbol,
        colorHex: String = AppCategory.palette[0],
        appIDs: [String] = []
    ) throws -> AppCategory {
        if let error = validationError(for: name) { throw error }
        let category = AppCategory(
            name: AppCategory.normalizedName(name),
            symbolName: symbolName,
            colorHex: colorHex,
            appIDs: appIDs.uniqued()
        )
        mutate { $0.categories.append(category) }
        return category
    }

    func updateCategory(
        id: UUID,
        name: String,
        symbolName: String,
        colorHex: String,
        appIDs: [String]
    ) throws {
        guard let index = document.categoryIndex(id: id) else { throw LibraryError.categoryNotFound }
        if let error = validationError(for: name, excluding: id) { throw error }

        mutate { document in
            document.categories[index].name = AppCategory.normalizedName(name)
            document.categories[index].symbolName = symbolName
            document.categories[index].colorHex = colorHex
            document.categories[index].appIDs = appIDs.uniqued()
        }
    }

    func renameCategory(id: UUID, to name: String) throws {
        guard let category = document.category(id: id) else { throw LibraryError.categoryNotFound }
        try updateCategory(
            id: id,
            name: name,
            symbolName: category.symbolName,
            colorHex: category.colorHex,
            appIDs: category.appIDs
        )
    }

    func deleteCategory(id: UUID) {
        guard document.categoryIndex(id: id) != nil else { return }
        mutate { $0.categories.removeAll { $0.id == id } }
    }

    /// Creates a category with a generated name and palette slot, and drops the
    /// given apps straight in. Used by "New Category with this App".
    @discardableResult
    func createCategory(containing appIDs: [String]) throws -> AppCategory {
        let slot = document.categories.count
        return try createCategory(
            name: uniqueName(basedOn: NSLocalizedString("category.untitled", comment: "Default new category name")),
            symbolName: AppCategory.symbolChoices[slot % AppCategory.symbolChoices.count],
            colorHex: AppCategory.palette[slot % AppCategory.palette.count],
            appIDs: appIDs
        )
    }

    func duplicateCategory(id: UUID) {
        guard let source = document.category(id: id) else { return }
        var copy = source
        copy.id = UUID()
        copy.name = uniqueName(basedOn: source.name)
        copy.createdAt = Date()
        mutate { document in
            if let index = document.categoryIndex(id: id) {
                document.categories.insert(copy, at: index + 1)
            } else {
                document.categories.append(copy)
            }
        }
    }

    func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) {
        mutate { $0.categories.moveElements(fromOffsets: source, toOffset: destination) }
    }

    /// Moves a category to sit at the position of another one. Used by the
    /// sidebar's drop-to-reorder.
    func moveCategory(id: UUID, before targetID: UUID) {
        guard id != targetID,
              let from = document.categoryIndex(id: id),
              let to = document.categoryIndex(id: targetID) else { return }
        mutate { document in
            let moved = document.categories.remove(at: from)
            document.categories.insert(moved, at: to)
        }
    }

    /// Appends a numeric suffix until the name is free.
    private func uniqueName(basedOn base: String) -> String {
        let isTaken: (String) -> Bool = { candidate in
            self.document.categories.contains { AppCategory.namesCollide($0.name, candidate) }
        }
        guard isTaken(base) else { return base }

        var counter = 2
        while true {
            let candidate = String(
                format: NSLocalizedString("category.nameNumbered", comment: "Category name with a counter"),
                base, counter
            )
            if !isTaken(candidate) { return candidate }
            counter += 1
        }
    }

    // MARK: - Membership

    func add(appIDs: [String], toCategory id: UUID) {
        guard let index = document.categoryIndex(id: id), !appIDs.isEmpty else { return }
        mutate { document in
            var existing = document.categories[index].appIDs
            let known = Set(existing)
            existing.append(contentsOf: appIDs.filter { !known.contains($0) })
            document.categories[index].appIDs = existing
        }
    }

    func remove(appIDs: [String], fromCategory id: UUID) {
        guard let index = document.categoryIndex(id: id), !appIDs.isEmpty else { return }
        let removing = Set(appIDs)
        mutate { document in
            document.categories[index].appIDs.removeAll { removing.contains($0) }
        }
    }

    func toggle(appID: String, inCategory id: UUID) {
        if document.category(id: id)?.appIDs.contains(appID) == true {
            remove(appIDs: [appID], fromCategory: id)
        } else {
            add(appIDs: [appID], toCategory: id)
        }
    }

    func removeFromAllCategories(appIDs: [String]) {
        guard !appIDs.isEmpty else { return }
        let removing = Set(appIDs)
        mutate { document in
            for index in document.categories.indices {
                document.categories[index].appIDs.removeAll { removing.contains($0) }
            }
        }
    }

    /// Reorders an app inside a category, which is what "manual" sort mode shows.
    func moveApp(id appID: String, toIndex destination: Int, inCategory categoryID: UUID) {
        guard let index = document.categoryIndex(id: categoryID),
              let current = document.categories[index].appIDs.firstIndex(of: appID) else { return }
        let target = max(0, min(destination, document.categories[index].appIDs.count - 1))
        guard current != target else { return }
        mutate { document in
            let moved = document.categories[index].appIDs.remove(at: current)
            document.categories[index].appIDs.insert(moved, at: target)
        }
    }

    // MARK: - Hidden applications

    func setHidden(_ hidden: Bool, appIDs: [String]) {
        guard !appIDs.isEmpty else { return }
        let target = Set(appIDs)
        mutate { document in
            if hidden {
                let known = Set(document.hiddenAppIDs)
                document.hiddenAppIDs.append(contentsOf: appIDs.filter { !known.contains($0) })
            } else {
                document.hiddenAppIDs.removeAll { target.contains($0) }
            }
        }
    }

    func setAllHiddenVisible() {
        guard !document.hiddenAppIDs.isEmpty else { return }
        mutate { $0.hiddenAppIDs.removeAll() }
    }

    /// `true` when every one of the given apps is already hidden. Drives the
    /// Hide/Unhide label in the bulk action bar.
    func selectedAreAllHidden(_ appIDs: Set<String>) -> Bool {
        guard !appIDs.isEmpty else { return false }
        return appIDs.allSatisfy { document.isHidden($0) }
    }

    // MARK: - Launch history

    func noteLaunched(_ appID: String) {
        mutate(recordingUndo: false) { document in
            document.recentAppIDs.removeAll { $0 == appID }
            document.recentAppIDs.insert(appID, at: 0)
            if document.recentAppIDs.count > LibraryDocument.recentHistoryLimit {
                document.recentAppIDs.removeLast(document.recentAppIDs.count - LibraryDocument.recentHistoryLimit)
            }
        }
    }

    func clearRecentHistory() {
        guard !document.recentAppIDs.isEmpty else { return }
        mutate { $0.recentAppIDs.removeAll() }
    }

    // MARK: - Settings

    func updateSettings(_ mutateSettings: (inout LauncherSettings) -> Void) {
        mutate { mutateSettings(&$0.settings) }
    }

    // MARK: - Maintenance

    /// Drops identifiers for apps that are no longer installed.
    ///
    /// Refuses to run on an empty set: a scan that found nothing means the scan
    /// failed, not that the user uninstalled every app, and wiping their
    /// categories in that situation would be unrecoverable.
    func prune(keeping liveIDs: Set<String>) {
        guard !liveIDs.isEmpty else { return }
        var probe = document
        guard probe.prune(keeping: liveIDs) else { return }
        mutate(recordingUndo: false) { document in
            _ = document.prune(keeping: liveIDs)
        }
    }

    func reset() {
        mutate {
            $0.categories.removeAll()
            $0.hiddenAppIDs.removeAll()
            $0.recentAppIDs.removeAll()
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        document = previous
        canUndo = !undoStack.isEmpty
        save()
    }

    // MARK: - Import / export

    func exportData() throws -> Data {
        try LibraryCoding.encode(document)
    }

    /// Replaces the document with the contents of an exported file.
    func importDocument(from data: Data) throws {
        let incoming = try LibraryCoding.decode(data)
        mutate { $0 = incoming }
    }

    /// Used by the legacy migration.
    func replaceDocument(_ newDocument: LibraryDocument) {
        mutate { $0 = newDocument }
    }

    // MARK: - Persistence

    /// Applies a change, but only if it actually changes something.
    ///
    /// The no-op guard matters for more than tidiness. `@Published` fires on
    /// every assignment, so a binding that SwiftUI writes back to during a view
    /// update would otherwise publish, re-render, get written to again, and spin
    /// forever.
    private func mutate(recordingUndo: Bool = true, _ body: (inout LibraryDocument) -> Void) {
        let previous = document
        var updated = previous
        body(&updated)
        guard updated != previous else { return }

        if recordingUndo {
            pushUndoSnapshot(previous)
        }
        document = updated
        save()
    }

    private func pushUndoSnapshot(_ snapshot: LibraryDocument) {
        undoStack.append(snapshot)
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst(undoStack.count - Self.undoLimit)
        }
        canUndo = true
    }

    func save() {
        do {
            try LibraryFile.save(document, to: fileURL)
        } catch {
            NSLog("[AppPocket] Failed to save library: %@", String(describing: error))
        }
    }
}

// MARK: - Helpers

extension Array where Element: Hashable {
    /// Removes duplicates while preserving the original order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Array {
    /// `move(fromOffsets:toOffset:)` is defined by SwiftUI, which the data layer
    /// has no business importing. Same semantics, implemented here.
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { self[$0] }
        for index in source.sorted(by: >) {
            remove(at: index)
        }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = Swift.max(0, Swift.min(count, destination - removedBeforeDestination))
        insert(contentsOf: moving, at: insertionIndex)
    }
}
