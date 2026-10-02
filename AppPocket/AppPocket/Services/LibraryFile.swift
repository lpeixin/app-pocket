//
//  LibraryFile.swift
//  AppPocket
//
//  Reading and writing `library.json`.
//

import Foundation

/// One place that decides how the document is serialised.
///
/// Encoding and decoding must agree on the date strategy. They did not, once:
/// the file was written with ISO 8601 strings and read back expecting numeric
/// timestamps, so every saved library was unreadable on the next launch.
///
/// Timestamps keep fractional seconds so a document that is saved and reloaded
/// compares equal to the one that was saved.
nonisolated enum LibraryCoding {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = fractionalFormatter.date(from: text) { return date }
            if let date = plainFormatter.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 timestamp, got \"\(text)\""
            )
        }
        return decoder
    }

    static func encode(_ document: LibraryDocument) throws -> Data {
        try makeEncoder().encode(document)
    }

    static func decode(_ data: Data) throws -> LibraryDocument {
        do {
            return try makeDecoder().decode(LibraryDocument.self, from: data)
        } catch {
            // A file written by a build that used the default numeric dates.
            return try JSONDecoder().decode(LibraryDocument.self, from: data)
        }
    }
}

nonisolated enum LibraryFile {
    static let fileName = "library.json"

    /// `~/Library/Application Support/AppPocket`
    static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("AppPocket", isDirectory: true)
    }

    static var defaultURL: URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Loads the document, returning an empty one when the file is missing or
    /// unreadable. A corrupt file is preserved as `library.json.corrupt` rather
    /// than silently overwritten, so the user can recover it by hand.
    static func load(from url: URL) -> LibraryDocument {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        do {
            return try LibraryCoding.decode(try Data(contentsOf: url))
        } catch {
            let backup = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            NSLog("[AppPocket] library.json could not be read (%@); kept a copy at %@",
                  String(describing: error), backup.path)
            return .empty
        }
    }

    static func save(_ document: LibraryDocument, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try LibraryCoding.encode(document).write(to: url, options: .atomic)
    }
}

// MARK: - Legacy data

/// The previous build kept categories in `UserDefaults` keyed by *name*, with
/// membership recorded as absolute paths. This reads that shape so a user who
/// has already organised their apps does not start from zero.
nonisolated enum LegacyLibrary {
    static let categoriesKey = "CustomCategories"

    /// Mirrors the old `CustomCategory` struct.
    struct LegacyCategory: Decodable {
        let name: String
        let appPaths: [String]?
    }

    /// Every place the old build could have written its defaults.
    ///
    /// The old build was sandboxed, so its `UserDefaults` lived inside the app
    /// container. The current build is not sandboxed, so both locations are
    /// checked.
    static var candidatePlistURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(
                "Library/Containers/com.liupeixin.AppPocket.AppPocket/Data/Library/Preferences/com.liupeixin.AppPocket.AppPocket.plist"
            ),
            home.appendingPathComponent("Library/Preferences/com.liupeixin.AppPocket.AppPocket.plist"),
        ]
    }

    /// Reads legacy categories from `UserDefaults` first, then from the old
    /// container plist. Returns an empty array when there is nothing to migrate.
    static func readCategories() -> [LegacyCategory] {
        if let data = UserDefaults.standard.data(forKey: categoriesKey),
           let decoded = decode(data), !decoded.isEmpty {
            return decoded
        }

        for url in candidatePlistURLs {
            guard let dictionary = NSDictionary(contentsOf: url) else { continue }
            if let data = dictionary[categoriesKey] as? Data,
               let decoded = decode(data), !decoded.isEmpty {
                return decoded
            }
        }
        return []
    }

    /// Clears the legacy key so migration runs at most once.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: categoriesKey)
    }

    private static func decode(_ data: Data) -> [LegacyCategory]? {
        try? JSONDecoder().decode([LegacyCategory].self, from: data)
    }
}
