# 阶段 2：主窗口 Shell 与片段库

## 基线与范围

- 分支：`feat/dark-ui-workspace`；恢复任务时以 `git status`、`git log` 确认 HEAD 为已审核的 `1993962`。
- 延续 `CODEBASE_AUDIT.md` 的阶段 2 计划及中断前的未提交初稿；没有替换 `lib/main.dart`，没有开始阶段 3。
- 原有未提交模型文件、压缩包、`.github/.github/`、`flutter_01.png` 和阶段 1 截图不纳入本次提交。

## 实现

| 文件 | 改动 |
| --- | --- |
| `lib/screens/main_screen.dart` | 响应式 Shell；208/64px 侧栏、60px 顶栏、可伸缩内容区；三页导航、搜索/AI 搜索、数据库、设置、导入与拖拽入口；保留离屏 Video 宿主。 |
| `lib/screens/tabs/clips_tab.dart` | 响应式网格和列表、筛选/排序/计数/收藏快捷筛选、空状态导航；复用原来的 AppState 过滤、保存与播放器调用。 |
| `lib/widgets/common/app_sidebar.dart` | 可折叠导航、数据库状态、设置入口及工具提示；窄屏自动折叠。 |
| `lib/widgets/common/app_header.dart` | 全局搜索与 AI 状态；窄屏将次级全局功能收进菜单；长状态文本截断。 |
| `lib/widgets/clip_card.dart` | 16:9 媒体框、来源、时长、标签、评分/收藏；Hover/焦点操作与右键菜单；选中边框。 |
| `lib/widgets/clip_list_row.dart` | 完整列表行、范围/来源/标签/评分/收藏及操作入口；Hover/焦点/选中状态。 |
| `lib/widgets/clip_media_preview.dart` | 异步源文件存在性提示；复用 ClipThumbnail，以 contain 保留竖屏内容。 |
| `lib/widgets/clip_thumbnail.dart` | 仅增加可选背景色及格式化；供片段库使用深色留边，默认行为保持不变。 |
| `test/stage2_visual_verification_test.dart` | 示例数据 Widget 布局与交互测试、缺失文件状态、真实 AppState 保存验证；明确使用无原生 Video 宿主的测试 Shell。 |
| `test/fixtures/stage2_desktop_fixture.dart` | 原生 Windows 截图验证入口：调用生产 main，使用真实服务和独立示例库；仅偏好设置采用内存存储。 |
| `tool/stage2_desktop_capture.py` | 生成 FFmpeg 测试图视频并捕获原生窗口客户区；记录尺寸及 DPI。使用环境已有的 Python/Pillow/pywin32/FFmpeg，未新增应用依赖。 |

修复了中断初稿中的搜索重置遗漏、空状态按钮不导航、双击监听延迟单击、长标签布局、竖屏浅色留边及侧栏宽度动画期间的布局风险。单击片段继续打开播放器；右键菜单选中片段，不增加批量操作或多选业务。

## 行为边界

- 与基线逐文件比较确认：`lib/main.dart`、`AppState`、数据模型、ScreenshotService、PreviewService、ThumbnailService、`pubspec.yaml` 和 `pubspec.lock` 未变。
- 软剪切仍只保存元数据；JSON schema、毫秒时间单位、筛选/排序比较规则、Provider 架构与播放器页面实现未变。
- 保留 `Positioned(left: -2, top: -2, width: 1, height: 1)` 下的 ScreenshotService Video 宿主，以及原有预生成启动/停止和播放返回后的恢复调用。
- Hover 使用原有关键帧缓存预览，不创建卡片专属 Player，不增加 seek/截图并行任务。
- 评分与收藏仍调用 `AppState.updateClip`，UI 即时更新并沿用原有保存调度；新增测试核验写入 JSON 的结果。
- 删除片段有确认弹窗，说明只删除元数据；源视频不删除。播放列表管理/播放器的事务编辑实现未改动。

## 检查与日志

最终结果见 [命令记录](logs/stage2/command-results.json)。完整分析日志保留历史问题，不以 `--no-fatal-warnings` 掩盖退出状态。

