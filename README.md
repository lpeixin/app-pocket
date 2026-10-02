# AppPocket

A local-only application launcher for macOS 26, where Launchpad is no longer with us.

No account, no network, no analytics, no third-party dependencies. It reads `Info.plist`
files and writes one JSON file.

<!-- LANGUAGE-SWITCH -->
**[English](#english) · [中文](#中文)**

---

# English

## What it does

- **Every installed app**, from `/Applications`, `/System/Applications`,
  `/System/Library/CoreServices/Applications` and `~/Applications`, with real icons.
- **Four smart groups**, computed rather than stored: All, Uncategorized, Recent, Hidden.
- **Your own categories** — name, SF Symbol, colour, and an ordered member list.
  Create, edit, rename, duplicate, reorder, delete.
- **Assign apps** by dragging a tile onto a category in the sidebar, from a tile's context
  menu, or in bulk from the multi-select action bar.
- **Search** with relevance ranking, not a substring filter.
- **Reachable without the Dock** — a menu bar extra and an optional global hot key.
- **Six languages**: English, 简体中文, 日本語, Deutsch, Français, Español.

## Using it

| Action | How |
|---|---|
| Launch an app | Click its tile |
| Launch and keep the launcher open | ⌥-click |
| Select several apps | ⌘-click each, or ⌘A for all |
| Move the keyboard focus | Arrow keys, then ⏎ to launch, esc to clear |
| New category | ⌘N, or the **+** at the bottom of the sidebar |
| Edit the selected category | ⌘E |
| Search | ⌘F |
| Rescan for new apps | ⌘R |
| Jump to a smart group | ⌘1 – ⌘4 |
| Jump to a category | ⌘5 – ⌘9 |
| Undo | ⌘Z (30 levels) |
| Put the launcher away | ⌘W — the app keeps running in the menu bar |

Right-click a category in the sidebar to rename, duplicate or delete it. Drag one category
onto another to reorder. Drag tiles onto **Uncategorized** to take them out of every
category.

## Building

```
git clone <this repo>
cd app-pocket/AppPocket
open AppPocket.xcodeproj      # ⌘R
```

or from the command line:

```
xcodebuild -project AppPocket.xcodeproj -scheme AppPocket \
           -configuration Debug -derivedDataPath /tmp/AppPocketDD \
           CODE_SIGNING_ALLOWED=NO build
```

Requires macOS 14.0+ and Xcode 26. There are no packages to resolve.

### Tests

```
xcodebuild -project AppPocket.xcodeproj -scheme AppPocket \
           -configuration Debug -derivedDataPath /tmp/AppPocketDD \
           CODE_SIGNING_ALLOWED=NO -only-testing:AppPocketTests test
```

86 unit tests covering category CRUD, name collisions, membership, hidden/recent
semantics, document round-tripping, the on-disk format's tolerance for change, the scan
filters, the query scorer and the sidebar counts. They build a synthetic filesystem of
`.app` bundles in a temp directory, so they do not depend on what is installed on the
machine running them.

Both test targets need `testmanagerd` to attach to a test runner, and that does not work
in every environment — inside a restrictive sandbox `xcodebuild test` can end with
`The test runner hung before establishing connection`, and `AppPocketUITests` additionally
needs the window server. When that happens, build and launch the app to confirm it is
alive, and treat the test result as unavailable rather than as a failure.

## Project layout

```
AppPocket/
├── AppPocket/
│   ├── AppPocketApp.swift        scenes, menu bar, menu commands, AppDelegate
│   ├── Models/                   AppInfo, AppCategory, SmartGroup,
│   │                             LauncherSettings, LibraryDocument, DragPayloads
│   ├── Services/                 AppScanner, AppCatalog, DirectoryWatcher, IconCache,
│   │                             LibraryStore, LibraryFile, AppQuery, LibrarySnapshot,
│   │                             AppLauncher, LaunchAtLogin, GlobalHotKeyCenter,
│   │                             WindowBridge, LegacyMigrator, AppUIState
│   ├── UI/                       LauncherRootView, CategorySidebarView,
│   │                             CategoryDetailView, CategoryEditorSheet,
│   │                             AppPickerSheet, SettingsView, Theme, SearchField,
│   │                             EmptyStateView, AppTileView
│   └── *.lproj/                  Localizable.strings × 6
├── AppPocketTests/               86 unit tests
└── AppPocketUITests/             2 launch smoke tests
```

`DESIGN_DOCUMENT.md` has the full architecture, the persistence format, and an
[errata section](../DESIGN_DOCUMENT.md#errata) recording what the previous design
document got wrong.

## How it stores your data

One file: `~/Library/Application Support/AppPocket/library.json`, written atomically.

Categories are keyed by **bundle identifier**, not by path, so moving an app between
folders does not silently drop it from your categories. If a bundle declares no
identifier, its path is used instead.

Nothing in the app can delete a file. The most destructive operation available is dropping
identifiers for apps you have uninstalled — and that refuses to run when a scan comes back
empty, because an empty scan means the scan failed, not that you uninstalled everything.

A `library.json` that fails to parse is renamed to `library.json.corrupt` rather than
overwritten, so your categories are still on disk to be repaired by hand. Settings → Data
has Export and Import if you want a copy.

## A note on the App Sandbox

It is off. With it on, `~/Applications` is unreadable and `homeDirectoryForCurrentUser`
resolves inside the app's container — which is to say, the sandboxed build cannot do the
one thing the app exists to do. Hardened Runtime stays on.

The cost is Mac App Store eligibility as written. `DESIGN_DOCUMENT.md` has the evidence
and what the alternatives would require.

## Licence

MIT.

---

# 中文

## 功能

- **列出全部已安装应用**，覆盖 `/Applications`、`/System/Applications`、
  `/System/Library/CoreServices/Applications` 与 `~/Applications`，显示真实图标。
- **四个智能分组**，实时计算而非存储：全部应用、未分类、最近使用、已隐藏。
- **自定义分类** —— 名称、SF Symbol 图标、颜色，以及可排序的成员列表。
  支持新建、编辑、重命名、复制、拖拽排序、删除。
- **把应用归入分类** —— 把图标拖到侧栏的分类上、用图标的右键菜单，或在多选操作栏里批量处理。
- **搜索**按相关度排序，不是简单的子串过滤。
- **不必回到 Dock** —— 菜单栏图标，以及可选的全局快捷键。
- **六种语言**：English、简体中文、日本語、Deutsch、Français、Español。

## 怎么用

| 操作 | 方式 |
|---|---|
| 启动应用 | 单击图标 |
| 启动并保持启动器打开 | ⌥ 单击 |
| 多选 | ⌘ 单击逐个选择，⌘A 全选 |
| 键盘操作 | 方向键移动焦点，⏎ 启动，esc 清除 |
| 新建分类 | ⌘N，或侧栏底部的 **+** |
| 编辑当前分类 | ⌘E |
| 搜索 | ⌘F |
| 重新扫描新装应用 | ⌘R |
| 跳到智能分组 | ⌘1 – ⌘4 |
| 跳到某个分类 | ⌘5 – ⌘9 |
| 撤销 | ⌘Z（30 步） |
| 收起启动器 | ⌘W —— 应用仍在菜单栏运行 |

在侧栏右键分类可以重命名、复制、删除；把一个分类拖到另一个分类上可以调整顺序。
把图标拖到**未分类**上，即可让它退出所有分类。

## 构建

```
git clone <本仓库>
cd app-pocket/AppPocket
open AppPocket.xcodeproj      # ⌘R
```

命令行：

```
xcodebuild -project AppPocket.xcodeproj -scheme AppPocket \
           -configuration Debug -derivedDataPath /tmp/AppPocketDD \
           CODE_SIGNING_ALLOWED=NO build
```

需要 macOS 14.0+ 与 Xcode 26。没有需要解析的依赖包。

### 测试

```
xcodebuild -project AppPocket.xcodeproj -scheme AppPocket \
           -configuration Debug -derivedDataPath /tmp/AppPocketDD \
           CODE_SIGNING_ALLOWED=NO -only-testing:AppPocketTests test
```

86 个单元测试，覆盖分类增删改查、重名校验、归属关系、隐藏与最近使用的语义、
文档读写往返、磁盘格式的向前兼容、扫描过滤规则、搜索打分与侧栏计数。测试会在
临时目录里搭出一套 `.app` 包组成的合成文件系统，因此不依赖运行机器上装了什么。

两个测试目标都需要 `testmanagerd` 挂上测试运行器，而这并非所有环境都能做到 ——
在受限沙箱里 `xcodebuild test` 可能以 `The test runner hung before establishing
connection` 结束，`AppPocketUITests` 还额外需要连上窗口服务。遇到这种情况，
构建并启动应用确认它活着即可，把测试结果当作**不可用**，而不是失败。

## 项目结构

```
AppPocket/
├── AppPocket/
│   ├── AppPocketApp.swift        场景、菜单栏、菜单命令、AppDelegate
│   ├── Models/                   AppInfo、AppCategory、SmartGroup、
│   │                             LauncherSettings、LibraryDocument、DragPayloads
│   ├── Services/                 AppScanner、AppCatalog、DirectoryWatcher、IconCache、
│   │                             LibraryStore、LibraryFile、AppQuery、LibrarySnapshot、
│   │                             AppLauncher、LaunchAtLogin、GlobalHotKeyCenter、
│   │                             WindowBridge、LegacyMigrator、AppUIState
│   ├── UI/                       LauncherRootView、CategorySidebarView、
│   │                             CategoryDetailView、CategoryEditorSheet、
│   │                             AppPickerSheet、SettingsView、Theme、SearchField、
│   │                             EmptyStateView、AppTileView
│   └── *.lproj/                  Localizable.strings × 6
├── AppPocketTests/               86 个单元测试
└── AppPocketUITests/             2 个启动冒烟测试
```

完整的架构说明、持久化格式，以及记录上一版设计文档错在哪里的
[勘误章节](../DESIGN_DOCUMENT.md#errata)，都在 `DESIGN_DOCUMENT.md` 里。

## 数据存在哪

只有一个文件：`~/Library/Application Support/AppPocket/library.json`，原子写入。

分类以**应用包标识（bundle identifier）**为键，不是路径，所以把应用在文件夹之间
挪动不会让它悄悄从分类里消失。若某个应用包没有声明标识，则退回使用路径。

应用里没有任何操作能删除文件。破坏性最强的一步是清理已卸载应用的标识 ——
而这一步在扫描结果为空时会**拒绝执行**，因为扫不到东西意味着扫描失败了，
不是你把应用全卸载了。

解析失败的 `library.json` 会被重命名为 `library.json.corrupt`，而不是被覆盖，
你的分类仍然留在磁盘上可以手工抢救。想留个备份的话，设置 → 数据里有导出与导入。

## 关于 App Sandbox

它是关闭的。开启沙箱后 `~/Applications` 无法读取，`homeDirectoryForCurrentUser`
也会落在应用容器内 —— 也就是说，沙箱版本做不了这个应用存在的唯一理由。
Hardened Runtime 仍然开启。

代价是按现状无法上架 Mac App Store。`DESIGN_DOCUMENT.md` 里记录了证据，
以及替代方案需要付出什么。

## 许可证

MIT。
