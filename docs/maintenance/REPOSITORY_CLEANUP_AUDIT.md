# 仓库根目录整理与双语 README 收尾审计

- 日期：2026-10-30
- 维护分支：`chore/repository-cleanup-readme`
- 基线：`master` @ `8761d40`（v1.1.0 已发布，未改动 tag / Release / Git 历史）
- 范围：文档、测试脚本归档、仓库卫生；不新增功能，不重新发布 v1.1.0

## 1. 处理原则

1. 先用 `git status -sb`、`git ls-files`、`rg` 确认每个文件的跟踪状态和引用情况，再决定去留；没有仅凭文件名删除文件。
2. 误保存的命令输出、`yt-dlp` 原始转储、空文件：确认无引用后从当前版本删除（不重写历史）。
3. 手动诊断脚本：迁移到 `tool/diagnostics/`，保留可执行能力；不把任何真实用户数据或凭证带进新目录。
4. 合成测试夹具：迁移到 `test/fixtures/`。
5. 历史修复 / 实现 / 优化说明：迁移到 `docs/archive/`；仍然有参考价值的设置指南与研究笔记迁移到 `docs/guides/`。
6. 不确定用途的文件保留并标记，等待用户确认。
7. 使用 `git mv` 完成迁移，避免不必要的内容变化；未运行全仓 `dart format`，未改动换行符。

## 2. 审计命令

```text
git status -sb
git ls-files
git ls-files models AV_Data_Capture
git ls-files "*.dart" "*.md" "*.json"
git check-ignore -v models/ AV_Data_Capture/
git ls-files --stage -- AV_Data_Capture
git submodule status
git config --file .gitmodules --get-regexp "submodule\..*"
rg -n "<文件名/符号>" lib test tool scripts .github docs
python -c "..."   # 读取 JSON、核对本地相对链接
```

## 3. 根目录已跟踪文件审计表

大小取自整理前工作区；`跟踪` 均指整理前已被 Git 跟踪。

### 3.1 Flutter / 平台构建必需与工程配置

| 原路径 | 大小 | 类型 | 引用情况 | 建议 | 依据与风险 |
| --- | --- | --- | --- | --- | --- |
| `.gitignore` | ~0.8 KB | 文本 | Git 使用 | 保留并补充 | 新增 `/AV_Data_Capture/` 与 3 条诊断脚本临时 `.py` 规则；不忽略正式代码、测试或配置 |
| `.metadata` | 1.5 KB | Flutter 元数据 | Flutter CLI 使用 | **保留** | Flutter 工具元数据，不是垃圾文件，删除会破坏工具链识别 |
| `analysis_options.yaml` | 1.4 KB | YAML | `flutter analyze` | 保留 | 分析规则配置 |
| `pubspec.yaml` / `pubspec.lock` | 4.5 KB / 27.9 KB | YAML | 依赖与版本 | 保留 | 版本 `1.1.0+3`，构建必需 |
| `devtools_options.yaml` | 184 B | YAML | DevTools | 保留 | 开发工具配置 |
| `android/`、`ios/`、`linux/`、`macos/`、`windows/` | 平台目录 | 平台工程 | 构建与 CI | 保留 | Flutter 平台必需，缺一会破坏对应平台构建 |
| `.github/workflows/release.yml` | 文本 | CI | GitHub Actions | 保留 | 三平台构建并复制根目录 `onnxruntime.dll` |
| `LICENSE` | 1.1 KB | 文本 | README / About | 保留 | MIT 许可证 |
| `AGENTS.md` | 5.3 KB | Markdown | 开发约定 | 保留 | 仓库协作规则，用户明确要求保留 |
| `docs/` | 目录 | 文档 | README / 测试 | 保留 | 版本历史、阶段报告、截图与评估集 |
| `test/` | 目录 | 正式自动化测试 | `flutter test` | 保留 | 461 项测试全部通过 |
| `lib/` | 目录 | 正式源代码 | 应用 / 测试 | 保留 | 本任务不修改运行时代码 |
| `scripts/` | 目录 | PowerShell 工具 | 模型下载说明 | 保留 | `fetch_*_models.ps1` 读取 `models/*_manifest.json` |
| `tool/stage2_desktop_capture.py`、`tool/stage3_uia_probe.py` | 脚本 | 诊断工具 | 阶段报告 | 保留 | 已有归档位置，不重复迁移 |

