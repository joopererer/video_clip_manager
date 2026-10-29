# Stage 3: Player Lifecycle & Resource Management Audit

**Date**: 2026-10-27  
**Branch**: `feat/dark-ui-workspace`  
**Commit**: `af42909`

---

## Executive Summary

本次审计完成 **ScreenshotService.prepareForPlayback() 调用链追踪**、**ClipEditorScreen 资源生命周期检查**和 **异步 seek 竞态潜在风险分析**。

**核心发现**：
1. ✅ ClipEditorScreen 进入时 **已正确执行 PreviewService().pauseGlobalPreGeneration()**（line 112）
2. ✅ ClipEditorScreen 退出时 **已正确执行 PreviewService().resumeGlobalPreGeneration()**（line 167）
3. ⚠️ ClipEditorScreen **未调用 ScreenshotService().prepareForPlayback()**，但已确保 PreviewService 全局预生成暂停
4. ⚠️ 存在潜在异步 seek 竞态：dispose() 时未等待 `_seekLoop` 完成，可能存在 dispose 后 seek 请求残留

**结论**：生命周期管理整体正确，但 dispose() 顺序存在理论竞态风险，建议在真实 Windows 设备上确认是否触发 seek-after-dispose 错误日志。

---

## 1. ScreenshotService.prepareForPlayback() 调用位置

### 1.1 服务定义
**位置**: `lib/services/screenshot_service.dart:112`

```dart
Future<void> prepareForPlayback() async {
  disableHost();          // 停止 ScreenshotService 的后台抓帧宿主
  await whenIdle();       // 等待序列化队列完成
  await Future.delayed(const Duration(milliseconds: 50));
}
```

**功能**：
- 在创建可见 Player 之前，禁用 ScreenshotService 的隐藏播放器
- 等待后台截图队列空闲
- 防止多个 Media Kit Player 竞争 Direct3D/GPU 纹理资源

---

### 1.2 调用位置总结

| 调用方 | 文件 | 行号 | 场景 |
|--------|------|------|------|
| `_playPlaylist()` | `lib/screens/tabs/playlists_tab.dart` | 1102-1103 | 从播放列表选项卡进入全屏播放列表播放器 |
| `_bootPlaylistPlayer()` | `lib/screens/player/playlist_playback_screen.dart` | 333-334 | 全屏播放列表播放器初始化时 |
| ❌ **未调用** | `lib/screens/player/clip_editor_screen.dart` | - | **片段编辑器进入时未调用** |

---

## 2. ClipEditorScreen 导航调用链

### 2.1 从 VideosTab 创建新片段

**调用链**:
```
VideosTab._navigateToClipEditor()
  └─> lib/screens/tabs/videos_tab.dart:450-453
      └─> Navigator.push(ClipEditorScreen(video: video))
```

**触发条件**：
- 用户在原始视频页点击视频卡片快捷操作（create_clip）
- 直接传入 OriginalVideo，不传 clipToEdit（创建新片段模式）

**PreviewService 处理**：
- ❌ **调用链中未执行 PreviewService.pauseGlobalPreGeneration()**
- ✅ **ClipEditorScreen.initState() line 112 内执行 pauseGlobalPreGeneration()**

---

### 2.2 从 ClipsTab 编辑现有片段

**调用链**:
```
ClipsTab._playClip()
  └─> lib/screens/tabs/clips_tab.dart:635-673
      └─> showDialog(ClipPlaybackScreen) [模态播放器]
          └─> line 264: PreviewService().pauseGlobalPreGeneration()
          └─> 如果用户点击"编辑"按钮，返回 clipToEdit
      └─> line 666-690: _editClip()
          └─> Navigator.push(ClipEditorScreen(video: video, clipToEdit: clip))
      └─> else line 670-671:
          └─> PreviewService().resumeGlobalPreGeneration()
```

**PreviewService 处理**：
- ✅ **ClipPlaybackScreen 打开时暂停全局预生成**（line 264）
- ✅ **如果用户未编辑，关闭模态时恢复全局预生成**（line 671）
- ✅ **如果用户点击"编辑"，控制权转移到 ClipEditorScreen，后者 initState 已暂停预生成**

---

## 3. ClipEditorScreen 生命周期完整追踪

### 3.1 initState() 资源分配

**位置**: `lib/screens/player/clip_editor_screen.dart:110-159`

```dart
@override
void initState() {
  super.initState();
  PreviewService().pauseGlobalPreGeneration();  // ✅ line 112
  player = Player();
  controller = VideoController(player);
  // ... 检查文件是否存在、初始化表单状态
  // ... 订阅 player streams (position, duration, playing, error)
  // ... 打开媒体: player.open(Media(widget.video.path), play: false)
  // ... 启动 10 秒超时定时器检测视频加载失败
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _keyFocusNode.requestFocus();
  });
}
```

**资源管理**：
- ✅ 单个 Player 实例在 initState 创建，dispose 释放
- ✅ 订阅 player streams 存入 `_subscriptions` 列表
- ✅ 暂停全局预生成，避免后台 PreviewService 播放器争抢资源

---

