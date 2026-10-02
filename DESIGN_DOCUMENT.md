# AppPocket — Software Design Document

**Status:** reflects the code as of the 2026-09-24 refactor.
**Supersedes:** the previous revision, which described `PocketLauncher` — a design that
was partly never built and partly removed. See [Errata](#errata) first.

---

## Errata

The previous revision of this document was written before the code existed. Several of
its claims were never true, and a few became false when the refactor landed. They are
recorded here rather than quietly deleted, because the next person to read this file
needs to know which parts of the old plan were abandoned and why.

| Previous claim | What is actually true |
|---|---|
| Product name `PocketLauncher` | The product is **AppPocket** (bundle id `com.liupeixin.AppPocket.AppPocket`). The old name survived only in stale UI tests, which have been deleted. |
| Persistence via **Core Data**, entities `AppEntity` / `CategoryEntity` / `UserPreferencesEntity` | **The Core Data layer was never wired to anything.** `CoreDataStack.shared`, `AppRepository` and the `.xcdatamodeld` existed but were never referenced from a view; categories actually lived in `UserDefaults` under the key `"CustomCategories"`, keyed by absolute path. The refactor deleted the whole stack and replaced it with a versioned JSON document. |
| "Optional CloudKit synchronization" | CloudKit was a placeholder: `NSPersistentCloudKitContainer` was constructed and never synchronised, and there was no entitlement. Removed. |
| `AppIndexer`, `FileSystemMonitor` using **FSEvents** | FSEvents was never used. The old build re-scanned every root on a 3-second timer. The refactor uses `DispatchSource.makeFileSystemObjectSource` per directory with a 900 ms debounce, and a 90 s polling fallback. |
| "Background Service: `SMLoginItemSetEnabled`" / `LoginHelper` helper app | No helper app exists or is needed. Launch at login uses `SMAppService.mainApp` from the main bundle. |
| "Global hotkey registration" (listed as a feature) | Was not implemented. Now implemented with Carbon `RegisterEventHotKey`. |
| `SceneDelegate` | SwiftUI lifecycle only; there is no `SceneDelegate`. |
| `SettingsManager`, `DataMigrationManager`, `CloudKitManager`, `LaunchServicesInterface`, `IconExtractor`, `AppUsageTracker`, `DragAndDropHandler` as separate types | None of these types ever existed. Their responsibilities are now covered by the concrete types listed under [Modules](#modules). |
| "UI Tests: window management, drag-and-drop UX, search workflow" | The UI test target contained 448 lines driving a window named `"PocketLauncher"` — a window that does not exist. Every test in it would have failed. Deleted and replaced with a two-case launch smoke test. |
| "App Sandbox configured (if applicable)" | See [Security and distribution](#security-and-distribution). The sandbox **cannot** be on, and that is a deliberate decision with a stated cost. |
| "`LibraryDocument.init(from:)` decodes leniently … so an older file simply loads with defaults" | True of the root document only. `LauncherSettings`, `AppCategory` and `HotKeySpec` used the **synthesised** `Codable`, which ignores property default values, so a file written before any one of their fields existed failed to decode entirely — and `LibraryFile.load` treats that as corruption. The claim was verified false by linking the real model files and decoding a document with one field removed: `keyNotFound: 'colorHex'`, `keyNotFound: 'columnCount'`, `keyNotFound: 'modifiers'`. All three types now hand-write `init(from:)`; `LibraryFormatTests` covers it. |

Two further corrections that are not errata but were decided during the refactor and
should be read as the current position:

- **Dead code was the norm, not the exception.** Four competing launcher views
  (`ContentView`, `SimpleLauncherView`, `DirectLauncherView`, `TestLauncherView`) existed
  and `AppPocketApp.body` pointed straight at `TestLauncherView()`. The other three were
  unreachable. They have been deleted; there is now exactly one root view.
- **Categories were stored by absolute path.** Moving an app between folders silently
  dropped it from every category. Membership is now keyed by bundle identifier, falling
  back to the path only when a bundle declares no identifier at all.

---

## Overview

macOS 26 removed Launchpad. AppPocket is a local-only replacement: a single window that
lists every installed application and lets the user organise them into their own
categories.

"Local-only" is a design constraint, not an accident. The app has no network code, no
account, no analytics, and no third-party dependencies. It reads `Info.plist` files and
writes one JSON file.

### What it does

- Lists every application in the four standard locations, with real icons.
- Four smart groups that are computed, not stored: **All**, **Uncategorized**,
  **Recent**, **Hidden**.
- User-defined categories with a name, an SF Symbol, a colour, and an ordered member list.
- Create / edit / rename / duplicate / reorder / delete categories.
- Assign apps by drag, by context menu, or in bulk from a multi-select action bar.
- Search with a relevance ranking, not just a substring filter.
- Menu bar extra and an optional global hot key, so the launcher is reachable without
  hunting for the Dock.
- Six languages: `en`, `zh-Hans`, `ja`, `de`, `fr`, `es`.

### Technology stack

| Concern | Choice |
|---|---|
| Language | Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES` |
| UI | SwiftUI (`Window`, `Settings`, `MenuBarExtra` scenes) |
| Persistence | A versioned JSON document (`library.json`), not a database |
| App discovery | `FileManager` directory walk + `Bundle(url:)` metadata |
| Change detection | `DispatchSource.makeFileSystemObjectSource`, debounced |
| Icons | `NSWorkspace.icon(forFile:)`, memoised in `NSCache` |
| Launch at login | `SMAppService.mainApp` |
| Global hot key | Carbon `RegisterEventHotKey` |
| Minimum OS | macOS 14.0 |

### Why JSON instead of Core Data

The document is a few kilobytes. Choosing a file over a database buys four things that
mattered more than query power:

1. **No migration tooling.** A `.xcdatamodeld` needs a version for every schema change.
   Every type in the document decodes field by field, with `decodeIfPresent` and an
   explicit fallback, so a file written before a field existed still loads and the new
   field takes its default. This is **not** free: the synthesised `Codable` conformance
   does the opposite (it ignores property default values and throws `keyNotFound`), so
   each new type has to opt in deliberately. See
   [Lenient decoding](#lenient-decoding) and `LibraryFormatTests`.
2. **Undo is free.** Every mutation pushes the previous document onto a stack — it is a
   value type, so the snapshot is a copy, not a diff.
3. **A corrupt file is recoverable.** A `library.json` that fails to decode is renamed to
   `library.json.corrupt` rather than overwritten, so the user's categories are still on
   disk to be repaired by hand. Only one generation is kept, though — the existing
   `.corrupt` file is deleted before the new one is moved into place, so a second failure
   destroys the first rescue copy. See [Known limitations](#known-limitations).
4. **It is diffable.** `git diff` on the user's library actually means something.

---

## Architecture

Three layers, plus the system frameworks. There is no dependency injection container and
no view-model-per-screen; the shared state lives in three `ObservableObject`s injected
through the SwiftUI environment.

```
┌──────────────────────────────────────────────────────────┐
│ UI                UI/*.swift                             │
│   LauncherRootView → CategorySidebarView + CategoryDetailView
│   Sheets: CategoryEditorSheet, AppPickerSheet            │
│   SettingsView (4 tabs)                                  │
├──────────────────────────────────────────────────────────┤
│ State             Services/AppUIState, LibraryStore,      │
│                   AppCatalog   (@MainActor ObservableObject)
├──────────────────────────────────────────────────────────┤
│ Pure logic        Services/AppQuery, LibrarySnapshot,     │
│                   Models/*   (no UI, no I/O, unit-tested) │
├──────────────────────────────────────────────────────────┤
│ I/O & system      Services/AppScanner, IconCache,         │
│                   LibraryFile, DirectoryWatcher,          │
│                   AppLauncher, LaunchAtLogin,             │
│                   GlobalHotKeyCenter, WindowBridge        │
└──────────────────────────────────────────────────────────┘
```

The important structural decision is the third row. **Filtering, ordering and grouping
are pure functions over value types.** `AppQuery.filter` / `.sorted` and
`LibrarySnapshot.apps(for:)` take plain inputs and return plain outputs, so the sidebar's
counts and the grid's contents can be tested without a window, a run loop, or a
`@MainActor` hop. `LibrarySnapshotTests` asserts that the number next to a sidebar row
equals the number of tiles the grid would show for it — the two are computed by different
code paths, so that test is meaningful.

### Concurrency model

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes every type main-actor isolated unless
it says otherwise. That is the right default for a UI app, but it means the boundary has
to be explicit:

- **`nonisolated`** marks the types that are pure or off-main: `AppInfo`, `AppCategory`,
  `LibraryDocument`, `SmartGroup`, `LauncherSettings`, `LibraryError`, `AppScanner`,
  `AppQuery`, `LibrarySnapshot`, `LibraryCoding`, `IconRenderer`.
- **`Task.detached(priority: .userInitiated)`** runs the directory walk. `NSImage` is not
  `Sendable`, so icons cross the boundary in `IconBox`, a `@unchecked Sendable` wrapper
  around an immutable image.
- **Everything else is `@MainActor`.** No locks, no `DispatchQueue` except for one
  deliberate `asyncAfter` that lets a launched app come forward before the launcher hides.
- **`nonisolated extension UTType`** — `Transferable.transferRepresentation` is a
  nonisolated static requirement that reads the custom UTTypes.

Two patterns recur because they are easy to get wrong:

```swift
// Wrong: reads a captured weak var from concurrent code (a Swift 6 error).
center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
    Task { @MainActor in self?.refresh() }
}

// Right: resolve to a strong let before hopping.
center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
    guard let self else { return }
    Task { @MainActor in self.refresh() }
}
```

```swift
// Wrong: @Published fires on every assignment, so a binding SwiftUI writes back
// during a view update re-publishes and the view re-renders forever.
document = updated

// Right: no-op mutations are dropped.
guard updated != previous else { return }
```

The second one is not hypothetical. Before the guard was added, a run produced
**2,532,912** `Publishing changes from within view updates is not allowed` warnings and
hung the test host for 344 seconds. `LibraryStore.mutate` is the single funnel for every
mutation precisely so that this check exists in exactly one place.

---

## Data model

### `LibraryDocument` — the root of `library.json`

```swift
nonisolated struct LibraryDocument: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var categories: [AppCategory] = []
    var hiddenAppIDs: [String] = []
    var recentAppIDs: [String] = []
    var settings: LauncherSettings = .init()

    static let recentHistoryLimit = 60

    mutating func prune(keeping liveIDs: Set<String>) -> Bool   // true if it changed
}
```

`AppCategory`:

```swift
nonisolated struct AppCategory: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var symbolName: String      // SF Symbol
    var colorHex: String        // "#RRGGBB", from a 10-entry palette
    var appIDs: [String]        // bundle identifiers, in the user's order
    var createdAt: Date
}
```

Two things are deliberately *not* stored:

- **Category membership per app.** An app's categories are derived by scanning
  `categories`, so there is no second copy to keep in sync.
- **Which smart group an app is in.** `Uncategorized` is "not a member of any category",
  computed on read. Storing it would create a state that can disagree with reality.

`hiddenAppIDs` and `recentAppIDs` are stored flat, not on `AppInfo`, because `AppInfo` is
a product of the scanner and is replaced wholesale on every scan.

### Lenient decoding

Every type in the document hand-writes `init(from:)` and reads each field with
`decodeIfPresent`, falling back to a default. None of them rely on the synthesised
`Codable` conformance, and that is a requirement rather than a style preference:

> **The synthesised decoder ignores property default values.** For a non-optional
> property it emits `decode(_:forKey:)`, not `decodeIfPresent`, so a struct whose
> properties all have defaults still throws `keyNotFound` when one of them is missing
> from the file.

Combined with `LibraryFile.load`, which treats *any* decode failure as corruption, that
turns "a future version adds one field" into silent, total loss of the user's categories.
Three types were exposed to this — `LauncherSettings`, `AppCategory`, `HotKeySpec` — and
all three now decode field by field. Two further details:

- **`CodingKeys` are written out explicitly**, so renaming a Swift property cannot
  silently change the on-disk format. `testEncodedKeysAreStable` pins it.
- **Enums and dates use `try?`**, not just `decodeIfPresent`: an unknown enum case or an
  unparseable timestamp throws rather than returning `nil`, and neither is worth losing a
  library over. `AppIconSize`, `AppSortMode` and `AppCategory.createdAt` are guarded this
  way.

The cost is that a damaged record degrades instead of failing loudly — a category missing
its `name` loads blank rather than stopping the app. For a file that holds the user's only
copy of their setup, degrading is the better failure.

`LibraryFormatTests` covers each of these paths, including the end-to-end case that the
file is read rather than quarantined.

### On-disk format

`~/Library/Application Support/AppPocket/library.json`, written atomically.

Dates use a custom ISO 8601 strategy with fractional seconds, defined once in
`LibraryCoding` and used by both the encoder and the decoder. This is load-bearing: an
earlier revision encoded with `.iso8601` and decoded with a default `JSONDecoder`, so
every save produced a file that could not be read back. On the next launch the app would
have renamed the user's library to `.corrupt` and started empty. Two regression tests now
pin the round trip (`testSavingAndLoadingAgreeOnDates`,
`testDecodingAcceptsTimestampsWithoutFractionalSeconds`).

### Migration from the old build

`LegacyMigrator` reads the old `"CustomCategories"` key from `UserDefaults`, and also
looks inside the app's former sandbox container
(`~/Library/Containers/com.liupeixin.AppPocket.AppPocket/Data/Library/Preferences/…`) for
users who ran a sandboxed build. It converts path-keyed membership into bundle-identifier
membership, which requires the scan to have run first — so it is invoked after the first
`refreshAndWait()`, not at launch. It only runs when the new document has no categories,
and it clears the legacy key once it succeeds.

---

## Modules

### Models (`AppPocket/Models/`)

| Type | Responsibility |
|---|---|
| `AppInfo` | One discovered bundle. `id` is the bundle identifier, or the path when there is none. |
| `AppLocation` | `.user` / `.local` / `.system` / `.other`, with a priority used to de-duplicate. |
| `AppCategory` | A user category, plus `palette` (10 colours) and `symbolChoices` (64 SF Symbols). |
| `SmartGroup` | The four computed groups. `isAlwaysVisible` keeps **Hidden** out of the sidebar until it has members. |
| `SidebarSelection` | `.smart(SmartGroup)` or `.category(UUID)`. |
| `LauncherSettings` | Column count, icon size, sort mode, close-after-launch, launch-at-login, menu bar, hot key. |
| `HotKeySpec` | Key code + Carbon modifier mask, with a `displayString` (`⌥⌘Space`). |
| `LibraryDocument` | The persisted root. |
| `AppDragPayload`, `CategoryDragPayload` | `Transferable` payloads with custom exported UTTypes, so a drag of plain text or a file from Finder is distinguishable. |

### Services (`AppPocket/Services/`)

| Type | Responsibility |
|---|---|
| `AppScanner` | `nonisolated`. Walks the roots, reads `Info.plist`, filters, de-duplicates. |
| `AppCatalog` | Owns the live app list, the scan lifecycle, and the set of running bundle ids. |
| `DirectoryWatcher` | One `DispatchSource` per root, 900 ms debounce, 90 s polling fallback. |
| `IconCache` | `NSCache` (512 entries) with in-flight de-duplication; renders off-main. |
| `LibraryStore` | Every mutation, every undo snapshot, every write. The only writer. |
| `LibraryFile` / `LibraryCoding` | Where the file lives; the one encoder/decoder pair. |
| `AppQuery` | `nonisolated`. Relevance scoring and the three sort modes. |
| `LibrarySnapshot` | `nonisolated`. What each sidebar row shows. |
| `AppLauncher` | Open, reveal, copy path, quit. |
| `LaunchAtLogin` | `SMAppService.mainApp`. |
| `GlobalHotKeyCenter` | Carbon hot key registration. |
| `WindowBridge` | Gives the hot key and menu bar a way to reach the window. |
| `LegacyMigrator` | One-shot import from the previous build. |
| `AppUIState` | Selection, search text, multi-select set, pending sheet request. |

### UI (`AppPocket/UI/`)

```
LauncherRootView                 NavigationSplitView, bootstrap, hot key wiring
├── CategorySidebarView          smart groups + categories, drop targets, footer
└── CategoryDetailView           header, sort/size menus, search, grid, action bar
    ├── AppTileView / AppIconView
    └── AppPickerSheet
CategoryEditorSheet              name + symbol + colour + membership, live validation
SettingsView                     General / Appearance / Data / About
Theme                            Color(hex:), Metrics, categoryBadge, tileSurface
SearchField, EmptyStateView
```

`Metrics.sidebarWidth` is `(min: 196, ideal: 224, max: 300)`. The grid clamps to 14
columns, or to `settings.columnCount` when the user has fixed it (clamped to 3…12).

---

## Behaviour worth stating explicitly

### Launching

A click launches the app. ⌘-click toggles selection instead; ⌥-click launches and keeps
the window open. When `closeAfterLaunch` is on, the window is ordered *out* rather than
closed — it comes back instantly with its scroll position intact — after a 180 ms delay
so the launched app can come forward first.

### Deletion

Deleting a category removes the category, never the apps. Nothing in the app can delete a
file; the most destructive operation available is `prune(keeping:)`, which drops
identifiers for apps that are no longer installed, and it **refuses to run on an empty
set**. A scan that finds nothing means the scan failed, not that the user uninstalled
every application, and wiping their categories in that situation would be unrecoverable.

### Hiding

Hidden apps disappear from **All**, **Uncategorized** and every user category, but
**Uncategorized** still counts them as categorized — otherwise an app that is in a
category and hidden would show up as uncategorized, which is confusing and wrong.

### Search

Searching filters the current selection's apps and re-orders by score rather than by the
user's chosen sort, because while searching, relevance is what the user wants. Tiers, high
to low: exact name, name prefix, word-boundary prefix, name substring, bundle-id suffix,
bundle-id substring, path, subsequence (≥ 0.6 density). Each tier subtracts a small amount
for length so that shorter matches win within a tier.

---

## Security and distribution

**The App Sandbox is off** (`ENABLE_APP_SANDBOX = NO`). Hardened Runtime stays on. There
are no entitlements that grant network or file access beyond what a normal app has.

This is the one decision in the project that a reader might reasonably want to reverse, so
here is the evidence. With `ENABLE_APP_SANDBOX = YES`:

- `FileManager.default.homeDirectoryForCurrentUser` resolves to
  `~/Library/Containers/com.liupeixin.AppPocket.AppPocket/Data`, so `~/Applications`
  cannot be listed.
- Even with a user-selected-file bookmark, the four scan roots cannot be read at launch
  without prompting.

In other words, the sandboxed build cannot do the single thing the app exists to do. The
cost of turning it off is that the app is not eligible for the Mac App Store as written;
distributing it there would require a different discovery mechanism (a signed helper
inside a sandboxed container, or an app-scoped bookmark the user grants once at first
launch). That trade is not made yet.

---

## Testing and verification

### Unit tests — 86 tests

`AppPocketTests/` covers category CRUD and name-collision validation, membership and
ordering, hidden/recent semantics, document round-tripping, the scan filters, the query
scorer, the snapshot builder, and — added last — the on-disk format's tolerance for
change. The fixtures build a synthetic filesystem of `.app` bundles in a temp directory,
so the scanner tests do not depend on what is installed on the machine running them.

Three of the tests exist because of a specific bug: the two date-strategy tests described
under [On-disk format](#on-disk-format), and the whole of `LibraryFormatTests` described
under [Lenient decoding](#lenient-decoding).

**How these have actually been run.** The suite was last executed in full before the
format work landed, at which point it was 77 tests, all passing. The 9 tests added
afterwards have **not** been run under XCTest — see [Not verified](#not-verified) — so
their assertions were instead re-run outside XCTest, compiled against the same sources.
That harness reports **28 assertions, 0 failures**, and it is what validates the fix. The
distinction matters: the assertions are verified, the XCTest plumbing around them is not.

### Offscreen UI verification

`swiftui ImageRenderer` is not usable here — it renders `NavigationSplitView` as a
forbidden placeholder and any `ScrollView` as blank. `screencapture` needs Screen
Recording permission and fails without a display.

The working path is in-process: build a real `NSWindow`, host the real view in an
`NSHostingView`, force layout, pump the run loop, and snapshot with
`NSView.cacheDisplay(in:to:)`. The window is never ordered front, so nothing appears on
screen and no focus is taken.

The resulting snapshots are checked programmatically rather than by eye, because
thumbnails lie. Measured from the 1040 pt snapshot:

```
sidebar / detail boundary : 224.0 pt   (Metrics.sidebarWidth.ideal = 224)
grid columns              : 7, pitch 109.0 pt (even within 1.3 pt)
at 820 pt window          : 5 columns
at 760 pt window (min)    : 5 columns, nothing clipped
selected tile plate       : (222,233,253) vs (216,235,255) expected
                            = accent.opacity(0.16) over the window background
sidebar category badges   : 6 plates, each matching its palette entry
                            (#0A84FF, #30D158, #FF9F0A, #FF375F, #BF5AF2, #FFD60A)
```

The badge check needs the right model to be meaningful. A badge is
`Color(hex:).gradient`, so a plate pixel is `s · (white·(1−t) + P·t)`; the checker
grid-searches `t` and `s` and keeps the palette entry with the smallest residual. Plain
RGB distance misreads every plate (the gradient lightens them), and hue distance cannot
separate `#FF375F` from `#FF6482` — they are 0.001 apart in hue and differ only in
saturation.

### Not verified

- **The XCTest runner cannot connect in this environment.** `xcodebuild test` ends with
  `The test runner hung before establishing connection`, after the full ~340 s timeout,
  and `xcodebuild test-without-building` reproduces it — so it is not a build problem and
  not flakiness. The build succeeds, the bundle is produced, and the app itself launches
  and stays alive; what fails is `testmanagerd` attaching to the runner. The sandbox logs
  `sandbox_extension_issue_file_to_process failed … Operation not permitted` on every
  `xcodebuild` invocation, which is the likely cause.
- **XCUITest fails for the same underlying reason** and additionally cannot attach to the
  window server: `Early unexpected exit, operation never finished bootstrapping … signal
  kill before establishing connection`. The two UI smoke tests are unverified.
- **Selection emphasis is rendered in the inactive-window style** in the snapshots,
  because the probe deliberately never activates the app. The sidebar's selected row and
  the Settings tab bar therefore appear grey rather than accent-coloured. The app's own
  colour coding — tile selection, category badges, running indicator — does not depend on
  window activation and is verified above.
- **The 9 tests in `LibraryFormatTests` have never been executed by XCTest.** Their
  assertions were verified by a standalone harness compiled against the same sources
  (28 assertions, 0 failures), so the behaviour they assert is confirmed; what remains
  unconfirmed is that XCTest discovers and runs them. CI on a normal runner is the first
  place this will actually be exercised.

Everything else listed above was measured, not assumed.

---

## Known limitations

1. **`columnCount` does not account for the legacy scroll bar.** At the 760 pt minimum
   window width the layout computes 5 columns from the full detail width, but the grid
   gets ~16 pt less because the system is configured to always show scroll bars. Tiles
   (94 pt) end up ~3 pt wider than their column. Nothing clips or overlaps, but the
   spacing is tighter than the formula implies. An overlay-scroller configuration does not
   have this problem.
2. **`~/Applications` requires no special permission only because the sandbox is off.**
   See above.
3. **Icons are rendered from disk on demand.** First paint of a 150-app grid shows
   monogram placeholders for the tiles whose icons have not resolved yet. `NSCache` makes
   this a first-launch-only cost.
4. **The global hot key is a single global.** Registering fails silently if another app
   owns the combination; the app detects the failure and switches its own setting back off
   rather than leaving a control that does nothing.
5. **`schemaVersion` is written and read but never acted on.** Nothing compares it to
   `LibraryDocument.currentSchemaVersion`, so a file claiming `"schemaVersion": 99` is
   decoded as if it were version 1 — there is no upgrade path and no protection against a
   file from a newer build. `testAHigherSchemaVersionIsCurrentlyAcceptedUnchecked`
   records the behaviour as it stands; it is a characterisation test, not an endorsement.
   The lenient decoder above is what actually keeps old files readable.
6. **Only one generation of the corrupt-file rescue copy is kept.** `LibraryFile.load`
   deletes any existing `library.json.corrupt` before moving the unreadable file into
   place, so a second corruption destroys the first rescue copy.
7. **A failed save is reported only in the log.** `LibraryStore.save` catches, logs, and
   returns; the in-memory document has already been published by then, so a full disk or a
   read-only directory leaves the UI showing success while the file on disk is stale. The
   two then stay out of sync until the next launch.

---

## Open questions

These are unresolved and should be answered before the next round of work:

1. Mac App Store distribution, or direct download? The answer determines whether the
   sandbox decision above has to be revisited.
2. Should categories be able to nest? The data model allows it; the UI does not.
3. Should the manual sort mode be reachable by dragging tiles *inside* a category? The
   store supports it (`moveApp(id:toIndex:inCategory:)`) and the sidebar drop targets
   exist, but no gesture is wired to it in the grid.
4. Is the `Recent` smart group worth keeping? It is currently populated only by launches
   made *through AppPocket*, so it stays empty for anyone who mostly uses Spotlight.

---

*This document describes the code that exists. When it and the code disagree, the code is
right — but fix the document in the same change, and record what changed under Errata.*