### 3.2 运行时 / 发布必需资源

| 原路径 | 大小 | 类型 | 引用情况 | 建议 | 依据与风险 |
| --- | --- | --- | --- | --- | --- |
| `onnxruntime.dll` | 15.7 MB | Windows DLL | `.github/workflows/release.yml`、`lib/services/ai_service.dart`、`ai_failure.dart`、`test/ai_pipeline_test.dart` | **保留** | CI 会把它复制进 Release；删除会导致 ONNX 推理与发布包资源缺失 |
| `models/embeddinggemma2_onnx_manifest.json` | 小 | JSON Manifest | `scripts/fetch_embedding_models.ps1`、`test/ai_model_download_test.dart`、`lib/services/ai_model_manifest.dart` | **保留跟踪** | 模型下载/校验的清单，不是模型权重；`/models/` 已忽略权重但清单必须留在索引中 |
| `models/qwen2vl_gguf_manifest.json` | 小 | JSON Manifest | `scripts/fetch_qwen2vl_models.ps1` | **保留跟踪** | 同上，属于 VLM 可下载清单 |
| `models/onnx/`、`models/*.json`（权重与配置） | 大 | ONNX / 配置 | 本地推理 | 本地保留、不跟踪 | `.gitignore` 的 `/models/` 已覆盖；本机文件原样保留 |
| `bilibili_extractor.py` | 4.2 KB | Python 脚本 | `lib/services/platform_support.dart:313` 以 `python bilibili_extractor.py <url>` 调用 | **保留** | 运行时依赖，移动会破坏 Bilibili 信息提取的默认路径 |
| `requirements.txt` | 38 B | Python 依赖 | 安装脚本 / 在线视频指南 | 保留 | `requests`、`bilibili-api` 依赖清单 |
| `install_dependencies.bat` | 451 B | BAT | `docs/guides/ONLINE_VIDEO_SETUP.md` | 保留 | Windows 安装辅助脚本 |
| `install_external_scrapers.bat` | 2.1 KB | BAT | `docs/guides/EXTERNAL_SCRAPERS_GUIDE.md` | 保留 | 外部 scraper 安装辅助脚本 |

### 3.3 明显误保存的命令输出 / 临时转储（已删除）

| 原路径 | 大小 | 类型 | 引用情况 | 建议 | 依据与风险 |
| --- | --- | --- | --- | --- | --- |
| `how --name-only c594429` | 1.8 KB | 文本 | 无 | **删除** | `git log --name-only` 的误重定向输出，包含 ANSI 颜色码 |
| `tatus` | 15.0 KB | 文本 | 无 | **删除** | `less` 帮助页（疑似 `git status` 拼写错误后被分页器写入） |
| `tatus --porcelain` | 500 B | 文本 | 无 | **删除** | 又一份误保存的命令输出，含历史提交行 |
| `t.copyWith 方法中的 description 参数处理逻辑 - 移除调试打印语句` | 15.3 KB | 文本 | 无 | **删除** | 文件名来自搜索命令，内容是 `less` 帮助页，不是源码或文档 |
| `bilibili_test.json` | 18.5 KB | JSON | 无 | **删除** | 一次性 `yt-dlp --dump-json` 转储，非测试夹具 |
| `youtube_test.json` | 112.4 KB | JSON | 无 | **删除** | 同上，含会过期的 CDN 签名 URL |
| `missav_test.json` | 0 B | 空文件 | 无 | **删除** | 空文件，无任何价值 |

### 3.4 手动诊断脚本（已迁移，未删除）

这些脚本都是 `void main()` 命令行诊断程序，不是 `flutter_test` 自动化测试，也没有被 `test/`、CI 或文档引用。