| 检查 | 结果 |
| --- | --- |
| Flutter / Dart | Flutter 3.41.7，Dart 3.11.5；见 `logs/stage2/flutter-version.txt`。 |
| `dart format`（仅本阶段 Dart 文件） | exit 0；10 个 Dart 文件已格式化，最终检查 0 个文件需要改动。 |
| `flutter pub get` | exit 0；依赖锁文件未变。 |
| `flutter analyze` | exit 1；0 error / 97 warning / 1268 info；基线 0 / 98 / 1268，无新增诊断，移除 1 条未使用局部变量警告。 |
| `flutter test` | exit 0；30/30 通过（其中阶段 2 新增 6 项）；见 `test-final.txt`。 |
| `flutter build windows --debug` | exit 0；生产入口构建成功（11.6s），产物 `build/windows/x64/runner/Debug/video_clip_manager.exe`；见 `build-windows-final.txt`。 |
| Windows 原生运行 | 已实际运行独立示例库，取得要求的七张客户区截图；与 Widget 截图分开存放。 |

环境说明：最终复核期间 C 盘仅余约 66 MiB，测试编译器曾报 `errno = 112`（临时磁盘空间不足）。该失败保存在 `test-disk-full.txt`，不算通过。最后一次全量测试和生产构建仅为各自进程设置 `TEMP`/`TMP` 为项目下的 `build/stage2_tmp` 后成功；没有更改系统全局环境变量，也没有删除用户文件。

阶段 1 对照分析：将 `1993962` 的全部受版本控制 Dart 源文件、pubspec、锁文件及分析配置复制到临时目录，使用同一个 SDK/包配置运行 `flutter analyze --no-pub`。比较时按严重级别、消息、文件、规则进行多重集比较，忽略因 UI 改动移动的行列号。详细结果见 [诊断差异](logs/stage2/analysis-comparison.json) 和两份完整分析日志。

## 截图

以下为 **真实 Windows 桌面运行截图**，使用生产 MainScreen/页面/Media Kit，客户区为标注的像素大小，DPI=96。所有彩条视频、片段与播放列表均为 **生成的示例素材/占位数据**。截图入口的内存偏好设置不会覆盖用户原来的数据库选择。

| 场景 | 截图 |
| --- | --- |
| 网格，1280×800 | [原生网格](screenshots/stage2/windows/01_clips_grid_1280x800.png) |
| 列表，1280×800 | [原生列表](screenshots/stage2/windows/02_clips_list_1280x800.png) |
| 窄屏折叠侧栏，900×700 | [原生窄屏](screenshots/stage2/windows/03_narrow_collapsed_900x700.png) |
| 卡片 Hover | [原生 Hover](screenshots/stage2/windows/04_card_hover_1280x800.png) |
| 搜索与收藏筛选 | [原生筛选](screenshots/stage2/windows/05_search_and_favorite_filter_1280x800.png) |
| 原始视频导航 | [原生原始视频页](screenshots/stage2/windows/06_original_videos_navigation_1280x800.png) |
| 播放列表导航 | [原生播放列表页](screenshots/stage2/windows/07_playlists_navigation_1280x800.png) |

`screenshots/stage2/widget/` 是 **Widget Test 截图**，使用假的缩略图服务、示例元数据和组件测试 Shell，不代表原生播放器集成测试。阶段中断时留下的 `screenshots/stage2/` 根目录旧图片不作为本次验收证据。

复现原生截图：

```powershell
rtk proxy python tool/stage2_desktop_capture.py fixture
rtk proxy flutter build windows --debug -t test/fixtures/stage2_desktop_fixture.dart
rtk proxy python tool/stage2_desktop_capture.py launch
rtk proxy python tool/stage2_desktop_capture.py capture example 1280 800
# click / hover 使用客户区坐标；capture 只捕获应用客户区。
rtk proxy python tool/stage2_desktop_capture.py close
rtk proxy flutter build windows --debug
```

## 未解决事项与验证限制

- 仓库仍有 97 条 warning、1268 条 info；分析退出码为 1，不是零警告。C 盘空间不足也尚未替用户清理，本次验证已使用 D 盘临时目录。
- 原始视频与播放列表页的内部旧样式保留，尤其播放列表顶部仍有浅色区域；本阶段验证其导航可达，播放列表内部重构留待后续批准。
- AI 语义模型实际推理、在线平台/爬虫的网络端到端任务以及操作系统文件拖拽导入尚未做完整集成回归；相关入口和业务调用已保留，不能把入口检查称作这些业务全部通过。
- 缺失文件状态在媒体框挂载或源路径变化时检查；外部恢复同一路径文件后可通过切换网格/列表刷新状态。
- 没有开展阶段 3 的编辑器改造或新的时间语义/播放器实现。

阶段 2 独立提交完成后等待用户验收。
