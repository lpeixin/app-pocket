# AppPocket 国际化（i18n）

界面语言跟随系统语言设置，无需在应用内切换。

## 支持的语言

| 语言 | 目录 | 说明 |
|---|---|---|
| English | `Localizable.strings`（包根） | 开发语言，也是兜底 |
| 简体中文 | `zh-Hans.lproj/` | |
| 日本語 | `ja.lproj/` | |
| Deutsch | `de.lproj/` | |
| Français | `fr.lproj/` | |
| Español | `es.lproj/` | |

**注意：没有 `en.lproj`。** 英文表直接放在 bundle 根目录，是
`CFBundleDevelopmentRegion` 的兜底资源。系统语言不在上表里时，界面就是英文。

## 键的规模与一致性

六份表各有 **151** 个键，键集完全相同。这个约束是刻意维持的：
任何一份表缺一个键，用户在该语言下就会看到 `detail.addApps` 这种原始键名。

当前状态（脚本核对，非人工目测）：

```
tables                        : 6
keys per table                : [151]
key sets identical            : True
localization keys used in code: 151
used but not defined          : 0
defined but never used        : 0
```

命名前缀：`smart` `sidebar` `detail` `editor` `picker` `selection` `action`
`menu` `menubar` `settings` `empty` `search` `category` `location` `sort`
`iconSize` `error`。

## 代码里怎么用

字符串键直接传给本地化感知的 API：

```swift
Text("sidebar.smartGroups")
Button("menu.newCategory") { … }
Label("detail.addApps", systemImage: "plus")
.help("sidebar.newCategoryHelp")
```

需要插值的场合走 `NSLocalizedString`，因为 `LocalizedStringKey` 不便于拼接：

```swift
String(format: NSLocalizedString("detail.appCount", comment: ""), count)
```

**分类名、应用名不翻译。** 分类名来自用户输入，应用名来自 bundle 的
`CFBundleDisplayName` / `CFBundleName`，两者都按原文显示。

## 加新键

1. 在代码里写上新键。
2. 六份表都要加，一份都不能漏 —— 包括根目录那份英文表。
3. 跑一遍上面的一致性检查（见下）。

## 怎么验证

### 一致性检查

六份表的键集必须一致，且与代码里用到的键一一对应：

```bash
cd AppPocket
python3 - <<'PY'
import pathlib, re
root = pathlib.Path("AppPocket")
tables = ["Localizable.strings"] + [f"{l}.lproj/Localizable.strings"
                                    for l in ("de","es","fr","ja","zh-Hans")]
def load(p):
    raw = pathlib.Path(p).read_bytes()
    return raw.decode("utf-16") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else raw.decode("utf-8")
key_re = re.compile(r'^\s*"([^"]+)"\s*=', re.M)
per = {t: set(key_re.findall(load(root / t))) for t in tables}
available = set().union(*per.values())
prefixes = {k.split(".")[0] for k in available}

lit_re = re.compile(r'"([a-z][A-Za-z0-9]*\.[A-Za-z0-9.]+)"')
used = set()
for f in root.rglob("*.swift"):
    used |= set(lit_re.findall(f.read_text()))
# 形如 `a.b` 的字符串字面量里，只有前缀与词表前缀吻合的才是本地化键，
# 其余都是 SF Symbol 名（square.grid.2x2、checkmark.circle.fill …）。
used = {k for k in used if k.split(".")[0] in prefixes}

print("keys per table  :", sorted({len(v) for v in per.values()}))
print("sets identical  :", len(set(map(frozenset, per.values()))) == 1)
print("used but missing:", sorted(used - available))
print("defined unused  :", sorted(available - used))
PY
```

两个列表都为空才算通过。

### 看一眼别的语言长什么样

```bash
# 临时用中文启动（不修改系统设置）
/path/to/AppPocket.app/Contents/MacOS/AppPocket -AppleLanguages '(zh-Hans)'
```

**但这个命令对 `NSLocalizedString` 无效。** 命令行参数进的是
`NSArgumentDomain`，而 `CFBundle` 取语言列表时读的是全局域
（`kCFPreferencesAnyApplication`），根本看不到参数域。结果是
`Locale.preferredLanguages` 会显示 `zh-Hans`，界面却依然是英文 ——
很有迷惑性。

可靠的办法是改系统语言，或者改 `.app` 里那份兜底表：

```bash
APP=/path/to/AppPocket.app
cp "$APP/Contents/Resources/zh-Hans.lproj/Localizable.strings" \
   "$APP/Contents/Resources/Localizable.strings"
```

改的是构建产物，不影响源码；重新构建即恢复。

### 自动化

`AppPocketTests` 不覆盖本地化 —— 单元测试跑在测试宿主的语言下，
断言文本会把测试和语言绑死。键集一致性用上面的脚本检查，
界面是否真的换语言则靠离屏截图确认（见 `DESIGN_DOCUMENT.md`
的 “Testing and verification”）。

## 已知问题

- **`SettingsView` 的标签栏在窗口非激活时会看不见文字。** 这是 macOS 分段控件
  在非激活窗口下的绘制方式，不是本地化问题；窗口一获得焦点就正常。
- 应用内没有语言切换开关。这是有意的：跟随系统是 macOS 的惯例，
  加一个应用内覆盖层会引入「系统是中文、应用是英文」这种更难解释的状态。
