//
//  LegacyMigrator.swift
//  AppPocket
//
//  Carries categories over from the build that stored them in `UserDefaults`.
//

import Foundation

@MainActor
enum LegacyMigrator {
    /// Converts legacy categories into the new document, once.
    ///
    /// The old build recorded membership as absolute paths; the new one keys on
    /// bundle identifiers. `apps` is used to translate one into the other, so
    /// the migration has to run after the first scan.
    ///
    /// - Returns: `true` when categories were imported.
    @discardableResult
    static func migrateIfNeeded(into store: LibraryStore, apps: [AppInfo]) -> Bool {
        guard store.categories.isEmpty else { return false }

        let legacy = LegacyLibrary.readCategories()
        guard !legacy.isEmpty else { return false }

        var idForPath: [String: String] = [:]
        for app in apps {
            idForPath[app.path] = app.id
        }

        var document = LibraryDocument()
        document.settings = store.settings

        for entry in legacy {
            let name = AppCategory.normalizedName(entry.name)
            guard !name.isEmpty else { continue }
            guard !document.categories.contains(where: { AppCategory.namesCollide($0.name, name) }) else {
                continue
            }
            let memberIDs = (entry.appPaths ?? []).compactMap { idForPath[$0] }.uniqued()
            let slot = document.categories.count
            document.categories.append(
                AppCategory(
                    name: name,
                    symbolName: symbol(for: name),
                    colorHex: AppCategory.palette[slot % AppCategory.palette.count],
                    appIDs: memberIDs
                )
            )
        }

        guard !document.categories.isEmpty else { return false }

        store.replaceDocument(document)
        LegacyLibrary.clear()
        NSLog("[AppPocket] Migrated %d categories from the previous build.", document.categories.count)
        return true
    }

    /// Picks a stable symbol from the curated list based on the name, so the
    /// imported categories do not all look alike.
    private static func symbol(for name: String) -> String {
        let checksum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return AppCategory.symbolChoices[checksum % AppCategory.symbolChoices.count]
    }
}
