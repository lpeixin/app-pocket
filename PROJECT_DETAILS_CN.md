# AppPocket 代码走读（中文）

> **2026-09-24 重写。** 本文的上一版是 372 行对 `CoreDataStack.shared`、
> `PersistenceController.shared`、`TestLauncherView`、`saveCustomCategories()`
> 的逐段分析 —— 而这些代码在重构中全部被删除，其中一部分从未被任何视图引用过。
> 一份描述不存在代码的分析比没有分析更糟，所以整篇重写。
> 架构决策与取舍见 `DESIGN_DOCUMENT.md`，这里只讲代码。

## 一、整体数据流

```
磁盘                     内存                        界面
────                     ────                        ────
/Applications/*.app  ──▶ AppScanner.scan()           （nonisolated，后台线程）
                         │  ScanOutcome
                         ▼
                       AppCatalog.apps               侧栏计数 / 网格内容
                         │  [AppInfo]
                         │
library.json         ──▶ LibraryStore.document      侧栏分类 / 归属 / 设置
                         │  LibraryDocument
                         ▼
                    AppQuery + LibrarySnapshot       （纯函数，可单测）
                         │  [AppInfo]
                         ▼
                    CategoryDetailView.grid
```

关键分界：**上半截是「机器上有什么」，下半截是「用户怎么组织」。** 两者互不写入，
只在 `AppQuery` / `LibrarySnapshot` 里合并。这条边界让「分类里的应用被卸载了怎么办」
这类问题变得平凡 —— 查询时查不到就跳过，不需要在卸载时回调清理任何东西。

## 二、`LibraryStore`：唯一写入者

所有对 `LibraryDocument` 的修改都必须经过 `mutate`：

```swift
private func mutate(recordingUndo: Bool = true, _ body: (inout LibraryDocument) -> Void) {
    let previous = document
    var updated = previous
    body(&updated)
    guard updated != previous else { return }   // ← 这一行是必须的

    if recordingUndo { pushUndoSnapshot(previous) }
    document = updated
    save()
}
```

`guard updated != previous` 看着像微优化，其实是修 bug 的补丁。`@Published` 只要赋值
就会发布，不管新旧值是否相等。于是：

1. 视图更新过程中，SwiftUI 把一个 Binding 写回 store；
2. `document` 被赋值 → `@Published` 发布 → 视图失效；
3. 视图再次更新，再次写回 → 回到第 1 步。

加上守卫之前，一次运行会产生 **2,532,912** 条
`Publishing changes from within view updates is not allowed` 警告，
测试宿主卡死 344 秒。把这个判断放进唯一入口，而不是散落在几十个 `func addXxx` 里，
是 `mutate` 存在的首要理由。

另外两处刻意为之：

- `noteLaunched` 用 `recordingUndo: false`。启动历史不是用户编辑，不该占用撤销栈 ——
  否则用户连点几个应用之后按 ⌘Z，撤销掉的是「记录了一次启动」，
  而分类的修改被推到栈底。
- `prune(keeping:)` 在 `liveIDs` 为空时**直接返回**。扫不到任何应用意味着扫描失败，
  不是用户把应用全卸载了；此时清空用户的分类是不可恢复的。

## 三、并发：默认 MainActor 之后，边界在哪

工程设置 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，所以「不写修饰符」
等于「主线程」。要挪到后台必须显式声明：

```swift
nonisolated enum AppScanner { … }                     // 整个类型
nonisolated func sortedByName() -> [AppInfo] { … }    // 单个方法
nonisolated extension UTType { … }                    // 整个扩展
```

`nonisolated` 的清单就是这份代码的「纯逻辑边界」：`AppScanner`、`AppQuery`、
`LibrarySnapshot`、`LibraryCoding`、`AppInfo`、`AppCategory`、`LibraryDocument`、
`SmartGroup`、`LauncherSettings`、`HotKeySpec`、`AppLocation`、`LibraryError`。
它们不碰 UI、不碰 `self` 的可变状态，因此天然可并发。

`AppCatalog` 里真正把扫描挪走的是这一句：

```swift
let outcome = await Task.detached(priority: .userInitiated) {
    AppScanner.scan(roots: roots)
}.value
```

`NSImage` 不是 `Sendable`，所以图标跨线程用 `IconBox` 包一层：

```swift
nonisolated struct IconBox: @unchecked Sendable { let image: NSImage }
```

