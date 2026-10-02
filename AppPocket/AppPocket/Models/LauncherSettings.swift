//
//  LauncherSettings.swift
//  AppPocket
//
//  User preferences that live inside the library document, so a single JSON
//  file captures everything needed to reproduce a setup on another Mac.
//

import Foundation

nonisolated enum AppSortMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case name
    /// Follows the order the user arranged apps in a category.
    case manual
    case recent

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .name: return "sort.name"
        case .manual: return "sort.manual"
        case .recent: return "sort.recent"
        }
    }

    var symbolName: String {
        switch self {
        case .name: return "textformat.abc"
        case .manual: return "hand.draw"
        case .recent: return "clock.arrow.circlepath"
        }
    }
}

nonisolated enum AppIconSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var side: CGFloat {
        switch self {
        case .small: return 48
        case .medium: return 64
        case .large: return 84
        }
    }

    /// Total tile width, icon plus breathing room.
    var tileWidth: CGFloat { side + 28 }

    var titleKey: String {
        switch self {
        case .small: return "iconSize.small"
        case .medium: return "iconSize.medium"
        case .large: return "iconSize.large"
        }
    }
}

/// A global hot key, stored as a virtual key code plus Carbon modifier flags.
///
/// The raw values are duplicated here (rather than importing Carbon into the
/// model layer) so the document stays a plain data type.
nonisolated struct HotKeySpec: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let command: UInt32 = 0x0100
    static let shift: UInt32 = 0x0200
    static let option: UInt32 = 0x0800
    static let control: UInt32 = 0x1000

    /// `Space`, which is what Launchpad itself uses.
    private static let spaceKeyCode: UInt32 = 49

    static let `default` = HotKeySpec(
        keyCode: spaceKeyCode,
        modifiers: command | option
    )

    static let presets: [HotKeySpec] = [
        HotKeySpec(keyCode: spaceKeyCode, modifiers: command | option),
        HotKeySpec(keyCode: spaceKeyCode, modifiers: control | option),
        HotKeySpec(keyCode: spaceKeyCode, modifiers: command | shift),
        HotKeySpec(keyCode: spaceKeyCode, modifiers: option),
    ]

    /// Human-readable form, e.g. `⌥⌘Space`.
    var displayString: String {
        var result = ""
        if modifiers & HotKeySpec.control != 0 { result += "⌃" }
        if modifiers & HotKeySpec.option != 0 { result += "⌥" }
        if modifiers & HotKeySpec.shift != 0 { result += "⇧" }
        if modifiers & HotKeySpec.command != 0 { result += "⌘" }
        result += Self.name(for: keyCode)
        return result
    }

    private static func name(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 53: return "⎋"
        default:
            if let scalar = UnicodeScalar(keyCode + 65), keyCode < 26 {
                return String(Character(scalar))
            }
            return "#\(keyCode)"
        }
    }
}

nonisolated struct LauncherSettings: Codable, Hashable, Sendable {
    /// `0` means "fit as many columns as the window allows".
    var columnCount: Int = 0
    var iconSize: AppIconSize = .medium
    var sortMode: AppSortMode = .name
    /// Hide the launcher right after an app is launched. Option-click always
    /// keeps the window open regardless of this setting.
    var closeAfterLaunch: Bool = true
    var launchAtLogin: Bool = false
    var showMenuBarExtra: Bool = true
    var globalHotKeyEnabled: Bool = false
    var globalHotKey: HotKeySpec = .default

    /// Clamped to something a human would actually pick.
    var effectiveColumnCount: Int? {
        (3...12).contains(columnCount) ? columnCount : nil
    }
}

// MARK: - Lenient decoding
//
// `init(from:)` lives in an extension on purpose: declaring an initialiser in a
// struct's main body suppresses its memberwise initialiser, and `HotKeySpec`
// and `LauncherSettings` are both built with one (`HotKeySpec(keyCode:modifiers:)`,
// `LauncherSettings()`). `AppCategory` already declares an explicit initialiser,
// so its decoder can stay in the body.
//
// The extensions are `nonisolated` explicitly: `nonisolated` on the type does
// not carry into an extension, and a main actor-isolated `init(from:)` conflicts
// with the nonisolated `Decodable` requirement.

nonisolated extension HotKeySpec {
    /// Keys are spelled out so renaming a property cannot silently change the
    /// on-disk format.
    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers
    }

    /// Decoded leniently, like every other type in the document. The synthesised
    /// decoder calls `decode` for these non-optional properties and throws
    /// `keyNotFound` on a file written before a field existed — which takes the
    /// whole library down with it, because `LibraryFile.load` treats any decode
    /// failure as corruption. See `LibraryDocument` for the same reasoning.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.keyCode = try container.decodeIfPresent(UInt32.self, forKey: .keyCode)
            ?? HotKeySpec.default.keyCode
        self.modifiers = try container.decodeIfPresent(UInt32.self, forKey: .modifiers)
            ?? HotKeySpec.default.modifiers
    }
}

nonisolated extension LauncherSettings {
    private enum CodingKeys: String, CodingKey {
        case columnCount, iconSize, sortMode, closeAfterLaunch
        case launchAtLogin, showMenuBarExtra, globalHotKeyEnabled, globalHotKey
    }

    /// Decoded leniently, so a file written before a setting existed still
    /// loads. The synthesised decoder ignores property default values and throws
    /// `keyNotFound` instead, which `LibraryFile.load` would interpret as
    /// corruption and move the user's whole library aside.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.columnCount = try container.decodeIfPresent(Int.self, forKey: .columnCount) ?? 0
        // `try?` on the enums as well: an unknown raw value from a newer build
        // throws rather than returning nil, and a setting is not worth losing a
        // library over.
        self.iconSize = (try? container.decode(AppIconSize.self, forKey: .iconSize)) ?? .medium
        self.sortMode = (try? container.decode(AppSortMode.self, forKey: .sortMode)) ?? .name
        self.closeAfterLaunch =
            try container.decodeIfPresent(Bool.self, forKey: .closeAfterLaunch) ?? true
        self.launchAtLogin =
            try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.showMenuBarExtra =
            try container.decodeIfPresent(Bool.self, forKey: .showMenuBarExtra) ?? true
        self.globalHotKeyEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .globalHotKeyEnabled) ?? false
        self.globalHotKey =
            try container.decodeIfPresent(HotKeySpec.self, forKey: .globalHotKey) ?? .default
    }
}
