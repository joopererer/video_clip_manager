# v1.1.0 发布准备报告

分支：`feat/v1.1-release-polish`（基于本地 `master` `a1fbcd9` 新建，未重新合并任何旧功能分支）
日期：2026-10-29
状态：待用户确认 Logo，未推送、未合并 `master`、未创建 GitHub Release。

## 0. 基线核实

| 项目 | 合并后基线 | 本次结果 |
| --- | --- | --- |
| 版本号（`pubspec.yaml`） | `1.0.1+2` | `1.1.0+3` |
| Windows EXE `FileVersion` | `1.0.1+2` | `1.1.0+3`（实测 Release 产物） |
| Windows EXE `ProductVersion` | `1.0.1+2` | `1.1.0+3` |
| `flutter test` | 398 通过 | **457 通过**（+59） |
| `flutter analyze` | 无 error | 无 error（1344 条 info/warning，均为既有历史项） |

版本链路保持不变：`pubspec.yaml` → `windows/flutter/ephemeral/generated_config.cmake`（Flutter 生成，不提交）→ `windows/CMakeLists.txt` 的 `FLUTTER_VERSION_*` → `windows/runner/Runner.rc` 的 `FILEVERSION` / `StringFileInfo`。因此 EXE 属性与 About 不会各写一套。

`Runner.rc` 另外把 `FileDescription` / `ProductName` 从 `video_clip_manager` 改成可读的 `Video Clip Manager`（仅展示字符串，不影响版本号与文件名）。

## 1. A 搜索交互提示

保持既有行为：输入即关键词筛选；Enter 或点击搜索框 ✨ 才执行 AI 语义搜索。**没有**新增"输入即自动 AI 搜索"。

| 场景 | 界面表现 |
| --- | --- |
| 输入框为空 | 占位符提示"输入关键词实时筛选，按 Enter 或点击 ✨ 进行 AI 语义搜索…"，状态条显示 `关键词筛选` + `按 Enter 或点击 ✨ 进行 AI 语义搜索` |
| 输入关键词 | 同上，实时关键词匹配 |
| AI 检索中 | 状态条 `AI 语义检索中` + 旋转指示器 + 阶段文案；内容区顶部出现"AI 语义检索中…「查询词」"横幅 |
| 有语义结果 | 状态条 `AI 语义结果 (N 个)` + `已按相似度排序，按 Enter 可重新搜索`；内容区横幅显示 `AI 语义搜索结果：「查询词」 共 N 个结果` 与"清除 AI 结果" |

实现要点：

- 新增 `lib/utils/search_mode.dart`：`SearchMode` 与 `resolveSearchMode` / `searchModeLabel` / `searchActionHint` / `semanticResultHeadline` / `formatSemanticScore`，UI 与测试共用同一套判定。
- `AppState` 新增 `semanticQuery`、`searchQueryText`、`syncSearchQueryText`、`hasStaleSemanticResults`、`_semanticResultToken`。
- **过期 HIT 不显示**：查询词一变即清空分数与 HIT（`trim` + 大小写不敏感比较，仅空格变化不清空）；进行中的请求用 token 失效，迟到结果整体丢弃，不会出现半新半旧。
- **防止重复 Enter**：`performSemanticSearch` 在检索中直接返回；`MainScreen` 入口也做同样拦截。测试断言重复触发只发生 1 次 `embedText`。
- 结果改为完成后整体提交（先写入局部 map，结束时一次性落地），避免检索过程中出现部分结果。

回归测试：`test/search_state_test.dart`（14 项）、`test/search_header_hint_test.dart`（5 项）。

## 2. B 语义检索质量审计

结论与证据见 `docs/ui-upgrade/semantic_eval/README.md`，自动化契约在 `test/semantic_retrieval_quality_test.dart`（6 项）。

要点：

1. **不是 Top-K**：返回的是全部 `score >= minScore` 的片段，12 个同等相似度片段全部返回。
2. **minScore = 0.28**（`performSemanticSearch` 默认值，调用处不覆盖）；分数是余弦相似度，理论 `[-1,1]`，实测落在 0.28–0.95。
3. **没有"凑数量"逻辑**，但阈值是唯一门限，所以 0.30 这类低分结果会被返回——这与用户"自行车 6 个结果只有 1 个相关"的观感一致。**本阶段未提高阈值、未删除低分结果**，只记录分布。
4. **片段分数 ↔ 命中帧一致**：`computeMaxSim` 同一帧同时产出 `score` 与 `hitTimestampMs`；广/窄区间用例验证命中帧落在片段区间内且是 argmax。
5. **排序**：`AppState.getFilteredClips` 原本按分数降序，但 `ClipsTab` 用默认"最新添加"重排，把语义排序覆盖了 —— 这是本次发现的明确排序缺陷，已最小修复（见第 3 节）。
6. **中文查询预处理**：仅 `trim` + `search_query: ` 前缀，原文不被分词或清洗改写。

同时修复一个相关缺陷：HIT 时间戳此前会随 `updateClip` 落库（`VideoClip.toJson` 含该字段），重启后仍显示旧 HIT。现在写入前剥离，读取时对无当前命中的片段也剥离；**用户数据 JSON Schema 未改动**。