`@unchecked` 在这里是安全的，因为 `IconBox` 一旦构造就不再修改，`NSImage`
只被读取。这是必须写清楚理由的 `@unchecked`，不是随手加的。

### 两个容易写错的模式

**弱引用跨并发**。`[weak self]` 捕获的是一个会被置空的 `var`，在 Swift 6 语言模式下
从并发代码里读它是错误：

```swift
// ✗ 警告（Swift 6 下是错误）
center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
    Task { @MainActor in self?.refresh() }
}

// ✓ 先落成强引用常量，再跳
center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
    guard let self else { return }
    Task { @MainActor in self.refresh() }
}
```

**在视图更新里改状态**。`onChange` 的回调本身就在视图更新过程中执行，
在里面改 store 就是上面那个死循环。`LauncherRootView` 里三处 `onChange`
（prune、两个快捷键设置）都包了一层 `Task { @MainActor in … }` 让改动落到下一拍。

## 四、扫描：过滤与去重

四个根目录，深度上限 2：

```
/Applications
/System/Applications
/System/Library/CoreServices/Applications
~/Applications
```

深度 2 覆盖 `/Applications/<厂商>/<App>.app` 这种常见布局，又不至于变成全盘遍历。
遍历时用 `[.skipsHiddenFiles, .skipsPackageDescendants]` —— 后者很重要，
否则会走进每个 `.app` 内部，把 `Contents/Helpers/*.app` 也当应用。

判定一个 bundle 是否算「应用」：

| 条件 | 处理 |
|---|---|
| 读不到 `Contents/Info.plist` | 跳过 |
| `LSUIElement` 或 `LSBackgroundOnly` 为真 | 跳过（后台代理、菜单栏工具不是启动器意义上的应用） |
| 没有 `CFBundleExecutable` | 跳过（没有可启动的东西） |
| `CFBundleDisplayName` / `CFBundleName` 都为空 | 退回目录名 |

`Info.plist` 里的布尔值有时写成 `1` 或 `"YES"`，所以有个 `boolValue(_:)` 同时接受
`Bool` / `NSNumber` / `String`。

去重按身份（bundle id，没有则路径）：先比 `AppLocation.priority`
（`/Applications` 3 > `~/Applications` 2 > `/System` 1 > 其他 0），
同优先级比路径深度，再同则比字典序。这样同一个应用同时装在 `/Applications`
和 `~/Applications` 时，留下的是用户更可能实际启动的那一份。

## 五、查询层：两个纯函数

**`AppQuery.score`** —— 搜索打分，高到低：

| 档位 | 分值 |
|---|---|
| 名称完全相同 | 1000 |
| 名称前缀 | `900 - min(99, 长度差)` |
| 词首匹配（`" code"`） | 800 |
| 名称包含 | `700 - min(99, 长度差)` |
| bundle id 完全相同 | 650 |
| bundle id 后缀（`.code`） | 600 |
| bundle id 包含 | 500 |
| 路径包含 | 300 |
| 子序列密度 ≥ 0.6 | `100 + Int(密度 × 100)` |
| 其他 | 0 |

前缀档减去长度差，是为了让 `Code` 排在 `CodeBuddy CN` 前面。
子序列那一档处理「打错几个字母但顺序还对」的情况，并设了 0.6 的下限 ——
不设的话 `abc` 会匹配上大半张表。

**`LibrarySnapshot.apps(for:)`** —— 侧栏每一行点开之后网格里有什么。
它和 `CategorySidebarView` 里算计数的 `LibrarySnapshot.count(for:)` 是**两条独立代码路径**，
`LibrarySnapshotTests` 专门断言两者结果一致（`testCountMatchesWhatTheGridWouldShow`）。
这类断言才有意义：如果它们共用同一个函数，测了等于没测。

## 六、`LauncherRootView` 的启动流程

```swift
private func bootstrap() async {
    guard !hasBootstrapped else { return }
    hasBootstrapped = true

    catalog.start()                         // 装上文件监听 + 运行中应用监听
    await catalog.refreshAndWait()          // 等首次扫描出结果

    LegacyMigrator.migrateIfNeeded(into: store, apps: catalog.apps)
    store.prune(keeping: Set(catalog.apps.map(\.id)))
    configureGlobalHotKey()
}
```

