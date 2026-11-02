# Noty 开发约定

## 项目与验证

- 这是原生 macOS SwiftUI/AppKit 应用；所有 `Sources/*.swift` 会由 `build.sh` 自动编译。
- 修改编辑器、持久化或同步逻辑后，先运行 `./scripts/test-editor.sh`，再运行 `./build.sh debug`。
- 发布安装包使用 `BUILD_ARCHS=arm64 ./build.sh` 后执行 `./scripts/make-dmg.sh <version>`。需要通用版时不要省略 `BUILD_ARCHS`。
- 不要手工改动 `build/` 产物；它们均由构建脚本生成。

## 逐条状态标签

- 状态定义由 `Settings.noteStatuses` 保存在 UserDefaults，默认状态为：开发中、已开发、待测试、已阻塞；设置窗口的“状态”页负责增删、改名和调色。
- 状态属于**光标所在的文本行**，而不是整张便签。编辑器标题栏的标签菜单调用 `EditorBridge.setStatusForCurrentLine(_:)`。
- 编辑器里的状态控件全部是 `LineStatusOverlayManager` 派生的浮层（`Sources/LineStatusOverlay.swift`）：
  - 未设置状态的复选框行显示行末“＋状态”胶囊（`LineStatusQuickButton`）；行末空间不足时降级为 16pt「+」迷你胶囊，再不足则整颗隐藏，绝不允许盖住文字。
  - 已设置状态的行显示彩色胶囊徽章（`LineStatusBadgeButton`），样式对齐 `NoteStatusBadge`；行内原始文字（含书名号）只保留占位宽度、由浮层负责显示。
  - 两者继承 `LineStatusOverlayButton`（统一的 hover/按压/手型光标/无障碍），并都必须通过 `TaskTextView.showLineStatusMenu` 进入同一状态菜单，不能绕过 `EditorBridge` 直接改正文。
- 行内存储格式是可读标签加稳定 id，例如：`〔待测试〕<noty-status:noty-status-testing>`。`LineStatus` 统一负责写入、替换、改名、清除和摘要时剥离该格式；不要在其他地方自行解析该字符串。
- `EditorStyleEngine.styleLineStatuses` 只负责隐藏稳定 id（`.notyHidden`，字符宽度塌缩为零）和把可读标签的前景色置透明（**保留宽度**，供光标与选区行走；不要对它用 `.notyHidden`，否则徽章浮层没有定位空间）。修改状态定义时，必须让 `Settings.noteStatusStyleToken` 进入编辑器的 `styleToken`，以触发已打开便签的重绘。
- 删除一个状态定义时，要同时清除所有便签中使用它的行内标签（`NoteStore.clearLineStatus(id:)`），避免留下不可维护的标签。

### 浮层易错点（踩过的坑）

- `LineStatus.match` 返回的范围是**行内局部坐标**；传给 `NSLayoutManager`（`glyphRange(forCharacterRange:)` 等）前必须加上 `lineRange.location` 换算成全文坐标，否则徽章定位错乱、渲染不出来。
- 浮层按行位置复用，但复用前必须比对 `reuseKey`（chip 分全称/紧凑；徽章含状态 id+标签+颜色）。否则 chip ↔ 徽章互换、改名或调色后旧控件不刷新，要等下一次别的编辑才更新。
- 浮层只在两种时机重排：滚动/视图 frame 变化的通知，以及编辑 coordinator 在样式 pass 后显式调用的 `lineStatusOverlays?.refresh()`（`NoteEditor.swift` 的 `applyIncremental` 和 full pass 两处）。新增浮层类型时两处都要接上。
- 隐藏行内原始文字是安全的，前提是所有编辑器都走 `NoteTextView.makeNSView`（会 attach overlay manager）；新增绕过 `NoteTextView` 的文本视图时浮层不会生效。

## 数据兼容性

- 便签正文、SQLite、iCloud Markdown 和 `.stickies` 导出都需保持兼容。新增每便签字段时同步更新 `Store` 迁移、`NoteDocument` 和 `StickyNote`。
- 行状态保留在正文中，因此会自然随正文同步；不要把状态名称仅保存在界面状态里。
- 预览、任务标题和搜索摘要不能泄漏 `<noty-status:…>` 存储标记，应通过 `LineStatus.stripping(from:)` 处理。