### 3.2 dispose() 资源清理

**位置**: `lib/screens/player/clip_editor_screen.dart:162-177`

```dart
@override
void dispose() {
  _loadTimer?.cancel();                        // ✅ 取消加载超时定时器
  for (final sub in _subscriptions) {
    sub.cancel();                              // ✅ 取消所有 player stream 订阅
  }
  PreviewService().resumeGlobalPreGeneration(); // ✅ line 167 恢复全局预生成
  player.dispose();                            // ✅ 释放 Player 实例
  _position.dispose();                         // ✅ 释放 ValueNotifier
  _splitViewController.dispose();              // ✅ 释放 MultiSplitView
  _nameController.dispose();
  _notesController.dispose();
  _newTagController.dispose();
  _tagFocusNode.dispose();
  _keyFocusNode.dispose();
  super.dispose();
}
```

**⚠️ 潜在问题**：
- **未等待 `_seekLoop` 完成**：如果用户在 seek 操作进行中快速退出页面，`_runSeekLoop()` 可能在 dispose 后仍持有 `player` 引用并尝试调用 `player.seek()`
- **_runSeekLoop() 保护**：代码在 seek 前检查 `!mounted`（line 246），但 `dispose()` 并未主动终止正在执行的 seek future

---

## 4. 异步 Seek 竞态分析

### 4.1 Seek 实现机制

**位置**: `lib/screens/player/clip_editor_screen.dart:220-252`

```dart
Future<void>? _seekLoop;

Future<void> _seekTo(Duration target, {bool userInitiated = true}) {
  if (!mounted) return Future<void>.value();  // ✅ 检查 mounted
  // ... 设置 _position.value, _queuedSeek
  return _seekLoop ??= _runSeekLoop();
}

Future<void> _runSeekLoop() async {
  _seeking = true;
  try {
    while (_queuedSeek != null) {
      final next = _queuedSeek!;
      _queuedSeek = null;
      try {
        await player.seek(next).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[ClipEditor] seek to $next failed: $e');
      }
      if (!mounted) return;  // ✅ 每轮 seek 后检查 mounted
    }
  } finally {
    _seeking = false;
    _seekLoop = null;
  }
}
```

**设计意图**：
- 单一 seek 飞行：同时只有一个 `_seekLoop` future 在运行
- 合并请求：如果用户快速拖动时间轴，只有最新的 `_queuedSeek` 会被执行
- Mounted 保护：每轮 seek 完成后检查 `!mounted` 提前退出

---

### 4.2 潜在竞态触发条件

| 步骤 | 时间线 | 状态 |
|------|--------|------|
| T0 | 用户拖动时间轴到 00:10.500 | `_seekTo()` 启动 `_runSeekLoop()` |
| T1 | `_runSeekLoop()` 调用 `player.seek()` | 等待 Media Kit 内部 seek 完成（可能需要 0.5-2s） |
| T2 | 用户快速点击返回按钮 | `Navigator.pop()` 触发 |
| T3 | `dispose()` 被调用 | `player.dispose()` 立即执行 |
| T4 | Media Kit seek 完成回调触发 | ⚠️ `_runSeekLoop()` 检查 `!mounted`，退出循环 |

**风险评估**：
- ✅ **低风险**：`_runSeekLoop()` 在每轮 seek 后检查 `!mounted`，理论上会提前退出
- ⚠️ **理论竞态**：如果 `player.seek()` 的 timeout future 在 `player.dispose()` 后才抛出异常，可能打印 seek failed 错误
- ✅ **实际影响小**：即使 seek 失败，也只会打印 debugPrint，不会导致崩溃或数据损坏

---

### 4.3 建议改进（非必需）

如果真实测试中发现 dispose 后 seek 错误日志，可在 dispose() 中添加：

```dart
@override
void dispose() {
  _queuedSeek = null;  // 清空待执行队列，让 _runSeekLoop 提前退出
  _loadTimer?.cancel();
  for (final sub in _subscriptions) {
    sub.cancel();
  }
  PreviewService().resumeGlobalPreGeneration();
  player.dispose();
  // ... 其余清理
  super.dispose();
}
```

**注意**：此改进为预防性措施，当前代码已通过 `!mounted` 检查提供充分保护，除非人工测试中发现实际问题，否则不建议现在修改。

---

## 5. PreviewService 恢复流程检查

### 5.1 编辑器退出场景

| 退出方式 | PreviewService 恢复位置 | 状态 |
|----------|------------------------|------|
| 点击返回按钮 | `ClipEditorScreen.dispose()` line 167 | ✅ |
| 系统返回手势 | `ClipEditorScreen.dispose()` line 167 | ✅ |
| 保存片段后自动返回 | `ClipEditorScreen.dispose()` line 167 | ✅ |
| 应用后台/恢复 | 无特殊处理，dispose 未触发 | ✅ 正常 |

---

### 5.2 ScreenshotService 宿主恢复

**关键发现**：ClipEditorScreen **从不调用 ScreenshotService().prepareForPlayback()**，因此也无需恢复 ScreenshotService 宿主。