评估集：`docs/ui-upgrade/semantic_eval/queries.csv`（自行车 / 短裤 / 雪山 / 雨夜街道 / 复合查询等），列含搜索词、位次、Score、HIT 时间码、相关性、命中帧是否正确。真实语料需用户在装有模型与 sidecar 的环境填写，见第 8 节。

严格 / 平衡 / 宽松三种检索模式方案已写入评估集 README，本阶段**不实现**。

## 3. 语义 Score 显示与排序

- 网格（`ClipCard`）：`Score: 0.xxx` 位于缩略图左上角 HIT 时间码正下方，与 HIT 同组叠放，不挤占布局。
- 列表（`ClipListRow`）：位于标题行右侧 `命中: mm:ss` 正下方，右对齐；右侧播放/编辑/收藏/更多按钮宽度不受影响（测试断言按钮仍可命中、无溢出异常）。
- 分数来自 `AppState.semanticScores[clip.id].score`，**不重新计算、不伪造**；三位小数（`0.863`），组件 tooltip 明确写"语义相似度（余弦相似度），不是准确率或可信概率"。
- 只有存在真实语义分数时才显示；普通关键词结果完全没有 `Score:`。
- 新增排序项 `相关度最高`（`SortOption.relevance`），语义分数存在时默认启用；严格按分数降序，无分数的关键词命中排在最后；排序未被用户手动切换过时自动跟随模式，切换后固定为用户选择。切换排序不丢失 HIT 与 Score（测试覆盖网格/列表两种模式）。
- 无分数时该排序项置灰并提示"需 AI 语义结果"。

回归测试：`test/semantic_score_display_test.dart`（8 项）。

## 4. C 版本与 About

- `pubspec.yaml`：`1.1.0+3`。
- `windows/runner/Runner.rc`：版本仍由 `FLUTTER_VERSION_*` 派生；展示字符串改为 `Video Clip Manager`。
- `windows/CMakeLists.txt`：无版本写死，`project(video_clip_manager)` 与 `BINARY_NAME` 未改动。
- About 改为 `lib/widgets/about_dialog.dart`，动态显示：版本号、构建号、仓库地址（可点击打开）、许可证入口（`showLicensePage` + MIT 说明）、Releases 页面、检查更新。旧版本里硬编码的 `版本: 1.0.1` 与功能列表已删除。
- `lib/app_info.dart` 的 `AppVersion` 来自 `package_info_plus`（Windows 读取 EXE 版本资源），测试环境回退常量；`test/version_consistency_test.dart` 断言 pubspec ↔ `AppInfo` ↔ `Runner.rc` 一致。
- `package_info_plus` 本就是 `wakelock_plus` 的传递依赖（8.3.0），本次仅提升为直接依赖并锁定同一版本，`pubspec.lock` 只改了 `dependency: transitive → direct main` 一行，未升级其他包、未改动 SDK 约束。

## 5. D 检查更新

审计结论：应用此前**没有**任何更新检查（`lib` 内无 github/releases/version 相关逻辑）。

本次实现（`lib/services/update_service.dart` + `lib/utils/semver.dart`）：

- 只请求 `https://api.github.com/repos/joopererer/video_clip_manager/releases/latest`（官方仓库，`latest` 端点本身已排除预发布）。
- SemVer 比较：解析 `v1.2.3` / `1.2` / `1.1.0-beta.1`；数值比较（1.10 > 1.9）；预发布低于同号正式版；标签不可解析、404、5xx、超时、断网、坏 JSON 都返回 `error` 而不是抛异常。
- 仅当远端版本严格大于当前版本才提示"发现新版本"；同版本或更旧版本一律不提示。
- 显示版本号、发布日期与 release notes；点击按钮用 `url_launcher` 打开真实 GitHub Release 页面。
- 启动静默检查：延迟 8 秒、最多每 12 小时一次、失败完全静默、不阻塞启动；只有发现新版本才弹一条非模态提示，并引导到「关于」。
- 手动入口：About → 检查更新。
- 隐私：只发一个 GET（测试断言无 query、无 body），不上传媒体、模型或向量数据。
- 本阶段**不做** EXE 自我覆盖、后台自动安装、强制升级。

测试：`test/update_service_test.dart`（13 项）、`test/about_dialog_test.dart`（4 项）。

## 6. E Logo / Icon 候选（待确认）

`docs/ui-upgrade/logo/LOGO_CANDIDATES.md`，预览图 `docs/ui-upgrade/logo/logo_candidates_preview.png`。

四个候选（A 四帧+第二帧高亮 / B 三帧+居中高亮 / C 双帧极简+右侧高亮 / D 微透视胶片带），统一：深色圆角底 `#171A20`、紫色强调 `#8B7CF6`、上下齿孔、无文字、无剪刀/播放按钮/AI 星星。

16 px 下"选中帧"仍可见的客观指标（紫色像素数）：A 12 / B 16 / **C 20** / D 7；32 px：A 40 / B 61 / **C 110** / D 38。

