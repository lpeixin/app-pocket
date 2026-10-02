//
//  ProbeMain.swift
//  AppPocket — offscreen UI verification harness
//
//  NOT part of the Xcode project. Compiled by hand against the app's own
//  sources (minus AppPocketApp.swift, whose @main would collide) and run from
//  inside the built .app so Bundle.main still resolves the localizations.
//
//  Renders the real SwiftUI views into a real NSWindow that is never ordered
//  front, then snapshots the hosting view with cacheDisplay(in:to:).
//  See ~/.workbuddy-ai/skills/offscreen-native-ui-verification.
//

import AppKit
import SwiftUI

@main
struct ProbeMain {
    static func main() {
        let environment = ProcessInfo.processInfo.environment
        guard let state = environment["APPPOCKET_UI_PROBE"] else {
            ProbeRunner.log("APPPOCKET_UI_PROBE is required")
            exit(2)
        }

        let outputDirectory = URL(
            fileURLWithPath: environment["APPPOCKET_UI_PROBE_OUT"] ?? NSTemporaryDirectory(),
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let width = Double(environment["APPPOCKET_UI_PROBE_WIDTH"] ?? "1040") ?? 1040
        let height = Double(environment["APPPOCKET_UI_PROBE_HEIGHT"] ?? "700") ?? 700
        let isDark = (environment["APPPOCKET_UI_PROBE_APPEARANCE"] ?? "light") == "dark"

        // NSApplication has to exist before any NSWindow / NSHostingView.
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        application.appearance = appearance

        let runner = ProbeRunner(
            state: state,
            outputDirectory: outputDirectory,
            size: NSSize(width: width, height: height),
            appearance: appearance
        )
        runner.run()
        exit(0)
    }
}

@MainActor
final class ProbeRunner {
    private let state: String
    private let outputDirectory: URL
    private let size: NSSize
    private let appearance: NSAppearance?

    private let catalog = AppCatalog()
    private let store: LibraryStore
    private let uiState = AppUIState()
    private let workDirectory: URL

    private var categoriesByRecipe: [String: UUID] = [:]
    private var emptyCategoryID: UUID?

    init(state: String, outputDirectory: URL, size: NSSize, appearance: NSAppearance?) {
        self.state = state
        self.outputDirectory = outputDirectory
        self.size = size
        self.appearance = appearance

        // Probe writes must never touch the real Application Support file.
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("apppocket-ui-probe", isDirectory: true)
        try? FileManager.default.removeItem(at: work)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        self.workDirectory = work
        self.store = LibraryStore(fileURL: work.appendingPathComponent("library.json"))
    }

    // MARK: - Entry

    func run() {
        log("state=\(state) size=\(Int(size.width))x\(Int(size.height))")

        // Keep the probe from registering a system-wide hot key.
        store.updateSettings { $0.globalHotKeyEnabled = false }

        catalog.start()
        waitFor { !self.catalog.isScanning && !self.catalog.apps.isEmpty }
        log("scanned \(catalog.apps.count) apps in \(String(format: "%.3f", catalog.lastScanDuration))s")
        log("language=\(Locale.current.identifier) preferred=\(Locale.preferredLanguages.prefix(2))")
        log("mainBundle=\(Bundle.main.bundlePath)")
        log("bundleLocalizations=\(Bundle.main.localizations.sorted())")
        log("bundlePreferred=\(Bundle.main.preferredLocalizations)")
        log("localized(sidebar.smartGroups)=\(NSLocalizedString("sidebar.smartGroups", comment: ""))")
        if let zh = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"),
           let zhBundle = Bundle(path: zh) {
            log("zh-Hans direct lookup=\(zhBundle.localizedString(forKey: "sidebar.smartGroups", value: nil, table: nil))")
        } else {
            log("no zh-Hans.lproj found in main bundle")
        }

        seedLibrary()
        present()
    }

    // MARK: - Seeding

