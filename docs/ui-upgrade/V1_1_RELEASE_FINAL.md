# Video Clip Manager v1.1.0 — 最终合并与发布包报告

日期：2026-10-30
状态：**本地合并完成、本地发布包已产出并校验通过。尚未推送、未创建 GitHub Release、未打 tag、未上传、未删除任何分支、未改动正式 Logo。**

---

## 1. 合并

| 项目 | 结果 |
| --- | --- |
| 合并前工作区 | 干净（`git status` 无改动） |
| 合并前 `master` | `a1fbcd9 Merge branch 'feat/dark-ui-workspace' into master` |
| 合并前 `feat/v1.1-release-polish` | `45ad861`，比 `master` 领先 9 个提交，`master` 无分叉提交（merge-base 即 `a1fbcd9`） |
| 合并方式 | `git merge --no-ff feat/v1.1-release-polish` |
| 合并提交 | `e073713 Merge branch 'feat/v1.1-release-polish' into master` |
| 冲突 | 无 |
| 功能分支 | `feat/v1.1-release-polish` 保留（未删除） |
| 当前 HEAD | `fcfbfd5 docs(release): align README with v1.1.0 and add release notes` |
| 与远端关系 | `master` 领先 `origin/master`，**未推送**（合并后的全部 v1.1.0 提交都在本地，其中若干为纯文档提交） |

合并后又追加了 3 个提交（都在 `master` 上，非功能分支）：

```
fcfbfd5 docs(release): align README with v1.1.0 and add release notes
228b1df test(ai): pin the no-model install guidance on a fresh install
e073713 Merge branch 'feat/v1.1-release-polish' into master   <-- 合并提交
```

另外，合并前在功能分支上补了两个小提交（随合并进入 `master`）：

```
45ad861 chore(repo): ignore versioned release zip artifacts   （`.gitignore` 覆盖 video_clip_manager-*.zip）
7cc8c23 chore(license): add MIT LICENSE referenced by README and About
```

## 2. 合并后回归

| 项 | 命令 | 结果 |
| --- | --- | --- |
| 静态分析 | `flutter analyze` | **0 error**；1344 条 info/warning，与合并前完全相同的既有历史项，未新增 |
| 单元/Widget 测试 | `flutter test` | **461 通过 / 0 失败**（合并前 457；新增 4 项见 §3） |
| 发布构建 | `flutter build windows --release` | 成功，`build/windows/x64/runner/Release/video_clip_manager.exe` |
| EXE 版本资源 | `(Get-Item ...).VersionInfo` | `FileVersion = 1.1.0+3`、`ProductVersion = 1.1.0+3`、`FileDescription = Video Clip Manager`、`ProductName = Video Clip Manager` |
| 文件大小 | — | 93,184 字节 |

版本链路保持单一来源：`pubspec.yaml (1.1.0+3)` → 生成的 `generated_config.cmake` → `windows/CMakeLists.txt` 的 `FLUTTER_VERSION_*` → `windows/runner/Runner.rc` 的 `FILEVERSION` / `StringFileInfo`，因此 EXE 属性与「关于」不会各写一套。

合并未改动业务代码（合并前后 `lib/` 完全一致），因此 About / 搜索 / 模型目录 / 播放器不存在"因合并而回归"的可能；上述 461 项测试覆盖了搜索状态、Score 展示与排序、检索质量契约、更新检查、版本一致性、关于对话框、AI 设置无模型指引，以及既有的片段库 / 播放列表 / 播放器流程。

## 3. 为"无模型新环境"补充的验证

原有一处验收点（"AI 功能显示明确的模型安装/下载指引"）只有代码可读、没有执行证据，因此新增 `test/ai_settings_no_model_guidance_test.dart`（4 项，已提交 `228b1df`）：

1. 空模型目录被判定为 **未安装**（`isComplete=false`、`anyFilePresent=false`、`resolveEmbeddingModelDir()=null`），不会被误报"已就绪"；
2. 半途复制（1 个被截断的清单文件）被逐文件判定为 **不完整**，且那份已存在的文件被计入问题；
3. 在该状态下挂载 `AiSettingsDialog`：显示「语义检索模型 (EmbeddingGemma 2)」+「未下载」+「一键下载」，「模型目录」与「片段特征向量库」区块照常渲染，`takeException()` 为 null —— 即缺少模型是**正常状态**而非错误状态；
4. `describeAiFailure(modelMissing / cliMissing)` 的文案必须包含模型缺失说明与 sidecar 放置建议。

