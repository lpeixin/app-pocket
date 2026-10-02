//
//  AppCategory.swift
//  AppPocket
//
//  A user-created group of applications.
//

import Foundation

nonisolated struct AppCategory: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// SF Symbol shown in the sidebar.
    var symbolName: String
    /// `#RRGGBB`. Kept as a string so the document stays human-readable.
    var colorHex: String
    /// Ordered application identifiers.
    ///
    /// Order is meaningful: the grid follows it when the sort mode is set to
    /// "manual", which is how the user arranges a category by hand.
    var appIDs: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = AppCategory.defaultSymbol,
        colorHex: String = AppCategory.palette[0],
        appIDs: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.appIDs = appIDs
        self.createdAt = createdAt
    }

    var appCount: Int { appIDs.count }
    var isEmpty: Bool { appIDs.isEmpty }

    /// Trims whitespace and collapses internal runs of whitespace.
    static func normalizedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Case- and diacritic-insensitive comparison used for duplicate detection.
    static func namesCollide(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, symbolName, colorHex, appIDs, createdAt
    }

    /// Decoded leniently.
    ///
    /// The synthesised decoder calls `decode` for every non-optional property,
    /// so it ignores the defaults above and throws `keyNotFound` the moment the
    /// file predates a field. `LibraryFile.load` treats any decode failure as
    /// corruption: it renames the file to `library.json.corrupt` and hands the
    /// app an empty document. That turns "one new field in a future version"
    /// into silent, total loss of the user's categories — which is why every
    /// type in the document decodes field by field, with a fallback.
    ///
    /// A category that arrives damaged therefore degrades to a blank one rather
    /// than taking the rest of the library with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName)
            ?? AppCategory.defaultSymbol
        self.colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
            ?? AppCategory.palette[0]
        self.appIDs = try container.decodeIfPresent([String].self, forKey: .appIDs) ?? []
        // `try?`: a timestamp that no date strategy can parse throws rather than
        // returning nil, and `createdAt` is only used for ordering. This file
        // already has a history of date-strategy mismatches making every saved
        // library unreadable, so the field is guarded rather than trusted.
        self.createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
    }

    // MARK: - Presets

    static let defaultSymbol = "folder.fill"

    /// Ten colours that stay legible in both light and dark appearances.
    static let palette: [String] = [
        "#0A84FF", // blue
        "#30D158", // green
        "#FF9F0A", // orange
        "#FF375F", // pink
        "#BF5AF2", // purple
        "#64D2FF", // teal
        "#FFD60A", // yellow
        "#FF6482", // rose
        "#5E5CE6", // indigo
        "#8E8E93", // graphite
    ]

    /// A curated slice of SF Symbols that reads well at 13pt in a sidebar.
    static let symbolChoices: [String] = [
        "folder.fill", "star.fill", "heart.fill", "flame.fill",
        "hammer.fill", "wrench.and.screwdriver.fill", "paintbrush.fill", "cpu.fill",
        "terminal.fill", "curlybraces", "chevron.left.forwardslash.chevron.right", "ant.fill",
        "gamecontroller.fill", "arcade.stick", "puzzlepiece.fill", "dice.fill",
        "music.note", "waveform", "mic.fill", "headphones",
        "photo.fill", "camera.fill", "video.fill", "film.fill",
        "globe", "network", "cloud.fill", "envelope.fill",
        "book.fill", "newspaper.fill", "graduationcap.fill", "pencil.and.ruler.fill",
        "cart.fill", "bag.fill", "creditcard.fill", "gift.fill",
        "briefcase.fill", "chart.bar.fill", "calendar", "clock.fill",
        "map.fill", "airplane", "car.fill", "figure.walk",
        "fork.knife", "cup.and.saucer.fill", "leaf.fill", "pawprint.fill",
        "shield.lefthalf.filled", "lock.fill", "key.fill", "lightbulb.fill",
        "sparkles", "wand.and.stars", "cube.fill", "square.stack.3d.up.fill",
        "desktopcomputer", "display", "externaldrive.fill", "server.rack",
        "doc.text.fill", "tablecells", "list.bullet.rectangle", "checklist",
    ]
}