顺序有约束，不能调换：旧版按路径记录归属，新版按 bundle id，
所以迁移必须等扫描结果出来才能做映射。`prune` 也必须在扫描之后 ——
在它之前跑，`liveIDs` 是空的，会被自身的守卫直接挡掉（挡掉是对的，但迁移就白做了）。

## 七、图标

`IconCache` 做两件事：`NSCache`（上限 512）缓存已渲染的图标，
以及用一个 `[NSString: Task<IconBox, Never>]` 表合并同一张图的并发请求。
没有第二件事的话，一次滚动会让同一张图被渲染十几遍 —— `LazyVGrid` 在快速滚动时
会反复创建销毁 tile，每个新 tile 的 `.task` 都会去要图标。

```swift
.task(id: "\(app.id)|\(Int(side))") {
    guard IconCache.shared.cached(for: app.id, size: side) == nil else { return }
    loaded = await IconCache.shared.image(for: app, size: side)
}
```

`.task(id:)` 的 id 带上尺寸，因为同一应用在不同位置（网格 64pt、拖拽预览 32pt、
编辑器列表 26pt）需要不同分辨率的渲染结果。

## 八、几个真实踩过的坑

1. **日期编解码策略不一致会让用户数据全丢。** 保存用 `.iso8601`、读取用默认
   `JSONDecoder`（数字时间戳），于是写出去的文件永远读不回来。下一次启动时，
   `library.json` 会被重命名成 `.corrupt`，用户看到的是一个空库。
   修法是把编解码器收进 `LibraryCoding` 一处，并加两个回归测试钉住往返。

2. **`@Published` 的等值发布。** 见第二节。

3. **`WindowAccessor` 每次布局都重新配置窗口。** `updateNSView` 里调
   `window.setFrameAutosaveName(…)` 会改变窗口尺寸 → 触发新的布局 → 再次进入
   `updateNSView`。加上 `guard self.window !== window` 和
   「只在 `WindowBridge.shared.window == nil` 时接管」两个条件才断掉这个环。

4. **`move(fromOffsets:toOffset:)` 属于 SwiftUI。** 数据层引用它会引入
   `[#MemberImportVisibility]` 报错。手写了一份 `moveElements(fromOffsets:toOffset:)`，
   顺带用 `Swift.max` / `Swift.min` 避开与实例方法的同名遮蔽。

## 九、怎么验证

- **单元测试** 86 个，覆盖分类增删改查、重名校验、归属、隐藏/最近语义、
  文档往返、**磁盘格式的向前兼容**、扫描过滤、搜索打分、侧栏计数。扫描相关的
  测试在临时目录里搭合成 `.app` 包，不依赖运行机器上装了什么。
  - 其中 `LibraryFormatTests` 是为一类具体缺陷写的：合成 `Codable` 忽略属性默认值，
    导致"下一版加一个字段"会让旧 `library.json` 解码失败、被 `LibraryFile.load`
    判为损坏并静默清空。细节见 `DESIGN_DOCUMENT.md` 的 Lenient decoding 一节。
  - ⚠️ **86 个里只有前 77 个在 XCTest 下跑过。** 后 9 个的断言是在 XCTest 之外、
    链接同一批源文件跑通的（28 条断言 0 失败），验证了行为，但没验证 XCTest 能
    发现并执行它们。受限沙箱里 `xcodebuild test` 会以
    `The test runner hung before establishing connection` 结束——那是运行器连不上
    `testmanagerd`，不是测试失败。首次真正在 CI 上跑才算数。
- **本地化一致性**：6 份表各 151 键、键集完全一致，且与代码中用到的键一一对应
  （used-but-missing = 0，defined-but-unused = 0）。检查脚本见
  `LOCALIZATION_README.md`。
- **界面**：`screencapture` 与 `ImageRenderer` 在无显示环境下都不可用
  （前者需要录屏权限，后者会把 `NavigationSplitView` 画成黄色占位符、
  把 `ScrollView` 画成空白）。可行路径是在进程内建真实 `NSWindow` + `NSHostingView`，
  强制布局后用 `cacheDisplay(in:to:)` 取图，全程不 `orderFront`。
  取到的图用像素扫描核对，而不是靠眼睛看缩略图：
  侧栏边界 224pt、1040pt 窗口 7 列（列距 109.0pt）、
  选中态色块 `(222,233,253)` 对 `accent.opacity(0.16)` 复合结果 `(216,235,255)`。