说明：`AiSettingsDialog` 的模型检查在 `initState` 中发起，widget 测试的 fake-async 时区不会驱动那类真实文件 I/O，因此 UI 断言针对的是检查返回前的首帧（该帧已经包含状态标签与下载入口）；而"检查结果"本身的正确性由第 1、2 项直接对 `AiService` 断言。二者合起来覆盖了该验收点，且不依赖真实模型。

## 4. 发布包

打包对象是**整个** `build/windows/x64/runner/Release/` 目录，而不是单个 EXE。

| 项 | 值 |
| --- | --- |
| 包名 | `video_clip_manager-v1.1.0-windows-x64.zip` |
| 位置 | 仓库根目录（已被 `.gitignore` 的 `video_clip_manager-*.zip` 覆盖，不会进入版本库） |
| ZIP 大小 | **39.59 MB**（41,516,055 字节） |
| 解压后 | **96.58 MB**，**30 个文件** |
| 压缩包顶层结构 | 单一目录 `video_clip_manager-v1.1.0-windows-x64/`，解压不会散落 30 个文件到当前目录 |
| SHA-256 | `500C9081850F2F6F5132252D74ACC0CB8301B7975E090CCC9FFB826C1B132349` |

### 4.1 包内容（全部 30 项，与构建产物逐字节一致）

| 类别 | 文件 |
| --- | --- |
| 主程序 | `video_clip_manager.exe` |
| Flutter 运行时 | `flutter_windows.dll`、`data/app.so`、`data/icudtl.dat`、`data/flutter_assets/**`（含 `NOTICES`、字体、着色器、`AssetManifest`） |
| 播放内核 (Media Kit) | `libmpv-2.dll` (28.4 MB)、`media_kit_video_plugin.dll`、`media_kit_libs_windows_video_plugin.dll` |
| AI 运行时 | `onnxruntime.dll` (15.7 MB) |
| 图形 / 解压依赖 | `d3dcompiler_47.dll`、`libEGL.dll`、`libGLESv2.dll`、`vk_swiftshader.dll`、`vulkan-1.dll`、`zlib.dll` |
| 插件 | `desktop_drop_plugin.dll`、`url_launcher_windows_plugin.dll`、`volume_controller_plugin.dll`、`native_assets.json` |

**未包含**（已对 ZIP 条目逐条扫描确认：无 `models/` 目录，无任何模型权重文件；唯一以 `.bin` 结尾的是 313 字节的 Flutter 资源索引 `data/flutter_assets/AssetManifest.bin`，不是权重）：
- EmbeddingGemma 2 模型权重（约 530MB）；
- Qwen2-VL 多模态权重；
- `local-media-ai.exe` sidecar（本仓库不产出该二进制）。

### 4.2 完整性校验

1. **构建产物 ↔ 解压内容逐文件 SHA-256 对比**：30 vs 30，**0 处差异**（byte-identical）。
2. **结构校验**：解压后顶层只有一个目录，目录名前缀正确，无嵌套多余层级。
3. **覆盖式校验**：发布 ZIP 由 `fcfbfd5` 的构建产物重新打包生成，SHA-256 针对该文件计算。

## 5. 从 ZIP 解压后的启动冒烟测试

在临时目录解压 ZIP，并以重定向的 `USERPROFILE` / `APPDATA` / `LOCALAPPDATA` 启动，尽量模拟新机器：

| 检查 | 结果 |
| --- | --- |
| 进程启动 | 成功，14 秒后仍存活，`Responding = True` |
| 窗口 | 创建成功（`MainWindowHandle = 2690654`） |
| 已加载模块 | `flutter_windows.dll`、**`libmpv-2.dll`**（播放内核被真实加载） |
| `onnxruntime.dll` | 未被加载 —— 符合预期：无模型时不会触发推理，也没有崩溃 |
| 首次运行写入 | `%APPDATA%\com.vcm\Video Clip Manager\shared_preferences.json`（含 `db_path`、`update_check_at_ms`） |
| 更新检查（远端最新为 v1.0.1） | 记录了节流时间戳、无崩溃、无错误弹窗 —— 远端 1.0.1 不高于本地 1.1.0，判定为"已是最新"，与预期一致 |
| 退出 | 强制结束后无残留进程 |

### 5.1 必须披露的副作用