| 原路径 | 大小 | 建议 | 迁移后路径 |
| --- | --- | --- | --- |
| `test_audio_detection.dart` | 3.2 KB | 移动 | `tool/diagnostics/test_audio_detection.dart` |
| `test_bilibili.dart` | 4.0 KB | 移动 | `tool/diagnostics/test_bilibili.dart` |
| `test_custom_javlibrary.dart` | 3.1 KB | 移动 | `tool/diagnostics/test_custom_javlibrary.dart` |
| `test_encoding_detection.dart` | 4.9 KB | 移动 | `tool/diagnostics/test_encoding_detection.dart` |
| `test_final_hybrid.dart` | 3.9 KB | 移动 | `tool/diagnostics/test_final_hybrid.dart` |
| `test_hybrid_service.dart` | 3.9 KB | 移动 | `tool/diagnostics/test_hybrid_service.dart` |
| `test_javlibrary_only.dart` | 4.7 KB | 移动 | `tool/diagnostics/test_javlibrary_only.dart` |
| `test_javscraper_data_structure.dart` | 6.2 KB | 移动 | `tool/diagnostics/test_javscraper_data_structure.dart` |
| `test_missav.dart` | 2.4 KB | 移动 | `tool/diagnostics/test_missav.dart` |
| `test_missav_analysis.dart` | 6.2 KB | 移动 | `tool/diagnostics/test_missav_analysis.dart` |
| `test_missav_data_flow.dart` | 7.1 KB | 移动 | `tool/diagnostics/test_missav_data_flow.dart` |
| `test_missav_encoding.dart` | 6.0 KB | 移动 | `tool/diagnostics/test_missav_encoding.dart` |
| `test_missav_python.dart` | 5.6 KB | 移动 | `tool/diagnostics/test_missav_python.dart` |
| `test_missav_simple.dart` | 4.7 KB | 移动 | `tool/diagnostics/test_missav_simple.dart` |
| `test_simple.dart` | 959 B | 移动 | `tool/diagnostics/test_simple.dart` |
| `test_simple_encoding.dart` | 3.2 KB | 移动 | `tool/diagnostics/test_simple_encoding.dart` |
| `test_specific_issues.dart` | 4.6 KB | 移动 | `tool/diagnostics/test_specific_issues.dart` |
| `test_video_formats.dart` | 5.1 KB | 移动 | `tool/diagnostics/test_video_formats.dart` |
| `test_video_sniffer.dart` | 1.4 KB | 移动 | `tool/diagnostics/test_video_sniffer.dart` |
| `test_xvideos.dart` | 3.2 KB | 移动 | `tool/diagnostics/test_xvideos.dart` |
| `test_youtube.dart` | 4.1 KB | 移动 | `tool/diagnostics/test_youtube.dart` |
| `test_youtube_streams.dart` | 5.7 KB | 移动 | `tool/diagnostics/test_youtube_streams.dart` |
| `test_yt_dlp_integration.dart` | 7.0 KB | 移动 | `tool/diagnostics/test_yt_dlp_integration.dart` |
| `test_scrapegraph_ai.py` | 2.8 KB | 移动 | `tool/diagnostics/test_scrapegraph_ai.py` |

迁移时把 `import 'lib/...'` 改为 `import 'package:video_clip_manager/...'`，使脚本不再依赖“从仓库根目录启动”才能解析导入。脚本内部仍按当前工作目录写临时 `.py` 文件，这是原有行为，未改变。

### 3.5 测试夹具（已迁移）

| 原路径 | 大小 | 类型 | 引用情况 | 建议 | 依据与风险 |
| --- | --- | --- | --- | --- | --- |
| `test_playlist.json` | 637 B | JSON | 无自动引用，合成数据 | 移动 | `test/fixtures/test_playlist.json` |
| `test_playlist_with_clips.json` | 2.1 KB | JSON | 无自动引用，合成数据 | 移动 | `test/fixtures/test_playlist_with_clips.json`；路径是虚构的 `C:\Videos\test_video1.mp4`，不含真实用户数据 |