    /// Builds a deterministic, realistic-looking library out of whatever apps
    /// happen to be installed, so every run produces the same categories.
    private func seedLibrary() {
        let recipes: [(name: String, symbol: String, keywords: [String])] = [
            (
                "开发工具",
                "chevron.left.forwardslash.chevron.right",
                ["xcode", "terminal", "iterm", "visual studio", "vscode", "sublime",
                 "nova", "intellij", "pycharm", "android studio", "docker", "sourcetree",
                 "postman", "insomnia", "simulator", "swift", "git", "warp", "zed"]
            ),
            (
                "设计与创意",
                "paintbrush.pointed.fill",
                ["figma", "sketch", "photoshop", "illustrator", "affinity", "pixelmator",
                 "blender", "final cut", "davinci", "keynote", "canva", "procreate",
                 "gimp", "inkscape", "color"]
            ),
            (
                "影音娱乐",
                "play.rectangle.fill",
                ["music", "spotify", "vlc", "iina", "quicktime", "podcast", "tv",
                 "netflix", "audacity", "handbrake", "elmedia", "game", "chess"]
            ),
            (
                "效率工具",
                "checklist",
                ["notes", "reminder", "calendar", "notion", "obsidian", "things",
                 "todoist", "fantastical", "bear", "craft", "raycast", "alfred",
                 "1password", "numbers", "pages", "mail", "messages", "preview"]
            ),
            (
                "常用",
                "star.fill",
                ["activity monitor", "calculator", "chess", "clock", "dictionary",
                 "font book", "photos", "safari", "stocks", "system settings",
                 "weather", "voice memos", "screenshot", "keychain", "disk utility"]
            ),
        ]

        let sorted = catalog.apps.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        var claimed: Set<String> = []
        for (index, recipe) in recipes.enumerated() {
            let members = sorted
                .filter { app in
                    guard !claimed.contains(app.id) else { return false }
                    let haystack = "\(app.name) \(app.bundleID ?? "") \(app.path)".lowercased()
                    return recipe.keywords.contains { haystack.contains($0) }
                }
                .prefix(20)
                .map(\.id)

            members.forEach { claimed.insert($0) }

            let category = try? store.createCategory(
                name: recipe.name,
                symbolName: recipe.symbol,
                colorHex: AppCategory.palette[index % AppCategory.palette.count],
                appIDs: members
            )
            if let category {
                categoriesByRecipe[recipe.name] = category.id
                log("category \(recipe.name): \(members.count) apps")
            }
        }

        // One deliberately empty category so the empty state is reviewable.
        if let empty = try? store.createCategory(
            name: "待整理",
            symbolName: "tray.full.fill",
            colorHex: AppCategory.palette[6 % AppCategory.palette.count],
            appIDs: []
        ) {
            emptyCategoryID = empty.id
        }

        // Give "Recent" something to show, and hide a couple of apps so the
        // Hidden smart group exists.
        for app in sorted.prefix(6) {
            store.noteLaunched(app.id)
        }
        store.setHidden(true, appIDs: sorted.suffix(3).map(\.id))
    }

    private var populatedCategoryID: UUID? {
        store.categories
            .filter { !$0.appIDs.isEmpty }
            .max { $0.appIDs.count < $1.appIDs.count }?
            .id
    }

    /// A category whose members sort near the top of the alphabet, so the
    /// editor/picker snapshots actually show checked rows without scrolling.
    private var earlyAlphabetCategoryID: UUID? {
        categoriesByRecipe["常用"]
    }

    // MARK: - States

