# AI 稳定性修复与播放器体验收尾报告

分支：`feat/dark-ui-workspace`  
生成日期：2026-06-16  
当前状态：未合并 master，未发布 Release。

## 1. 自动化验证结果

- `dart format`：已对本轮修改的 Dart 文件执行格式化（仅修改文件）。
- `flutter analyze`：无 error；1453 项均为 info/warning（与基线一致）。
- `flutter test`：通过，394 项全部通过（`All tests passed!`）。
- `flutter build windows --debug`：成功。
- `flutter build windows --release`：成功。
- 模型文件校验：`models/` 下 10 个 EmbeddingGemma 2 文件按 `models/embeddinggemma2_onnx_manifest.json` 的尺寸与 SHA-256 全量校验通过（约 541.8 MB）。

## 2. 三个 AI 问题根因与修复证据

### A. LM Studio 连接

根因判定：用户本机 PowerShell 诊断显示 `127.0.0.1:1234` TCP 连接失败、`/v1/models` 无法访问，因此本次故障属于 **环境/服务未就绪**，不是程序 Bug。程序侧已做准确区分与引导。

修复与证据：

- `lib/services/vlm_connection_probe.dart`：统一探测 `/v1/models` 与 `/v1/chat/completions`，对 connection refused / timeout / 404 / 401 / 500 / JSON 错误分别归类，LM Studio 时在 connection refused 时提示检查 Developer 页面 API Server 与端口。
- `lib/widgets/ai_settings_dialog.dart`：连接成功后展示服务模型列表（`_serverModels`），支持点击选用真实模型 ID；LM Studio 预设 URL 为 `http://localhost:1234/v1`。
- Ollama 请求格式保持不变，仅 LM Studio 增强探测与提示；不自动启动外部服务，不修改代理/防火墙。

无法复现时诊断步骤：

1. 在 LM Studio Developer 页面确认 API Server 已启动、端口为 1234。
2. PowerShell 执行 `Test-NetConnection 127.0.0.1 -Port 1234`。
3. 执行 `Invoke-RestMethod http://127.0.0.1:1234/v1/models`。
4. 确认已加载模型且模型 ID 与输入一致。
5. 若仍失败，检查防火墙/代理，但程序不会自动修改。

### B. EmbeddingGemma 2 下载与校验

根因：earlier releases 仅依据文件存在判定就绪；下载脚本退出码 1 未被结构化捕获。现已改为原生 Dart 下载器与 sha256 校验。

修复与证据：

- `lib/services/ai_model_downloader.dart`：捕获 stdout/stderr、退出码、文件路径、HTTP 状态、OS errno；区分网络/DNS/代理/工具缺失/权限/磁盘空间/校验失败；断点续传 `.part`；失败不破坏已有有效文件。
- `lib/services/ai_service.dart`：`resolveEmbeddingModelDir()` 仅在所有 manifest 文件尺寸与 sha256 完整时判定就绪；`inspectEmbeddingModel()` 提供 cheap state。
- `lib/widgets/ai_settings_dialog.dart`：未就绪时显示下载/修复按钮；提供重试与错误详情；校验状态与下载状态以磁盘为准，不互相矛盾。
- 测试：`test/ai_model_download_test.dart` 覆盖缺失文件、无权限、成功校验、失败路径等；`ModelManifest` 测试守护 `lib/services/ai_model_manifest.dart` 与 `models/embeddinggemma2_onnx_manifest.json` 不漂移。

### C. 片段特征向量库构建失败

根因：帧抽取链路未捕获具体视频路径/时间戳/命令/stderr；单点失败无条件终止；相对/绝对时间可能混淆。

修复与证据：