### 3.6 历史技术文档（已归档）

| 原路径 | 大小 | 建议 | 迁移后路径 |
| --- | --- | --- | --- |
| `IMPLEMENTATION_SUMMARY.md` | 4.4 KB | 归档 | `docs/archive/IMPLEMENTATION_SUMMARY.md` |
| `OPTIMIZATION_SUMMARY.md` | 4.7 KB | 归档 | `docs/archive/OPTIMIZATION_SUMMARY.md` |
| `PLAYLIST_AUTO_PLAY_FIX.md` | 7.0 KB | 归档 | `docs/archive/PLAYLIST_AUTO_PLAY_FIX.md` |
| `PLAYLIST_DEEP_FIX_ANALYSIS.md` | 6.1 KB | 归档 | `docs/archive/PLAYLIST_DEEP_FIX_ANALYSIS.md` |
| `PLAYLIST_FIXES_SUMMARY.md` | 6.3 KB | 归档 | `docs/archive/PLAYLIST_FIXES_SUMMARY.md` |
| `PLAYLIST_ICON_AND_AUTO_PLAY_FIX.md` | 5.6 KB | 归档 | `docs/archive/PLAYLIST_ICON_AND_AUTO_PLAY_FIX.md` |
| `PLAYLIST_OPTIMIZATION_SUMMARY.md` | 9.6 KB | 归档 | `docs/archive/PLAYLIST_OPTIMIZATION_SUMMARY.md` |
| `PLAYLIST_SPACE_KEY_FIX.md` | 5.3 KB | 归档 | `docs/archive/PLAYLIST_SPACE_KEY_FIX.md` |
| `PLAYLIST_UI_IMPROVEMENTS.md` | 6.5 KB | 归档 | `docs/archive/PLAYLIST_UI_IMPROVEMENTS.md` |
| `TAG_CATEGORIZATION_IDEA.md` | 5.0 KB | 归档 | `docs/archive/TAG_CATEGORIZATION_IDEA.md` |
| `VIDEO_TAB_OPTIMIZATION.md` | 4.2 KB | 归档 | `docs/archive/VIDEO_TAB_OPTIMIZATION.md` |
| `ONLINE_VIDEO_SETUP.md` | 4.4 KB | 移动 | `docs/guides/ONLINE_VIDEO_SETUP.md` |
| `EXTERNAL_SCRAPERS_GUIDE.md` | 5.0 KB | 移动 | `docs/guides/EXTERNAL_SCRAPERS_GUIDE.md` |
| `research_better_scrapers.md` | 1.7 KB | 移动 | `docs/guides/research_better_scrapers.md` |

归档文件没有被代码、测试、CI 或 README 引用，只作为历史记录。两份指南中的安装脚本调用补充了“在仓库根目录执行”的前缀说明；`dart test_external_scrapers.dart`（文件从未存在）改为指向 `tool/diagnostics/` 的实际示例。

### 3.7 尚不能确定用途 / 需用户判断

| 路径 | 现状 | 说明 |
| --- | --- | --- |
| `docs/ui-upgrade/logs/**` | 保留跟踪 | 阶段验证日志，含本机绝对路径（如 `C:\Users\...`、`D:\workspace\...`），不含凭证；作为历史记录保留 |
| `docs/ui-upgrade/reference/visual_prototype_only.zip` | 保留 | 视觉原型参考包，AGENTS.md 明确其只作视觉参考 |
| `docs/ui-upgrade/logo/` 候选图 | 保留 | 品牌候选资产，当前应用图标未使用 |
| `tool/diagnostics/` 中多个 `test_missav_*` / `test_*_encoding` 变体 | 保留 | 功能高度重叠，可能已过时；无引用，但删除前建议由作者确认 |
| 根目录本地 Release ZIP | 未跟踪（已忽略） | `video_clip_manager-v1.1.0-windows-x64.zip`、`video_clip_manager-windows-x64.zip` 仅本机存在 |
| 本地 `AV_Data_Capture/` | 未跟踪（已忽略） | 独立上游 Git 仓库，原样保留 |