已产出 SVG 母版 + 1024/256/64/48/32/16 PNG + 对照预览图与可复现脚本。**`app_icon.ico` 未改动，Runner 未接入**；等用户确认后再导出 ICO 并接入。

## 7. 截图

Flutter 侧（由 `test/v1_1_visual_verification_test.dart` 用生产 widget 渲染，可复现）：

- `docs/ui-upgrade/screenshots/v1_1/01_grid_semantic_score.png` — 网格 + Score + 默认相关度排序 + 结果横幅
- `docs/ui-upgrade/screenshots/v1_1/02_list_semantic_score.png` — 列表 + `命中: mm:ss` + Score
- `docs/ui-upgrade/screenshots/v1_1/03_keyword_hint.png` — 关键词模式与 Enter/✨ 提示（无语义结果）
- `docs/ui-upgrade/screenshots/v1_1/04_semantic_loading.png` — AI 检索中状态
- `docs/ui-upgrade/screenshots/v1_1/05_about_dialog.png` — About：版本 1.1.0 · 构建 3，发现新版本 v1.2.0 与发布说明
- `docs/ui-upgrade/screenshots/v1_1/06_release_exe_icon.png` — 从 Release EXE 实际抽取的 32 px 图标（证明 Runner 图标资源完好、未被误替换）

Windows 实机驱动脚本：`docs/ui-upgrade/scripts/capture_v1_1_windows.ps1`（UIA 语义树）、`docs/ui-upgrade/scripts/capture_v1_1_click.ps1`（坐标点击 + 截图）。本次会话中两者都未能产出可用的界面截图，见第 9 节。

## 8. 验证

| 项 | 结果 |
| --- | --- |
| `flutter analyze` | 0 error；1344 info/warning 全部为既有问题（未新增） |
| `flutter test` | **457 通过 / 0 失败** |
| `flutter build windows --debug` | 成功 |
| `flutter build windows --release` | 成功，`build/windows/x64/runner/Release/video_clip_manager.exe` |
| Release EXE 版本资源 | `FileVersion 1.1.0+3`、`ProductVersion 1.1.0+3`、`FileDescription Video Clip Manager` |
| Release EXE 图标 | 可抽取 32×32 图标（沿用现有 `app_icon.ico`） |
| 桌面 fixture 启动 | `test/fixtures/v1_1_desktop_fixture.dart` 构建后启动成功，窗口 `video_clip_manager` 创建，媒体缺失只产生"源文件缺失"占位与既有超时日志，未崩溃 |

新增测试文件：`search_state_test.dart`、`search_header_hint_test.dart`、`semantic_score_display_test.dart`、`semantic_retrieval_quality_test.dart`、`update_service_test.dart`、`version_consistency_test.dart`、`about_dialog_test.dart`、`v1_1_visual_verification_test.dart`。

## 9. 未验证项与限制

1. **真实语义检索**：开发环境没有 sidecar 二进制与 EmbeddingGemma 2 模型（`D:\workspace\local-media-ai\target` 为空），因此 `自行车` / `短裤` 的真实分数分布尚未填表；需要用户在装有模型的机器上按 `semantic_eval/README.md` 记录。
2. **Windows 实机截图**：本次会话无法抓取真实窗口画面（`CopyFromScreen` 报 `handle is invalid`，Flutter 也只在 UIA 客户端请求后异步填充语义树，本次只看到 `Window / Pane(FLUTTERVIEW)`）。因此"真实应用里的搜索状态、About、更新入口"是**用生产 widget 渲染的截图 + 自动化断言**证明的，不是实机像素截图，需用户人工复核一次。
3. **真实更新检查**：仓库目前没有任何 Release，`/releases/latest` 会返回 404；该分支已被"尚未发布任何正式版本"覆盖（单测），但真实网络下的成功路径尚未在实机验证。
4. **Logo**：用户本轮选择**暂不改动图标**，`app_icon.ico` 保持现状；候选与接入流程仍保留在 `logo/LOGO_CANDIDATES.md`，后续确认后再导出 ICO 并接入 Runner。
5. **许可证文件**：已补 `LICENSE`（MIT，`Copyright (c) 2026 joopererer`），README 与 About 的 `blob/master/LICENSE` 链接在合并到 `master` 后即可正常打开。
6. 播放界面的「相关度最高」排序退化为稳定顺序（播放页不持有语义分数），语义命中时间与分数不受影响。

## 10. 提交

```
15e5e49 feat(about): bump to v1.1.0+3 and show packaged version in About
3378fc5 feat(update): add non-intrusive GitHub release update check
82bed1f feat(search): make the manual AI trigger explicit and drop stale HITs
805b3a0 feat(clips): show the real semantic Score and add relevance sorting
817ac44 docs(ai): add reproducible semantic retrieval audit and eval set
b1a8046 docs(design): add film strip logo candidates and previews
```

（本文件与截图、桌面 fixture 脚本作为最后一个提交追加。）

未执行：`git push`、合并 `master`、创建 GitHub Release、修改 `app_icon.ico`。