- `lib/services/ai_failure.dart`：定义 `AiStage`（extraction/inference/storage）、`AiFailureKind` 与 `AiStageException`，区分提帧失败、模型推理失败、索引存储失败。
- `lib/services/ai_service.dart`：`extractClipFrames()` 与 `embedFrames()` 捕获 FFmpeg/sidecar 命令、超时、stderr、退出码；`normalizeFrameTime()` 处理 `Seek` / `Filter` 时间语义。
- `lib/services/delta_engine.dart`：`syncClipRange()` 对缺失帧做增量规划；提取失败、推理失败、无向量结果均 surfaced；`resolveClipIndexRange()` 处理 `end == 0` 与超 duration。
- `lib/services/frame_embedding_pool.dart`：原子写入 `.tmp` + rename，损坏缓存隔离为 `.corrupt-*`，存储失败 surfaced；不可读缓存不会被覆盖。
- `lib/data/app_state.dart`：`indexAllClips()` 单片段失败跳过并记录；环境级失败停止批次；支持再次执行时增量重试；不破坏已成功缓存。
- 测试：`test/ai_pipeline_test.dart` 覆盖本地视频、不可访问视频、失败恢复、缓存一致性。

## 3. 音量控制共享组件与四处接入

- 新增 `lib/widgets/common/volume_control.dart`：紧凑横向音量条 `[图标] ──●── [65%]`，范围 0–100，点击图标静音/恢复，记住静音前音量，拖动不触发 seek/快捷键。
- 接入：原始视频预览弹窗、`ClipPlaybackScreen`、`ClipEditorScreen`、`PlaylistPlaybackScreen`。
- 使用 `Player.setVolume()`，不创建额外 Player，不改播放器生命周期。
- `flutter test` 中预览测试通过。

## 4. 自定义 AI 模型存储目录

- `lib/data/app_state.dart`：新增 `aiModelDir` getter 与 `setAiModelDir()`，保存在 SharedPreferences，不改业务 JSON Schema。
- `lib/services/ai_service.dart`：`customEmbeddingModelDir` 作为唯一配置来源，优先于默认候选目录；下载/校验/加载/路径展示使用同一来源。
- `lib/widgets/ai_settings_dialog.dart`：新增“模型目录”与“浏览”、恢复默认；验证存在性与读写权限；切换时提供“仅使用新路径 / 复制现有模型 / 取消”；复制进行完整性验证，失败回滚旧目录与配置；复制过程中拒绝覆盖目标目录已有同名文件，失败时删除本轮复制文件；忙碌时禁止切换。
- 明确区分应用内 EmbeddingGemma 与 LM Studio/Ollama 外部服务模型。

## 5. 本轮提交

| Commit | 内容 |
|---|---|
| `15eafa0` | AI 提帧、失败分类、向量索引恢复与缓存保护 |
| `b238676` | 四处播放器共享音量控件 |
| `f37168e` | 自定义 EmbeddingGemma 模型目录与安全复制 |
| `83da816` | 声明 `collection` 依赖 |
| 最后一提交 | 本报告更新 |

本会话未执行 `git reset --hard`、`git clean` 或覆盖用户原有修改。

## 6. 本轮修改文件

AI 提帧与向量索引：

- `lib/data/app_state.dart`
- `lib/services/ai_failure.dart`
- `lib/services/ai_service.dart`
- `lib/services/delta_engine.dart`
- `lib/services/frame_embedding_pool.dart`
- `test/ai_pipeline_test.dart`

音量控制：

- `lib/widgets/common/volume_control.dart`
- `lib/widgets/video_preview/video_preview_dialog.dart`
- `lib/screens/player/clip_editor_screen.dart`
- `lib/screens/player/clip_playback_screen.dart`
- `lib/screens/player/playlist_playback_screen.dart`

自定义模型目录：

- `lib/widgets/ai_settings_dialog.dart`

依赖与文档：

- `pubspec.yaml`
- `pubspec.lock`
- `docs/ui-upgrade/AI_STABILITY_AND_UX_REPORT.md`

相关前置文件（在本轮前的提交中已完成，本轮构建于其上）：

- `lib/services/ai_model_downloader.dart`
- `lib/services/ai_model_manifest.dart`
- `lib/services/ai_model_verifier.dart`
- `lib/services/vlm_connection_probe.dart`
- `test/ai_model_download_test.dart`
- `test/vlm_connection_probe_test.dart`

## 7. 模型 Manifest 校验