## 4. AV_Data_Capture 处理结果

调查结论：

```text
git ls-files --stage -- AV_Data_Capture
160000 03d9833ccf50d1c2468214ee6010440c007a9736 0  AV_Data_Capture

git submodule status
fatal: no submodule mapping found in .gitmodules for path 'AV_Data_Capture'

git config --file .gitmodules --get-regexp "submodule\..*"
（无输出）

git -C AV_Data_Capture remote -v
https://github.com/yoshiko2/AV_Data_Capture.git

git grep -n -i "AV_Data_Capture"
（无输出）
```

- 它是**未在 `.gitmodules` 中声明的独立 Git 工作副本**，父仓库只记录了一个 gitlink。
- 复查 `lib/`、`test/`、`tool/`、`scripts/`、`.github/workflows/` 与全部文档：没有构建、CI、运行时或测试依赖。
- 处理：`git rm --cached -- AV_Data_Capture`，仅移除父仓库索引中的 gitlink；**本地目录和 `AV_Data_Capture/.git` 未删除、未移动**（已用 Python 校验 `os.path.isdir` 两项均为 `True`）。
- `.gitignore` 新增 `/AV_Data_Capture/`，避免本地独立目录被再次误加入。
- 未做任何历史重写、未修改 v1.1.0 tag 或已发布 Release。

## 5. 敏感数据检查

- 在根目录被删除/迁移的文件中搜索 `C:\Users`、`/Users/`、`password`、`token`、`api_key`、`secret`、`cookie`、`Authorization` 等模式：**未发现硬编码凭证**。
- `tool/diagnostics/test_scrapegraph_ai.py` 只从环境变量读取 `OPENAI_API_KEY`，文件内没有密钥值。
- 删除的 `youtube_test.json` / `bilibili_test.json` 是公开视频的 `yt-dlp` 元数据转储，含会过期的 CDN 签名 URL，但不含账号、Cookie 或本地用户数据。
- 未跟踪 `models/` 权重、缩略图、向量缓存或用户媒体；本机模型与个人媒体保持原样。
- `docs/ui-upgrade/logs/*/capture-session.json` 含开发机绝对路径，属于既有已公开内容，风险低；本任务仅记录，未改写历史。

## 6. 验证结果

| 检查 | 结果 |
| --- | --- |
| `flutter --version` | Flutter 3.41.7 / Dart 3.11.5 |
| `flutter pub get` | 成功 |
| `flutter analyze` | 无 **error**；共 1344 条既有 `info`/`warning`（主要是 `avoid_print`、`deprecated_member_use`、`unused_import`），退出码为 1 属既有基线，本任务未新增错误 |
| `flutter test` | **461 项全部通过**（`+461: All tests passed!`） |
| `flutter build windows --release` | 成功，产出 `build\windows\x64\runner\Release\video_clip_manager.exe`；同目录含 `flutter_windows.dll`、`data/`、`libmpv-2.dll`、`onnxruntime.dll` 等资源 |
| 双语 README 语言切换 | `README.md` ↔ `README_EN.md` 顶部双向链接正确 |
| 本地相对链接 | `README.md`、`README_EN.md`、`docs/CHANGELOG.md` 全部本地链接/图片存在 |
| 根目录 | 根目录跟踪文件由 62 个降到 15 个（见第 3 节） |
| 误提交命令输出 | 已不再出现在根目录 |
| 正式测试 | `test/` 全部保留，未删除任何自动化测试 |
| Release 资源 | `onnxruntime.dll`、`models/*_manifest.json`、`bilibili_extractor.py` 均保留 |
| 本机模型 / 个人媒体 | 未改动 |
| macOS / Linux CI | 只移动了文档和诊断脚本；三平台 workflow 未引用这些路径，不受影响 |

说明：运行 `flutter test` 时，视觉验证测试会重写 `docs/ui-upgrade/screenshots/` 下 6 张已跟踪截图。为保持发布截图不被无意替换，测试后已用 `git restore` 恢复这些图片，工作区最终干净。

