# Video Clip Manager

<p align="center">
  <img src="https://img.shields.io/badge/version-1.1.0-blue.svg?cacheSeconds=2592000" />
  <img src="https://img.shields.io/badge/Flutter-3.41+-02569B?logo=flutter" />
  <img src="https://img.shields.io/badge/Dart-3.11+-0175C2?logo=dart" />
  <img src="https://img.shields.io/badge/AI-EmbeddingGemma%202-8E24AA" />
  <img src="https://img.shields.io/badge/VLM-Qwen2--VL-00ACC1" />
  <img src="https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-success" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg" />
</p>

**Video Clip Manager** 是一个基于 Flutter 开发的跨平台现代化视频片段管理与多模态 AI 智能检索工具。它专注于**“无损软截取”**（Soft Clipping）、**AI 视觉大模型剧情解构**、**768维自然语言画面秒搜**与**专业级智能收藏管理**。

---

## 🌟 核心理念与设计原则

1. **无损软截取 (Soft Clipping)**
   - **时间标记虚拟截取**：通过精确到毫秒的时间戳标记片段起点与终点，原始视频文件零重写、零画质损失。
   - **极速创建**：免去繁重的视频重新编码与重渲染等待，秒级生成片段卡片。
2. **多模态 AI 深度赋能 (Local-First Multimodal AI)**
   - **语义画面秒搜**：无需繁琐人工打标，输入“雪山上拿着木棍”、“红衣女子回眸”，即可基于关键帧视觉特征毫秒级召回对应片段。
   - **HIT 最佳帧悬停高亮 (Hit Keyframe Scrubbing)**：搜索命中直接在缩略图展示金色 `HIT` 徽章，光标悬停即时滑至最匹配瞬间。
   - **视觉大模型 (VLM) 自动打标**：一键调用 Qwen2-VL 视觉大模型，自动生成场景类型、核心主体、剧情浓缩摘要与 DAM 规范原子标签。
3. **全链路在线与本地视频整合**
   - **多平台在线直接解析**：支持 YouTube、Bilibili、MissAV、XVideos 在线视频直接播放、截取片段与画质切换。
   - **智能元数据与封面刮削**：多源检索（JavDB、JavBus、JavLibrary、TMDB）自动补全番号、简介与高清海报封面。
4. **专业播放列表与时间轴**
   - **片段自由编排**：将多个片段串联成播放列表无缝连播。
   - **可视化轨道时间轴**：直观展示片段在时间轴中的分布与拖拽排序。

---

## 🚀 核心功能特性

### 1. 🔍 多模态语义搜索与增量特征库
- **EmbeddingGemma 2 ONNX 本地推理**：将查询文本与视频关键帧映射到同一 768 维语义空间，离线运行、隐私完全自主可控。
- **DeltaEngine 增量差集抽帧规划**：剪辑保存或搜索时自动增量抽帧并存入母视频磁盘缓存池，100% 缓存命中时零额外计算。
- **HIT 徽章与悬停穿梭**：命中片段高亮展示相似度，鼠标在缩略图滑动时实时定位到最高相似度关键帧。
- **特征向量库一键管理**：AI 设置面板提供一键下载全套模型与一键批量构建所有片段特征向量，实时显示处理进度条。

### 2. 🤖 视觉大模型 (VLM) 智能剧情解析
- **支持多种推理后端**：
  - **Ollama 本地模式**：推荐配置 `qwen2-vl:2b`，开箱即用；
  - **内置 llama-server**：支持 GGUF 权重与多模态投影（mmproj）；
  - **OpenAI / DashScope 兼容接口**：支持接入各类兼容 API。
- **DAM 规范原子标签提取**：自动拆分短语并过滤无意义停用词，保证标签精炼规范。

### 3. 🌐 在线视频全能工作流
- **无缝流媒体解析**：支持多分辨率、多码率音视频流智能重组与播放。
- **外部刮削器支持**：内置 `yt-dlp` 与 Cloudflare 绕过机制，稳定获取标题、标签、缩略图与视频流。
- **多数据源智能回退**：优先级调度多数据库，确保海报与元数据获取成功率。

### 4. 🎬 播放器与片段编辑器
- **双播放器毫秒级微调**：主播放器 + 辅助微调播放器，支持 100ms / 1s / 5s 步进控制。
- **自定义封面选择**：可将任意时刻关键帧提取并设为封面。
- **底层稳定性保障**：升级 `media_kit: 1.2.6`，重构 Windows Direct3D 纹理与播放器销毁时序，消除资源竞态崩溃。

---

## 🛠️ 技术架构

```
┌────────────────────────────────────────────────────────┐
│              Video Clip Manager (Flutter UI)           │
│  - ClipsTab / VideosTab / PlaylistsTab / EditorScreen  │
│  - AppState (Provider 状态管理)                         │
└───────────────┬────────────────────────┬───────────────┘
                │                        │
       ┌────────▼────────┐      ┌────────▼────────┐
       │   Media Kit     │      │   DeltaEngine   │
       │ (Direct3D 视频) │      │  (增量差集规划) │
       └─────────────────┘      └────────┬────────┘
                                         │
 ┌───────────────────────────────────────▼───────────────┐
 │       local-media-ai (Rust CLI Sidecar IPC)           │
 │  - extract-clip: FFmpeg 精确/场景增量抽帧               │
 │  - embed-text / embed-frames: EmbeddingGemma 2 ONNX   │
 │  - caption: Qwen2-VL 结构化剧情解析与标签提取         │
 └───────────────────────────────────────────────────────┘
```

---

## 📦 跨平台 Release 构建与发布

本仓库通过 GitHub Actions 自动化矩阵为三大桌面平台提供原生发布包：
- **Windows**: `video_clip_manager-windows-x64.zip`
- **macOS**: `video_clip_manager-macos.zip`
- **Linux**: `video_clip_manager-linux-x64.tar.gz`