- 仓库：`onnx-community/embeddinggemma-2-ONNX`
- 固定 commit：`daa72c51243991dfcaf9f9137d2c573d8f7790c0`
- 清单文件：`models/embeddinggemma2_onnx_manifest.json`
- 代码常量：`lib/services/ai_model_manifest.dart` 中的 `embeddingGemmaManifest`
- 文件数：10
- 总大小：541,781,770 bytes（约 541.8 MB）
- 本地已有模型文件：尺寸与 SHA-256 全部匹配
- 下载器行为：
  - 已完整文件直接跳过，不重写
  - 缺失/损坏文件下载到 `.part`
  - 支持 HTTP Range 断点续传
  - 网络中断保留 `.part`
  - 校验失败删除 `.part`，不触碰目标文件
  - 服务器大小不一致时拒绝写入
  - 磁盘空间不足时拒绝开始下载
  - 取消时保留进度
  - 不删除 manifest 之外的文件

## 8. 模型目录迁移回滚

- 旧配置在复制与校验成功前不会被修改。
- 旧目录只读访问，不会被破坏。
- 目标目录中已有同名文件会被拒绝覆盖。
- 复制失败或校验失败时，本轮复制出的文件会被删除，配置回滚到旧目录。
- 未执行 `git reset --hard`、`git clean` 或覆盖用户原有修改。

## 9. `indexAllClips` 失败隔离

- 单个片段失败记录到 `indexFailures` 并继续处理下一个片段。
- 已成功缓存保留，失败片段下次重试。
- 环境级失败（sidecar 缺失、FFmpeg 缺失、ONNX 缺失、模型缺失）会停止批次，避免重复相同错误。
- `FrameEmbeddingPool` 损坏缓存隔离、不可读缓存不覆盖。
- 存储失败会 surfaced，而不是静默吞掉。

## 10. 共享音量控件与四处播放器

- 四处均使用同一 `VolumeControl` 组件。
- 状态保存在各播放器页面的 `_volume`、`_isMuted`、`_volumeBeforeMute`。
- 音量通过 `Player.setVolume()` 应用。
- 静音恢复使用静音前音量。
- Widget rebuild 使用当前状态渲染，不重置音量。
- 未创建额外 Player，未改变播放器生命周期。

## 11. 人工验收覆盖状态

- Ollama/LM Studio 连接：Ollama 由现有功能支持；LM Studio 依据用户本机诊断为服务未启动/端口不可达，程序提供明确引导。未在本机 LM Studio 环境复测。
- EmbeddingGemma 校验与失败提示：自动化测试覆盖，真实下载未在本会话执行。
- 真实视频提帧与向量索引：单元测试覆盖，未执行真实视频端到端。
- 四个播放器音量调节与静音恢复：共享组件已接入，预览自动化通过；其它三个为代码接入，未人工 UI 验证。
- 自定义模型目录切换、重启保持、失败回滚：代码实现与构建通过，未人工 UI 验证。
- 原始视频与播放列表播放功能：自动化测试通过。

## 12. 未验证项目与后续风险

- 未执行真实 LM Studio/Ollama 人工连接测试（LM Studio 本机服务不可达）。
- 未执行真实 EmbeddingGemma 下载（约 542MB）与真实视频向量索引端到端。
- 未捕获 Windows 运行截图；建议在 Debug/Release 构建上手动截图放入 `docs/ui-upgrade/screenshots/`。
- 音量控件在极窄窗口（<320px）可能拥挤，建议 UI 人工检查。
- 自定义目录复制大模型（~542MB）耗时较长，UI 无进度条，仅完成后提示；失败时保留旧目录但可能留下空目录。
- `dart format` 仅作用于修改文件，未全量格式化。
- 媒体打开后播放器是否重置音量未做自动化验证，需人工确认。

## 13. 结论

AI 稳定性相关代码与测试、音量控制共享组件、自定义模型目录功能已实现并通过自动化构建与测试。LM Studio 本机不可达问题按环境问题处理并提供诊断步骤，未编造修复成功结论。当前未合并 master 或发布 Release，等待最终验收。