### 6.1 与 master 整合后的复核（第二次全量验证）

在把最新 `master`（含双语 README 合并 `29bc429`）整合进整理分支后，于 `f4e3692` 之上重新执行了完整验证：

| 检查 | 结果 |
| --- | --- |
| `flutter --version` | Flutter 3.41.7 / Dart 3.11.5 |
| `flutter pub get` | 成功（`Got dependencies!`，`pubspec.lock` 未变更） |
| `flutter analyze` | 0 error；**1344** 条既有 info/warning（与整理前基线一致，未新增） |
| `flutter test` | **461 项全部通过**（`+461: All tests passed!`） |
| `flutter build windows --release` | 成功；`build\windows\x64\runner\Release\video_clip_manager.exe`，同目录含 `flutter_windows.dll`、`data/`、`libmpv-2.dll`、`onnxruntime.dll`、各插件 DLL |
| 回归链接 | `README.md` / `README_EN.md` / `docs/CHANGELOG.md` 的 3 张截图与全部本地链接均可解析 |
| 本地资产 | `AV_Data_Capture/` 与 `AV_Data_Capture/.git` 存在；`models/*_manifest.json` 2 份均在；`models/` 权重未被跟踪、未被改动 |

说明（截图）：本轮 `flutter test` 同样重写了 6 张已跟踪的 Widget 截图（`stage1/02_clips_tab_dark.png`、`stage2/widget/interaction_1600x800.png`、`stage2_01/02/03/05`）。逐项核对：只是 PNG 重新编码（字节数相差 1 B ~ 1.2 KB，渲染内容一致），非界面变更。为避免把测试副产物混进整理提交、并保持发布截图稳定，测试后仅对上述 6 个文件做了路径精确的 `git checkout --` 恢复；未对任何未确认用途的文件执行恢复。

## 7. 提交清单

| 提交 | 内容 |
| --- | --- |
| `340382a` `docs(readme): bilingual README (zh/en) and changelog for v1.1.0` | 沿用既有 `docs/bilingual-readme` 分支成果：`README.md`、`README_EN.md`、`docs/CHANGELOG.md` |
| `1938f14` `chore(repo): remove accidental command-output files` | 删除 4 个命令输出文件、2 个 `yt-dlp` 转储、1 个空 JSON |
| `ea4d399` `chore(repo): stop tracking the stray AV_Data_Capture checkout` | 移除父仓库 gitlink，`.gitignore` 增加 `/AV_Data_Capture/` |
| `1694e3c` `refactor(repo): organize diagnostic scripts and fixtures` | 24 个诊断脚本 → `tool/diagnostics/`；2 个夹具 → `test/fixtures/`；修正 `lib/` 导入 |
| `8edc0a4` `docs: archive historical development notes` | 11 个历史说明 → `docs/archive/`；3 个指南/研究 → `docs/guides/` |
| `1d3eb6a` `docs(maintenance): add repository cleanup audit` | 新增本审计文件 |
| `2825639` `chore(repo): ignore diagnostic temp files` | `.gitignore` 补充诊断脚本临时 `.py`；审计文件一处措辞修正 |
| `f4e3692` `Merge master (bilingual README) into repository cleanup branch` | 并入最新 `master`（`29bc429`），无冲突；仅带入 README/README_EN/docs/CHANGELOG 的隐私与 FFmpeg 修正（3 文件 +7/−6） |
| 本文件本次修订所在提交 | `docs(maintenance): record final classification, master integration and re-verification` |

## 8. 32 项未提交改动的最终分类与处理

整理工作区在整合 `master` 前共有 32 项 `git status` 显示的“已修改”文件（`LICENSE`、`docs/ui-upgrade/**`、`lib/**`、`test/**`）。逐项核查结论：