    private func present() {
        switch state {
        case "all":
            uiState.selection = .smart(.all)
            render(launcher, name: "01-all-apps")

        case "all-dark":
            uiState.selection = .smart(.all)
            render(launcher, name: "02-all-apps-dark")

        case "narrow":
            uiState.selection = .smart(.all)
            render(launcher, name: "03-narrow-window")
        case "min-width":
            uiState.selection = .smart(.all)
            render(launcher, name: "03b-min-width")

        case "category":
            if let id = populatedCategoryID {
                uiState.selection = .category(id)
                log("category state -> \(store.category(id: id)?.name ?? "?")")
            }
            render(launcher, name: "04-category")

        case "empty-category":
            if let id = emptyCategoryID {
                uiState.selection = .category(id)
            }
            render(launcher, name: "05-empty-category")

        case "no-results":
            uiState.selection = .smart(.all)
            uiState.searchText = "qqzzxxnomatch"
            render(launcher, name: "06-no-search-results")

        case "uncategorized":
            uiState.selection = .smart(.uncategorized)
            render(launcher, name: "07-uncategorized")

        case "recent":
            uiState.selection = .smart(.recent)
            render(launcher, name: "08-recent")

        case "hidden":
            uiState.selection = .smart(.hidden)
            render(launcher, name: "09-hidden")

        case "search":
            uiState.selection = .smart(.all)
            uiState.searchText = "code"
            render(launcher, name: "10-search")

        case "selection":
            uiState.selection = .smart(.all)
            uiState.selectedAppIDs = Set(catalog.apps.prefix(3).map(\.id))
            render(launcher, name: "11-multi-select")

        case "editor":
            if let id = earlyAlphabetCategoryID {
                render(editorSheet(for: id), name: "12-category-editor", size: NSSize(width: 760, height: 560))
            }

        case "editor-new":
            render(editorSheet(for: nil), name: "13-category-editor-new", size: NSSize(width: 760, height: 560))

        case "picker":
            if let id = earlyAlphabetCategoryID {
                render(appPicker(for: id), name: "14-app-picker", size: NSSize(width: 520, height: 540))
            }

        case "settings":
            render(settingsView, name: "15-settings", size: NSSize(width: 620, height: 520))

        case "settings-dark":
            render(settingsView, name: "16-settings-dark", size: NSSize(width: 620, height: 520))

        default:
            log("unknown state \(state)")
        }
    }

    // MARK: - View composition

    private var launcher: some View {
        LauncherRootView()
            .environmentObject(store)
            .environmentObject(catalog)
            .environmentObject(uiState)
    }

    @ViewBuilder
    private func editorSheet(for id: UUID?) -> some View {
        CategoryEditorSheet(existing: id.flatMap { store.category(id: $0) })
            .environmentObject(store)
            .environmentObject(catalog)
    }

    @ViewBuilder
    private func appPicker(for id: UUID) -> some View {
        if let category = store.category(id: id) {
            AppPickerSheet(category: category)
                .environmentObject(store)
                .environmentObject(catalog)
        }
    }

    private var settingsView: some View {
        SettingsView()
            .environmentObject(store)
            .environmentObject(catalog)
    }

    // MARK: - Rendering

    private func render<V: View>(_ root: V, name: String, size explicit: NSSize? = nil) {
        let contentSize = explicit ?? size
        let frame = NSRect(origin: .zero, size: contentSize)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.toolbar = NSToolbar(identifier: "AppPocketProbeToolbar")
        window.toolbarStyle = .unified

        let hosting = NSHostingView(rootView: root)
        hosting.frame = frame
        window.contentView = hosting
        window.setContentSize(contentSize)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        settle(0.7)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        settle(0.5)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        let bounds = hosting.bounds
        // Content-only by default: window chrome is macOS's, not the app's.
        // `APPPOCKET_UI_PROBE_CHROME=1` captures the theme frame instead, which
        // is needed when a control lives in the toolbar (the Settings tab bar).
        let wantsChrome = ProcessInfo.processInfo.environment["APPPOCKET_UI_PROBE_CHROME"] == "1"
        let captureView = wantsChrome ? (window.contentView?.superview ?? hosting) : hosting
        let captureBounds = captureView.bounds
        guard let rep = captureView.bitmapImageRepForCachingDisplay(in: captureBounds) else {
            log("FAILED bitmap rep for \(name)")
            return
        }
        captureView.cacheDisplay(in: captureBounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            log("FAILED png encode for \(name)")
            return
        }

        let url = outputDirectory.appendingPathComponent("\(name).png")
        do {
            try data.write(to: url)
            log("wrote \(url.lastPathComponent) content=\(Int(bounds.width))x\(Int(bounds.height)) captured=\(Int(captureBounds.width))x\(Int(captureBounds.height)) px=\(rep.pixelsWide)x\(rep.pixelsHigh) windowFrame=\(Int(window.frame.width))x\(Int(window.frame.height))")
        } catch {
            log("write failed for \(name): \(error)")
        }
    }

    // MARK: - Run loop plumbing

    /// Pumps the main run loop, which is what drains the main dispatch queue and
    /// therefore lets main-actor continuations run.
    private func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func waitFor(timeout: TimeInterval = 40, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        if !condition() {
            log("timed out waiting for condition")
        }
    }

    nonisolated static func log(_ message: String) {
        FileHandle.standardError.write(Data("[probe] \(message)\n".utf8))
    }

    private func log(_ message: String) {
        Self.log(message)
    }
}