### 本地编译运行指南

#### 前置要求
- [Flutter SDK](https://flutter.dev) (>= 3.32)
- [Rust](https://rustup.rs) (用于编译 local-media-ai sidecar，可选)
- [FFmpeg](https://ffmpeg.org)

#### 运行与构建命令
```bash
# 获取依赖
flutter pub get

# 运行调试版本 (以 Windows 为例)
flutter run -d windows

# 构建各平台正式发布版本
flutter build windows --release
flutter build macos --release
flutter build linux --release
```

### Windows 发布包内容与首次运行

发布包是一个完整目录（不是单个 EXE），解压后直接运行 `video_clip_manager.exe`：

| 内容 | 说明 |
| --- | --- |
| `video_clip_manager.exe` | 主程序（版本资源 = `pubspec.yaml` 的版本号） |
| `flutter_windows.dll`、`data/` | Flutter 运行时与已编译资源，**不可缺** |
| `libmpv-2.dll`、`media_kit_*_plugin.dll` | 播放内核，删除后无法播放 |
| `onnxruntime.dll` | 向量推理运行时 |
| `d3dcompiler_47.dll`、`libEGL.dll`、`libGLESv2.dll`、`vk_swiftshader.dll`、`vulkan-1.dll`、`zlib.dll` | 图形与解压依赖 |
| 插件 DLL（`desktop_drop`、`url_launcher_windows`、`volume_controller` 等） | 拖拽、外链、音量等能力 |

**包内不包含任何 AI 模型权重。** 因此：

- 视频管理、播放、片段截取、播放列表、关键词筛选开箱即用；
- 「AI 语义搜索」需要 EmbeddingGemma 2（约 530MB），在 **设置 → AI 设置 → 语义检索模型** 里点「一键下载」或「修复 / 补全下载」，模型默认落在程序目录下的 `models/`（也可自定义目录）；
- 帧提取与推理还需要独立的 `local-media-ai.exe` sidecar（放在程序同目录或系统 `PATH` 中）以及 FFmpeg。缺少时应用不会崩溃，而是给出明确的缺失提示与处理建议。

---

## 📝 版本更新历史 (Changelog)

### v1.1.0 (当前版本)
- **界面与交互**：
  - 🎨 深色工作区全面落地：响应式 Shell（可折叠侧栏 + 顶栏 + 三页导航）、网格 / 列表两种片段视图、统一的卡片悬停 / 焦点 / 右键交互；
  - 🎬 「原始视频」双击 / 播放按钮直接打开**原始视频预览**（不再误入剪辑器），支持播放暂停、进度条、静音还原、全屏与「创建片段」；
  - 📚 播放列表工作台：可编排、连播与跨片段跳转，M3U8 在线源在片段库与播放列表中都可用；
  - 🔊 播放器与剪辑器新增音量滑杆与静音切换（取消静音时恢复原音量）。
- **AI 语义搜索**：
  - 🎯 搜索结果直接显示**真实余弦相似度 Score**（三位小数，明确标注"不是准确率"），并新增「相关度最高」排序，存在语义分数时默认启用；
  - ⚡ 明确区分「关键词筛选」与「AI 语义搜索」：输入即筛选，按 `Enter` 或点击搜索框 ✨ 才执行 AI 检索，状态条与结果横幅全程可见；
  - 🧹 修改搜索词后旧 HIT 与 Score 立即清除，迟到的请求结果整体丢弃，不再出现新旧混排；
  - 🛠️ AI 设置新增「语义检索模型 (EmbeddingGemma 2)」区块：模型状态（已就绪 / 未下载 / 不完整）、模型目录切换（可复制既有模型）、一键下载与「修复 / 补全下载」（sha256 校验，只补缺失或损坏的文件）。
- **关于与更新**：
  - ℹ️ 「关于」显示真实打包版本（v1.1.0 · 构建 3）、仓库地址、许可证入口与 Releases 页面，不再硬编码版本号；
  - 🔄 新增非侵入式「检查更新」：读取 GitHub 最新正式 Release 并按 SemVer 比较，仅在远端版本更高时提示，失败完全静默、不阻塞启动、不上传任何数据；
  - 🏷️ 版本链路统一为 `pubspec.yaml` → Windows 版本资源，EXE 属性与「关于」不会各写一套。
- **工程与文档**：
  - ✅ 测试从 398 项增加到 461 项（新增搜索状态、Score 展示、检索质量、更新检查、版本一致性、关于对话框、无模型指引等）；
  - 📄 补充 `LICENSE`（MIT），新增语义检索质量审计与评估集、Logo 候选、发布准备与验收报告。

### v1.0.1
- **新特性**：
  - ✨ 接入 EmbeddingGemma 2 多模态 768 维图文语义向量检索，支持自然语言画面秒搜；
  - 🎯 实现最佳匹配关键帧悬停高亮（Hit Keyframe Scrubbing）与金色 HIT 徽章；
  - 🤖 集成 Qwen2-VL 视觉大模型剧情解析，支持场景、主体与原子关键词自动生成；
  - 🌐 在线视频全链路支持（YouTube、Bilibili、MissAV、XVideos）与画质自适应切换；
  - 📊 AI 设置面板新增模型一键下载与片段语义向量库一键批量增量构建进度展示。
- **稳定性修复**：
  - 🛡️ 升级 `media_kit: 1.2.6`，修复 Windows 平台 Direct3D 纹理释放与回调虚拟机奔溃；
  - 🔇 消除在线视频流静默轮询日志对控制台的频繁占用。

---

## 📄 许可证 (License)

本项目采用 [MIT License](LICENSE) 开源许可。
