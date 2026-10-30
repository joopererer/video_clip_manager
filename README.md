[**简体中文**](README.md) | [English](README_EN.md)

# Video Clip Manager

> 面向桌面端的本地视频片段管理器：用毫秒级 IN/OUT 标记完成**无损软剪辑**（不转码、不改动原片），在深色媒体工作区里管理片段与播放列表，并可选用**本地 AI 模型**用自然语言检索画面。

<p align="center">
  <img alt="Version 1.1.0" src="https://img.shields.io/badge/version-1.1.0-8B7CF6">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.41+-02569B?logo=flutter&logoColor=white">
  <img alt="Dart" src="https://img.shields.io/badge/Dart-3.11+-0175C2?logo=dart&logoColor=white">
  <img alt="Platforms" src="https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-2EA44F">
  <img alt="License MIT" src="https://img.shields.io/badge/license-MIT-blue">
  <a href="https://github.com/joopererer/video_clip_manager/releases/tag/v1.1.0"><img alt="Latest release" src="https://img.shields.io/badge/release-v1.1.0-181717?logo=github&logoColor=white"></a>
</p>

## 下载

最新正式版本：[**Video Clip Manager v1.1.0**](https://github.com/joopererer/video_clip_manager/releases/tag/v1.1.0)

| 平台 | 附件 | 状态 |
| --- | --- | --- |
| **Windows x64（推荐）** | [`video_clip_manager-v1.1.0-windows-x64.zip`](https://github.com/joopererer/video_clip_manager/releases/download/v1.1.0/video_clip_manager-v1.1.0-windows-x64.zip)（约 39.6 MB） | **人工实机验证通过**的绿色便携包 |
| Windows x64（CI 构建） | `video_clip_manager-windows-x64.zip`（约 40.9 MB） | 同一提交由 GitHub Actions 构建，**未经人工测试**，文件结构与推荐包不同 |
| macOS | `video_clip_manager-macos.zip` | CI 构建，未人工测试 |
| Linux x64 | `video_clip_manager-linux-x64.tar.gz` | CI 构建，未人工测试 |

> **请优先下载带版本号的 `video_clip_manager-v1.1.0-windows-x64.zip`。** 同一个 Release 里还有一个不带版本号的 `video_clip_manager-windows-x64.zip`，它是 CI 在 GitHub Runner 上重新构建的产物：不含外层目录、二进制与本机验证过的包不一致。两者都可用 SHA-256 区分。
>
> 推荐包校验值：`SHA-256 500C9081850F2F6F5132252D74ACC0CB8301B7975E090CCC9FFB826C1B132349`（41,516,055 字节，解压后约 96.6 MB / 30 个文件）。校验命令：`Get-FileHash .\video_clip_manager-v1.1.0-windows-x64.zip -Algorithm SHA256`

## 界面预览

> 以下截图由仓库内的 `test/v1_1_visual_verification_test.dart` 使用**生产 Widget** 渲染，可本地复现，界面文字为中文。部分页面（原始视频预览、播放列表、关于）本轮未重新抓取正式截图，因此不在此展示。

**片段库 · 网格视图，搜索结果直接显示余弦相似度 `Score`**

![片段库网格视图与语义分数](docs/ui-upgrade/screenshots/v1_1/01_grid_semantic_score.png)

**片段库 · 列表视图，显示 `命中: mm:ss` HIT 时间码与 `Score`**

![片段库列表视图与 HIT 时间码](docs/ui-upgrade/screenshots/v1_1/02_list_semantic_score.png)

**输入即关键词筛选，按 `Enter` 或点击 ✨ 才发起 AI 语义检索**

![关键词筛选与 AI 触发提示](docs/ui-upgrade/screenshots/v1_1/03_keyword_hint.png)

## 核心功能（v1.1.0）

### 深色媒体工作区

- 响应式深色工作区：可折叠侧栏（208 px / 64 px）、顶栏与内容区，三个页面（片段库 / 原始视频 / 播放列表）在窄窗口下自动收拢次级功能，不挤压内容。
- 片段库支持**网格 / 列表**两种视图，卡片统一了悬停、键盘焦点、选中边框与右键菜单行为；空状态、源文件缺失、加载中都有明确落点。

### 原始视频与片段

- **原始视频管理**：统一管理本地文件、网络串流与已支持的在线媒体，表头显示片源类型、时长、分辨率（竖屏会标注 `portrait`）与片段数量。
- **独立预览**：「原始视频」页双击 / 播放按钮 / 右键「播放」打开预览对话框（播放暂停、可拖动进度条、静音、音量还原、全屏、一键「创建片段」），剪刀按钮或右键「创建片段」才进入剪辑器——两者语义彻底分开。
- **毫秒级 IN/OUT 软剪辑**：片段只是带时间范围（`inMs` / `outMs`）的元数据，**不转码、不切割、不重写原片**，保存片段不产生画质损失，也不需要等待重新编码。
- **片段管理**：网格 / 列表视图，评分、标签、收藏、搜索、筛选与排序。
- **播放列表**：把多个片段编排成播放列表，支持拖动排序、连续播放与跨片段跳转；已支持的在线 / M3U8 媒体在片段库与播放列表中都能直接打开。
- **播放控制**：播放器、剪辑器、片段播放页与原始视频预览四处都提供音量滑块与静音切换，取消静音时恢复静音前的音量而不是直接跳回 100%。

### AI 语义搜索（可选）

- **自然语言搜画面**：输入「雪山上拿着木棍」「红衣女子回眸」这类描述，即可按关键帧语义相似度召回片段。
- **HIT 时间码**：命中片段在缩略图上显示金色 `HIT` 徽章，悬停 / 列表行展示最佳命中帧时间码。
- **相似度 Score**：搜索结果直接显示真实余弦相似度（三位小数，如 `Score: 0.871`），tooltip 明确说明它**不是准确率或可信概率**。
- **相关度排序**：存在语义分数时默认按「相关度最高」排序，严格按分数降序；切换排序不会丢失 HIT 与 Score。
- **关键词筛选与 AI 检索分开**：输入框始终是实时关键词筛选，只有按 `Enter` 或点击搜索框的 ✨ 才发起 AI 语义检索；状态条与结果横幅全程显示当前模式，改词后旧的 HIT / Score 立即清除，迟到结果整体丢弃。
- **语义检索模型管理**：AI 设置内提供 EmbeddingGemma 2 模型状态（已就绪 / 未下载 / 不完整）、模型目录自定义（可复制现有模型）、一键下载与「修复 / 补全下载」（逐文件 sha256 校验，只补缺失或损坏的部分）。
- **隐私边界**：EmbeddingGemma 语义检索的向量计算与帧提取在本机完成，媒体、模型与向量数据不会被上传。若你使用自己配置的远程 VLM API（OpenAI / DashScope 兼容等），请求中会向该服务发送必要数据（如帧图像与提示词），请按所选服务的政策自行评估。

### VLM 描述（可选，需外部推理服务）

- 可接入 **Ollama**（推荐 `qwen2-vl:2b`）或**可选**的本地推理服务 **LM Studio**，也支持 OpenAI / DashScope 兼容接口，用于生成片段描述与原子标签。
- LM Studio 是独立的第三方本地推理服务，**不是本应用自带组件**；应用不会自动启动它，也不会修改其配置。

### 关于与更新

- 「关于」读取**真实打包版本**（v1.1.0 · 构建 3）、仓库地址、许可证清单与 Releases 页面，不再硬编码版本号。
- **检查更新**：读取 GitHub 最新正式 Release 并按 SemVer 比较，仅在远端版本更高时提示；失败、404、断网都只显示"无法检查"，不弹错误框，也不上传任何数据。

## 下载与安装

当前 Windows 发布物是**绿色便携 ZIP，不是安装程序**。

1. 下载并解压 `video_clip_manager-v1.1.0-windows-x64.zip`，得到单一目录 `video_clip_manager-v1.1.0-windows-x64\`。
2. 进入该目录，运行 `video_clip_manager.exe`。
3. **不要只把 EXE 单独复制出去**——它依赖同目录下的 DLL、`data/` 资源与插件，缺任何一项都起不来或无法播放。

| 包内内容 | 说明 |
| --- | --- |
| `video_clip_manager.exe` | 主程序（版本资源取自 `pubspec.yaml`） |
| `flutter_windows.dll`、`data/` | Flutter 运行时与编译后的资源，**不可缺** |
| `libmpv-2.dll`、`media_kit_*.dll` | 播放内核，删除后无法播放 |
| `onnxruntime.dll` | ONNX 推理运行时 |
| `d3dcompiler_47.dll`、`libEGL.dll`、`libGLESv2.dll`、`vk_swiftshader.dll`、`vulkan-1.dll`、`zlib.dll` | 图形 / 解压依赖 |
| `desktop_drop`、`url_launcher_windows`、`volume_controller` 等插件 DLL | 拖拽导入、外链、音量能力 |

**包内不含任何 AI 模型权重，也不含 `local-media-ai.exe` sidecar。** macOS 与 Linux 附件为 CI 构建产物，仓库维护者未做过人工测试，请自行评估后使用。

## 快速开始

1. 首次启动后，默认数据库位于 `Documents/VideoClipManager`（也可在顶栏「切换/新建数据库」中改到其他位置）。
2. 在「原始视频」页点击 **Add Videos → Add Local Video** 选择视频文件，或直接把视频文件拖进窗口导入。
3. 双击原始视频打开**预览**，用进度条找到需要的画面；点「创建片段」或剪刀按钮进入剪辑器。
4. 在剪辑器里设定 IN / OUT（毫秒级）与标题、标签、评分后保存——原片不会被改动。
5. 在片段库中筛选、评分、收藏片段，或把片段加入播放列表编排连续播放。

普通功能（视频管理、播放、软剪辑、播放列表、关键词筛选）**开箱即用**，不需要下载任何 AI 模型。

## AI 语义搜索配置（可选）

只做视频管理、播放与剪辑时，本节可以完全跳过。启用 AI 语义搜索需要三样额外组件：

| 依赖 | 用途 | 获取方式 |
| --- | --- | --- |
| **EmbeddingGemma 2** 模型（约 530 MB） | 文本与关键帧的 768 维向量 | 应用内 **设置 → AI 设置 → 语义检索模型** 一键下载；逐文件 sha256 校验，可自定义模型目录（默认在程序目录的 `models/`） |
| **`local-media-ai.exe`** sidecar | 抽帧、文本 / 图像嵌入、VLM 调用 | 本仓库**不产出该二进制**，发布包也不包含它。sidecar 来自独立的 `local-media-ai` Rust 项目，需要自行构建后放到程序同目录（或 `bin/` 子目录、系统 `PATH`） |
| **FFmpeg** | AI 抽帧（sidecar 调用）与在线媒体流合并（DASH/HLS 音视频分流） | 按 FFmpeg 官方发布的常规方式安装并确保可被找到；普通本地视频播放由随包的 media_kit（mpv）内核完成，**不**需要外部 FFmpeg |

缺少模型、sidecar 或 FFmpeg 时应用不会崩溃，AI 设置与搜索会给出明确的缺失提示与放置建议。

**关于 Ollama 与 LM Studio**：它们只用于 **VLM 描述 / 打标**这类可选推理，**不是语义向量检索的依赖**。语义搜索的向量推理由 sidecar + EmbeddingGemma 2 在本机完成，不需要启动任何外部服务。若你只想搜索画面而不需要 AI 描述，可以不安装 Ollama，也不需要 LM Studio。

## 更新方式

- 应用内：**关于 → 检查更新**。它读取 GitHub 最新正式 Release 并按 SemVer 比较，只有远端版本更高时才提示，并给出对应 Release 页面链接。
- 手动：到 [Releases](https://github.com/joopererer/video_clip_manager/releases) 下载新版本压缩包。
- **不做自我覆盖安装，也不做强制升级**——下载与安装始终由你决定。
- 升级数据安全：用户数据库 JSON Schema 在 1.0.x → 1.1.0 之间**未变**，直接沿用原数据库、缩略图与向量缓存即可。升级时用新解压的目录替换程序文件；数据库默认在 `Documents/VideoClipManager`，不受版本影响；若模型放在程序目录下的 `models/`，请保留该目录或在 AI 设置中重新指定模型目录。

## 开发构建

### 前置要求

- [Flutter SDK](https://flutter.dev) 3.41+（Dart 3.11+）
- [FFmpeg](https://ffmpeg.org)（AI 抽帧与在线音视频流合并；普通本地播放不需要，随包的 media_kit / mpv 内核自带解码能力）
- [Rust](https://rustup.rs)（可选，仅在自行构建 `local-media-ai` sidecar 时需要）

### 常用命令

```bash
flutter pub get
flutter run -d windows          # 调试运行
flutter build windows --release # 发布构建
flutter build macos --release
flutter build linux --release
flutter test                    # 461 项单元 / Widget 测试
flutter analyze
```

架构上，Flutter UI 通过 `media_kit` 播放，通过 `DeltaEngine` / `FrameEmbeddingPool` 规划关键帧增量抽帧，并把抽帧与推理交给 `local-media-ai` sidecar（JSON IPC，独立进程，推理崩溃不会拖垮 UI）：

```
┌─────────────────────────────────────────────────────────┐
│            Video Clip Manager (Flutter UI)              │
│  ClipsTab / VideosTab / PlaylistsTab / Editor / Player  │
│  AppState (Provider) · DeltaEngine · FrameEmbeddingPool │
└───────────────┬─────────────────────────┬───────────────┘
                │                         │
        ┌───────▼────────┐        ┌───────▼─────────┐
        │   media_kit    │        │  local-media-ai │
        │ 播放内核 (mpv) │        │  (Rust sidecar) │
        └────────────────┘        └───────┬─────────┘
                                          │
                        FFmpeg 抽帧 · EmbeddingGemma 2 (ONNX)
                        可选 VLM：Ollama / LM Studio / OpenAI 兼容
```

### 贡献

欢迎通过 Issue 反馈问题、通过 Pull Request 提交改进。提交前请确认 `flutter analyze` 无新增错误、`flutter test` 全绿，并保持既有行为不变量（软剪辑只存元数据、不改动原片、不改变 JSON Schema）。详细阶段报告与设计文档见 [`docs/`](docs)。

## 已知限制

1. **语义检索没有 Top-K 截断**：返回全部 `score >= 0.28` 的片段，阈值与 v1.0.x 相同，因此低相关结果也可能出现；本版只是把分数如实显示并按相关度排序。
2. **发布包不含模型与 sidecar**：纯新环境要额外准备 EmbeddingGemma 2、`local-media-ai.exe` 与 FFmpeg 才能使用 AI 画面搜索，不是"下载即用"。
3. **macOS / Linux 附件由 CI 构建**，未做人工测试，不宣称已验证通过。
4. **在线视频与刮削**依赖外部工具与网络环境，可用性随平台与网络变化。
5. **不提供视频转码 / 导出**：本应用只做时间范围标记与元数据管理，不重新编码媒体。
6. **更新检查只提示，不自动安装**；某次检查失败只显示"无法检查"，不会重试弹窗。
7. 检索相关性评估集（`docs/ui-upgrade/semantic_eval/queries.csv`）仍需在装好模型与 sidecar 的机器上补实测分数。

## FAQ

**这是安装包还是绿色版？**
绿色便携版（Portable ZIP）。没有安装程序，解压完整目录后运行 `video_clip_manager.exe` 即可；删除目录即卸载，用户数据存放在 `Documents/VideoClipManager`。

**AI 模型是必须下载的吗？**
不是。视频管理、播放、软剪辑、播放列表与关键词筛选都不需要模型。只有 AI 语义搜索需要 EmbeddingGemma 2（外加 sidecar 与 FFmpeg），VLM 描述还需要你自己准备 Ollama 或 LM Studio 之类的推理服务。

**输入搜索词和按 Enter 有什么区别？**
输入时是**实时关键词筛选**（不计算向量）。只有按 `Enter` 或点击搜索框的 ✨ 才发起 **AI 语义检索**，结果才会带 `HIT` 时间码与 `Score`；状态条和结果横幅会显示当前处于哪种模式。

**如何升级到新版本？**
在「关于 → 检查更新」里看是否有新版本，或直接到 Releases 下载新包；解压替换程序目录即可，数据库（`Documents/VideoClipManager`）与既有 JSON Schema 无需迁移。若模型放在程序目录的 `models/`，记得保留。

**支持 macOS / Linux 吗？**
仓库通过 CI 为 macOS 与 Linux 提供构建产物，但**只有 Windows x64 版本经过人工实机验证**。macOS / Linux 请自行测试后使用。

## 版本历史

v1.1.0 主要变化：深色媒体工作区整窗重构、原始视频独立预览、播放列表编排与连播、四处播放器音量滑块、AI 搜索真实 Score 与相关度排序、关键词筛选与 AI 检索分离、语义检索模型下载 / 校验 / 目录管理、关于页动态版本与检查更新。

- 完整历史（含 v1.0.1）：[`docs/CHANGELOG.md`](docs/CHANGELOG.md)
- v1.1.0 发布说明：[`docs/ui-upgrade/V1_1_RELEASE_NOTES.md`](docs/ui-upgrade/V1_1_RELEASE_NOTES.md) ｜ [GitHub Release](https://github.com/joopererer/video_clip_manager/releases/tag/v1.1.0)
- v1.1.0 发布与验证记录：[`docs/ui-upgrade/V1_1_RELEASE_FINAL.md`](docs/ui-upgrade/V1_1_RELEASE_FINAL.md)

## 许可证

本项目采用 [MIT License](LICENSE) 开源许可。