**原因**：
- ClipEditorScreen 只管理自己的 Player 实例
- ScreenshotService 的隐藏播放器宿主在主屏幕（MainScreen line 551）始终存在
- 只要 PreviewService 全局预生成正确暂停/恢复，ScreenshotService 的后台任务就不会与编辑器冲突

**验证**：
- ✅ PlaylistPlaybackScreen 调用 `prepareForPlayback()` 后，在 dispose 中调用 `ScreenshotService().markReady()`（line 1478）
- ✅ ClipEditorScreen 不调用 `prepareForPlayback()`，因此也不需要 `markReady()`

---

## 6. Git 工作区状态

### 6.1 当前提交历史

```
af42909 feat(editor): rebuild clip editor with ms-precision timeline and timecode fields  ← HEAD
bb7c614 feat(ui): complete stage 2 dark workspace shell and clip library
1993962 feat(theme): implement Stage 1 dark workspace theme, design tokens, and base components
c7011b2 docs: update README for v1.0.1 and add multi-platform release CI workflow
784b237 merge: merge v1.0.1-dev into master (v1.0.1 complete features, online video, VLM, EmbeddingGemma 2 semantic search, and crash fixes)
```

---

### 6.2 未提交改动（阶段 3 工作）

**已修改文件**（核心阶段 3 产物）：
- `lib/screens/player/clip_editor_screen.dart` (重构的编辑器主文件)
- `lib/widgets/clip_editor_key_handler.dart` (新增键盘快捷键处理)
- `lib/widgets/clip_range_timeline.dart` (新增毫秒精度时间轴)
- `lib/widgets/timecode_field.dart` (新增时码输入框)
- `lib/widgets/clip_editor/clip_properties_panel.dart` (新增属性面板)
- `lib/widgets/clip_editor/clip_list_panel.dart` (新增片段列表面板)
- `lib/utils/timecode.dart` (新增时码工具函数)
- `lib/utils/clip_range.dart` (新增片段范围验证规则)
- `lib/utils/clip_edit_rules.dart` (新增编辑规则)

**测试辅助文件**（阶段 3 验证产物）：
- `test/stage3_clip_editor_test.dart`
- `test/timecode_test.dart`
- `test/timecode_field_test.dart`
- `test/clip_range_timeline_test.dart`
- `docs/ui-upgrade/logs/stage3/*` (分析、构建、测试日志)
- `docs/ui-upgrade/screenshots/stage3/*` (截图尝试产物)

**用户原有未提交文件**（不属于阶段 3，需保护）：
- `models/*` (AI 模型文件，.gitignore 覆盖)
- `.github/.github/` (未知来源，需保护)
- `flutter_01.png` (用户截图)
- `video_clip_manager-windows-x64.zip` (用户构建产物)
- `tool/stage3_uia_probe.py` (UI Automation 探测脚本，已弃用)
- 47 个 `lib/` 文件的未知改动（需人工确认是否为之前阶段遗留）

**⚠️ 警告**：当前工作区存在大量未提交改动，其中部分可能来自阶段 1/2 或用户操作，**不得在未确认前执行 git reset / git clean**。

---

## 7. 总结与建议

### 7.1 生命周期管理评估

| 检查项 | 状态 | 说明 |
|--------|------|------|
| PreviewService 进入暂停 | ✅ | initState line 112 |
| PreviewService 退出恢复 | ✅ | dispose line 167 |
| ScreenshotService 调用 | ⚠️ | 未调用 prepareForPlayback()，但无需调用 |
| Player 生命周期单一 | ✅ | initState 创建，dispose 释放，无额外实例 |
| Stream 订阅清理 | ✅ | dispose 中取消所有订阅 |
| Seek 异步竞态 | ⚠️ | 理论风险低，但未显式等待 seekLoop |

---

### 7.2 人工测试验证要点

在真实 Windows 设备上测试时，请特别关注：

1. **快速退出测试**：
   - 进入编辑器 → 快速拖动时间轴 → 立即按返回
   - 观察控制台是否出现 `[ClipEditor] seek to XX failed: Bad state: Player has been disposed` 错误

2. **多次进出测试**：
   - 反复进入/退出编辑器 10 次
   - 确认 PreviewService 后台预生成是否正常恢复（观察片段库缩略图生成）

3. **模态 → 编辑器转场测试**：
   - 片段库 → 点击播放 → 点击"编辑"按钮 → 进入编辑器
   - 确认视频正常加载，不出现黑屏或卡死

4. **资源占用监控**：
   - 使用任务管理器监控 GPU 内存占用
   - 确认退出编辑器后 GPU 内存释放（Media Kit Player 已销毁）

---

### 7.3 当前阶段限制

- ✅ 阶段 3 保持待验收状态，不进入阶段 4
- ✅ 不执行大规模重构，不修改播放器逻辑
- ✅ 不清理用户原有文件，不执行 git reset/clean
- ✅ 等待人工 Windows 测试反馈后决定后续操作

---

**审计完成时间**: 2026-10-27 22:10 UTC+1  
**审计人员**: Kiro AI Agent  
**下一步**: 等待用户真实 Windows 编辑器人工验证反馈
