//
//  IconCache.swift
//  AppPocket
//
//  Application icons, rendered off the main thread and memoised.
//

import AppKit

/// `NSImage` is not `Sendable`. The images produced here are created on a
/// background queue and never mutated afterwards, so handing them across the
/// boundary in a box is safe.
nonisolated struct IconBox: @unchecked Sendable {
    let image: NSImage
}

nonisolated enum IconRenderer {
    static func render(path: String, size: CGFloat) -> IconBox {
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: size, height: size)
        return IconBox(image: image)
    }
}

/// Caches icons by application identifier and pixel size.
///
/// Rendering an icon means hitting the disk and the icon services daemon, which
/// is far too slow to do inline while scrolling a 200-item grid.
@MainActor
final class IconCache {
    static let shared = IconCache()

    private let cache = NSCache<NSString, NSImage>()
    /// De-duplicates concurrent requests for the same icon.
    private var inFlight: [NSString: Task<IconBox, Never>] = [:]

    init() {
        cache.countLimit = 512
    }

    /// Synchronous lookup, for the first render pass of a tile.
    func cached(for appID: String, size: CGFloat) -> NSImage? {
        cache.object(forKey: Self.key(appID, size))
    }

    func image(for app: AppInfo, size: CGFloat) async -> NSImage {
        let key = Self.key(app.id, size)
        if let hit = cache.object(forKey: key) {
            return hit
        }
        if let existing = inFlight[key] {
            return (await existing.value).image
        }

        let path = app.path
        let task = Task<IconBox, Never> {
            await Task.detached(priority: .userInitiated) {
                IconRenderer.render(path: path, size: size)
            }.value
        }
        inFlight[key] = task

        let box = await task.value
        inFlight[key] = nil
        cache.setObject(box.image, forKey: key)
        return box.image
    }

    func clear() {
        cache.removeAllObjects()
    }

    private static func key(_ appID: String, _ size: CGFloat) -> NSString {
        "\(appID)|\(Int(size))" as NSString
    }
}