Windows 的"文档"目录由 Shell 已知文件夹决定，**不受重定向的 `USERPROFILE` 影响**，所以本次冒烟测试实际打开的是本机真实资料库：

`C:\Users\univasity\OneDrive\Documents\VideoClipManager\default_clips.json`

- 该文件在启动后被写入（`LastWriteTime` 落在本次启动时刻）；
- 事后只读校验：**JSON 合法**，`clips=9`、`videos=7`、`playlists=3`，`onlineVideos`/`onlineVideoClips` 为 0，9 个片段均保留 `hitTimestampMs` 字段 —— **结构完整、条目未丢失**；
- 同一目录下既有的缩略图文件未被删除或改动。

结论：真实资料库可用（这反过来证明了发布包能读取旧版本数据），但也说明"干净环境"并未真正隔离，`Documents\VideoClipManager` 与既有数据被触碰过。后续若要严格隔离，应改用独立 Windows 用户或虚拟机。

## 6. 发布前核对

| 核对项 | 结果 |
| --- | --- |
| `pubspec.yaml` 版本 | `1.1.0+3` |
| EXE `FileVersion` / `ProductVersion` | `1.1.0+3` / `1.1.0+3` |
| README 版本徽章 | 原为 `1.0.1`，**已改为 `1.1.0`** |
| README Changelog | 原以 `v1.0.1 (当前版本)` 结尾，**已新增 `v1.1.0 (当前版本)` 并降级 v1.0.1** |
| README 发布包说明 | 新增「Windows 发布包内容与首次运行」：逐项说明必备文件、包内无模型权重、AI 需要模型 + sidecar + FFmpeg |
| LICENSE | 存在，MIT，`Copyright (c) 2026 joopererer`；README 与 About 的 `blob/master/LICENSE` 链接指向该文件 |
| Release Notes | `docs/ui-upgrade/V1_1_RELEASE_NOTES.md`（深色工作区、原始视频预览、播放列表与音量、AI Score/HIT、模型管理、检查更新、升级说明、已知限制） |

## 7. 未验证项与残余风险