| 分类 | 数量 | 判定依据 | 处理 |
| --- | --- | --- | --- |
| 有意的仓库清理修改 | **0** | 32 个文件的工作区内容经 `git hash-object --path=<f>`（应用 clean 过滤）后与索引 blob **逐一相等**（脚本断言 `content_diff=0`） | 无 |
| 纯 CRLF/LF 换行差异 | **32** | `git diff --quiet` 退出 0；`git diff --ignore-space-at-eol` 无输出；索引存储 LF、工作区为 CRLF（`core.autocrlf=input`），仅 stat 缓存过期 | 用 `git add --renormalize .` 刷新（`git diff --cached` 为空，证明无内容进入暂存） |
| 无关格式变化 | 0 | — | — |
| 无法确定来源 | 0 | — | — |

补充说明：
- 未使用 `git restore`/`git reset`/`git clean` 处理这 32 项，也未丢弃任何内容；`--renormalize` 后 `git status -sb` 输出为干净（0 项）。
- 根因是历史提交以 LF 入库、而工作区文件被 Windows 编辑器/处理器保存为 CRLF。彻底根治需要提交 `.gitattributes`（`* text=auto eol=lf`）并全仓 renormalize，会改写成千上万行的提交，超出本次“文档与仓库卫生”范围，故仅记录、不改写。

## 9. 与最新 master 的整合

- 整理分支原基线为 `340382a`（双语 README 首个提交），`master` 后续新增 `20c6566`（隐私边界 + FFmpeg 范围修正）与合并提交 `29bc429`。
- 合并命令：`git merge --no-ff master`，结果提交 `f4e3692`，**无冲突**。
- 合并只引入 `README.md`、`README_EN.md`、`docs/CHANGELOG.md` 三处修正（+7/−6）；整理分支从未在 `340382a` 之后修改过这三个文件，因此**不会用旧 README 覆盖 master 的新 README**。
- 合并后确认：`README.md` 含“隐私边界”段、`README_EN.md` 含 `Privacy boundary` 段、`docs/CHANGELOG.md` 顶部保留返回 README 的双语链接。

## 10. 大文件与敏感信息复核（整合后）

- 仓库内最大的被跟踪二进制为根目录 `onnxruntime.dll`（约 15.7 MB），是 Release 与 CI 必需资源（`.github/workflows/release.yml` 复制进发布包），保留。
- 未跟踪的 `models/`（含 `tokenizer.json` 约 32 MB 与 ONNX 权重）、根目录 Release ZIP、`AV_Data_Capture/` 均由 `.gitignore` 覆盖，不进入版本库，本机原样保留。
- 对被删除/迁移文件复查 `C:\Users`、`password`、`token`、`api_key`、`secret`、`cookie`、`Authorization`：**无硬编码凭证**；`tool/diagnostics/test_scrapegraph_ai.py` 仅从环境变量读取 `OPENAI_API_KEY`。
- 未改动任何用户媒体、AI 模型权重或向量缓存。

## 11. 保留但需作者确认的项（未处理）

1. `tool/diagnostics/` 中多个高度重叠的 MissAV / 编码诊断脚本：无引用、可能过时，删除前建议作者确认。
2. `docs/ui-upgrade/logs/**`：含开发机绝对路径的阶段性日志，作为历史保留。
3. 是否在双语 README 中增加 `docs/guides/ONLINE_VIDEO_SETUP.md` 与 `docs/guides/EXTERNAL_SCRAPERS_GUIDE.md` 的入口（本次未新增宣传性链接）。
4. 原始视频预览、播放列表、关于页的 v1.1 正式截图尚未重新抓取，README 已按实际情况不展示这些页面。
5. `flutter analyze` 的 1344 条既有提示属于独立清理任务，本任务未处理。

## 12. 准备合并的提交

- 整合 `master` 的合并提交：`f4e3692`
- 本审计最终修订提交：见本文件最后修订的 `docs(maintenance): ...` 提交（运行 `git log -1 --stat` 查看哈希）
- 建议合并方式：`git merge --no-ff chore/repository-cleanup-readme` → `master`（保留整理历史，不重写、不 force push），由用户批准后执行。