1. **真实"无模型机器"未完全模拟**：本机存在 `models/`（516.7 MB，12 个文件）以及 `D:\workspace\local-media-ai\runtime\models`、`D:\workspace\IdeaProjects\video_clip_manager\models`、`D:\workspace\FlutterProjects\video_clip_manager\models` 三个绝对路径候选（代码中的既有开发路径）。因此"AI 显示未下载并引导下载"是**通过测试断言 + 代码路径**证明的，不是在真正缺模型的机器上肉眼看到的。
2. **包内播放/截取的端到端操作未在打包版内用鼠标跑一遍**：可确认的是进程存活、窗口创建、`libmpv-2.dll` 已加载、真实资料库读取成功；实际点开视频播放仍需人工在解压目录里点一次。
3. **界面截图未产出**：本会话的图片读取能力不可用（工具拒绝读取 png/jpg），`PrintWindow` 虽然成功抓到窗口位图，但无法自行确认画面内容，故**没有**把未核实的截图作为证据提交。视觉层面仍以 `docs/ui-upgrade/screenshots/v1_1/` 中生产 widget 渲染图与用户已完成的人工验收为准。
4. **更新检查的真实远端**：发布前核实发现仓库**已有**正式 Release `v1.0.1`（2026-10-26 发布，非 prerelease，含 Windows/macOS/Linux 三个 CI 产物；tag `v1.0.1` 为 annotated tag，指向 `477087d`）。因此"无 Release 时 404"并非唯一现状；本机实测的路径是"远端 1.0.1 低于本地 1.1.0 → 不提示更新"，符合预期。此前文档中"仓库尚无任何 Release"的表述据此更正。
5. **语义检索阈值未调整**：仍为 `minScore = 0.28` 且无 Top-K，低相关结果仍会返回（本版只是把分数如实显示并默认按相关度排序）。真实语料评估表 `semantic_eval/queries.csv` 仍待填写。
6. **包内不含 sidecar**：纯新环境启用 AI 语义搜索，除模型外还需自行获取 `local-media-ai.exe` 与 FFmpeg；提示文案明确，但不是"下载即用"。
7. `docs/ui-upgrade/screenshots/stage1`、`stage2` 下 6 张既有截图会被 `flutter test` 重新生成（内容为该测试的渲染输出）。本次已把它们**备份到 `%TEMP%\vcm_regen_shots\` 后恢复到 HEAD 版本**，以保持工作区干净；未做任何 `reset --hard` / `clean -fd` 等破坏性清理。

## 8. 权限边界执行情况

已执行：本地 `master` 合并（`--no-ff`）、本地构建、本地 ZIP 打包、Release Notes 与报告编写、文档/测试的小幅提交。

**未执行**：
- `git push`（`master` 领先 `origin/master`，全部 v1.1.0 提交仍在本地）
- 创建 GitHub Release
- 推送任何 Git tag
- 上传发布 ZIP
- 删除 `feat/v1.1-release-polish` 或其他分支
- 改动正式 Logo / `app_icon.ico`
- 任何破坏性 Git 清理

## 9. 等待授权后的下一步

1. 决定是否推送 `master`（落后 0 个、领先全部 v1.1.0 提交）。
2. 起 tag（建议 `v1.1.0`）并创建 GitHub Release，附件上传 `video_clip_manager-v1.1.0-windows-x64.zip`，正文使用 `V1_1_RELEASE_NOTES.md`。
3. Release 上线后，实测一次「关于 → 检查更新」：确认已发布同版本时**不会**提示有新版本，并把结果补进本文件。
4. 如需彻底验证"无模型新环境"，在一台干净的 Windows 机器/虚拟机上解压运行，确认 AI 设置的下载引导与普通播放均正常。

## 10. 发布前最终确认（用户授权后、实际推送前）

### 10.1 已核对项

| 项 | 结果 |
| --- | --- |
| 工作区 | 干净（`git status --porcelain` 为 0 条） |
| 当前分支 / HEAD | `master` / `3936f88f6897b655119887aa38a94b54b10e8077`（与用户给出的 `3936f88` 一致） |
| 本地 `origin/master` | `c7011b2f74a450783887bf73a7d4f8b2983b3969` |
| 远端 `refs/heads/master`（`git ls-remote`，只读） | `c7011b2f74a450783887bf73a7d4f8b2983b3969` —— **与本地跟踪分支一致，无新的远程提交** |
| 分叉判断 | `git rev-list --left-right --count origin/master...master` = `0  49` → 领先 49、落后 0，推送为**快进**，无需强推 |
| 远端 tag `v1.1.0` | **不存在**（`git ls-remote --tags origin v1.1.0` 无输出），创建安全 |
| 已有 Release | `v1.0.1`（Latest，非 prerelease，2026-10-26），tag `v1.0.1` 为 annotated tag → `477087d` |
| ZIP 与源码对应 | 发布构建完成于 `fcfbfd5`；此后的 `8e54a67`/`243f36b`/`3936f88` **只改了 `docs/ui-upgrade/V1_1_RELEASE_FINAL.md`**，`lib/`、`windows/`、`pubspec.*`、`assets/` 无任何差异 → ZIP 即当前 HEAD 的代码 |
| ZIP SHA-256 复算 | `500C9081850F2F6F5132252D74ACC0CB8301B7975E090CCC9FFB826C1B132349`，与 §4 记录**一致**；41,516,055 字节 |
| ZIP 结构复检 | 35 个条目 = 30 个文件 + 5 个目录条目；唯一 `.bin` 是 313 字节的 `AssetManifest.bin`；最大文件均为运行时 DLL，**无模型权重** |
| GitHub 权限 | `gh auth status` → 账号 `joopererer`，token scopes 含 `repo`；仓库 `joopererer/video_clip_manager`（public，默认分支 `master`） |

### 10.2 阻断项：仓库自带的发布工作流与人工发布计划冲突

`.github/workflows/release.yml` 的触发条件是 `push: tags: v*`，其中 `publish-release` job 用 `softprops/action-gh-release@v2` **自动创建 Release**，且：

- 标题固定为 `Release ${tag}`，不是「Video Clip Manager v1.1.0」；
- 正文由 `generate_release_notes: true` 自动生成，**不会**使用 `V1_1_RELEASE_NOTES.md`；
- 附件来自 CI 三平台构建，Windows 包名为 `video_clip_manager-windows-x64.zip`（无版本号），与本地产出的 `video_clip_manager-v1.1.0-windows-x64.zip` 是**两个不同的二进制**；
- `prerelease: false`。

因此，一旦推送 `v1.1.0` tag，CI 会先建好一个标题/正文/附件都与本次发布计划不同的 Release；随后用 `gh release create v1.1.0` 会因已存在而失败，改用编辑则会覆盖正文并产生重复附件。此外通过 `gh release create --target master` 让 GitHub 代建 tag，同样会触发该工作流。

**结论：在用户就"如何处理该工作流"作出决定之前，不执行 tag 推送与 Release 创建。**

### 10.3 尚未满足的前置条件

用户要求"未经确认最终 ZIP 的人工播放测试通过，不得开始实际推送与 Release 创建"。截至本节撰写，**尚未收到该确认**，因此 `git push`、tag、Release 均未执行。

### 10.4 本轮更正的事实

- 仓库**已有**正式 Release `v1.0.1`，此前"仓库尚无任何 Release、`/releases/latest` 404"的表述不准确，已在 §7 第 4 条与 Release Notes 的「已知限制」中更正。
- 冒烟测试时远端最新 Release 已为 `v1.0.1`，因此当时走的是"远端版本更低 → 不提示更新"的分支，而非 404 分支。

## 11. 正式发布结果（2026-10-30）

人工验收通过后执行，全部操作均为普通推送与手工发布，未使用 force push / reset / clean。

| 项 | 值 |
| --- | --- |
| GitHub Release | https://github.com/joopererer/video_clip_manager/releases/tag/v1.1.0 |
| Release 标题 | `Video Clip Manager v1.1.0` |
| Release 状态 | 正式稳定版（`prerelease: false`、`draft: false`），发布时间 `2026-10-30T00:30:46Z` |
| Tag | `v1.1.0`（annotated tag，object `55726df`） |
| Tag 指向提交 | `d39996c5ba4825579d3262a299034fec6496faeb` |
| 推送 | `c7011b2..d39996c  master -> master`（快进，无 force） |
| CI 运行 | run `40979395665`，结论 **success**（Windows / macOS / Linux 三个构建 + Publish 全部成功） |
| `/releases/latest` | `v1.1.0`、非 prerelease → 1.1.0 客户端检查更新时判定为"已是最新"，不会误报 |

### 11.1 附件

| 附件 | 大小 | SHA-256 | 来源 |
| --- | --- | --- | --- |
| `video_clip_manager-v1.1.0-windows-x64.zip` | 41,516,055 | `500c9081850f2f6f5132252d74acc0cb8301b7975e090ccc9ffb826c1b132349` | **本地构建 + 人工实测通过**，手工上传 |
| `video_clip_manager-windows-x64.zip` | 40,973,205 | `22680763ae50ef43c8f2187cb53185f47670558e6893097f3bc9fa6a32f7de12` | CI（GitHub Runner）构建 |
| `video_clip_manager-macos.zip` | 38,878,617 | `772e7ed978c3f456fb18c7b8af5a4a9c96bfde7febf2e06c6a26024b3e9cf392` | CI 构建，保留 |
| `video_clip_manager-linux-x64.tar.gz` | 11,773,352 | `2801806a660cac8e08add71c9661790652a8522eb4bfb52e8d41375ad9f9572c` | CI 构建，保留 |

两个 Windows 包**不等价**（实测差异）：本地包 30 个文件且带外层目录 `video_clip_manager-v1.1.0-windows-x64\`；CI 包 27 个文件、无外层目录（解压即当前目录）。两者都含 `libmpv-2.dll` 与 `onnxruntime.dll`，都不含模型权重。Release 正文已说明应以 SHA-256 区分，人工验证过的是带版本号的那一份。

从 Release 重新下载 `video_clip_manager-v1.1.0-windows-x64.zip` 后校验：41,516,055 字节、SHA-256 `500C9081…2349`，与本地一致；Release 页面与下载链接均返回 HTTP 200。

### 11.2 未做与遗留

- **未删除** CI 产出的 `video_clip_manager-windows-x64.zip`（删除附件不在本次授权范围内）。若希望发布页只保留一个 Windows 包，需要单独授权后删除，并保留 CI 的 macOS/Linux 产物。
- **未修改** `.github/workflows/release.yml`，后续任何 `v*` tag 推送仍会自动构建三平台并创建/更新对应 Release（正文会被 `generate_release_notes` 覆盖），因此**下一次发版**需要重复本轮的"发布后编辑正文"步骤。
- **未改动**版本号、Logo 与安装程序形态。
- 本报告新增的 §11 是在发布提交之后追加的文档提交；Tag `v1.1.0` 仍指向发布提交 `d39996c`。
