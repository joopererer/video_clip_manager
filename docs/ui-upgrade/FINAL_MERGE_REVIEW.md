# Final Merge Review

分支：`feat/dark-ui-workspace`  
目标分支：`master`  
状态：审查完成，未执行合并、推送、Release 或 destructive Git 操作。

## 1. Git 状态

- 当前分支：`feat/dark-ui-workspace`
- 工作区：干净
- 相对 `origin/feat/dark-ui-workspace`：领先 29 个提交
- 合并基点：`c7011b2`（v1.0.1 merge）

## 2. 阶段与 AI 稳定性提交覆盖

当前分支包含 Stage 1–5、AI 稳定性、播放器音量、自定义模型目录、遗留问题调查与最终测试相关提交，包括但不限于：

- `bb48c74` docs(ai): audit LM Studio, EmbeddingGemma download and vector index failures
- `4f60fe6` fix(ai): classify LM Studio/OpenAI-compatible connection errors and list server models
- `254ea90` fix(ai): verify and download EmbeddingGemma 2 natively with sha256, resume and classified errors
- `bd90d04` style(ai): add braces to Authorization header guard in VLM probe
- `15eafa0` fix(ai): make frame extraction and clip indexing resilient
- `b238676` feat(player): add shared volume control to all playback surfaces
- `f37168e` feat(settings): support custom embedding model directory with safe copy
- `83da816` chore(deps): declare collection dependency
- `e4f7fea` docs(ai): update stability and UX acceptance report
- `83c4aed` fix(ai): clarify online indexing skip and add regression tests
- `53fdafb` docs(ai): record manual acceptance and leftover investigations
- `5378bb9` test(settings): add controlled model directory migration rollback tests

## 3. 无关文件与大文件检查

- `.gitignore` 已忽略 `/models/` 与 `/video_clip_manager-windows-x64.zip`。
- `git status` 干净，未发现未跟踪模型权重、发布 ZIP、缓存或临时截图。
- `git ls-files` 中无模型目录文件或发布 ZIP。
- 已跟踪的 `docs/ui-upgrade` 截图与日志属于阶段报告/验收证据，不是运行时缓存；它们会增加仓库体积，但不阻断合并。
- 未发现意外覆盖用户原有文件。

## 4. 依赖与 Windows 资源配置审查

- `pubspec.yaml` 已恢复 `flutter: sdk: flutter`，并声明 `collection: ^1.18.0`。
- `pubspec.lock` 已更新为 `collection` direct dependency。
- Windows Release 构建成功：`build/windows/x64/runner/Release/video_clip_manager.exe`
- 版本资源由 `windows/runner/Runner.rc` 与 CMake `VERSION_AS_NUMBER` / `VERSION_AS_STRING` 管理；本次未修改版本号。

## 5. 自动化验证

- `flutter analyze`：无 error；仅 info/warning，与基线一致。
- `flutter test`：398 项全部通过（`All tests passed!`）。
- `flutter build windows --release`：成功。
- `flutter build windows --debug`：此前成功。

## 6. 文档与提交记录

- `AI_STABILITY_AND_UX_REPORT.md` 已更新测试数量、用户人工验收结果、未测试项、提交哈希、遗留问题调查与测试结果。
- 文档日期为 `2026-06-16`，与当前审查日期一致。

## 7. 语义搜索 Hit 审查

用户此前搜索“雪山”时未看到 Hit 标记。本次仅做链路审查，未假设单元测试已证明真实 UI 正常。

追踪链路：

`AppState.performSemanticSearch`
→ `_semanticScores[clip.id]`
→ `AppState.getFilteredClips`
→ `clip.copyWith(hitTimestampMs: semHit.hitTimestampMs)`
→ `ClipCard` / `ClipListRow` / `ClipThumbnail`

显示条件：

- `ClipCard`：`clip.hitTimestampMs != null`
- `ClipListRow`：`clip.hitTimestampMs != null`
- `ClipThumbnail`：`clip.hitTimestampMs != null`，并显示 `HIT` 角标

无逐帧命中时间时的预期行为：

- `computeMaxSim` 对空帧返回 `hitTimestampMs: 0`，但 `performSemanticSearch` 只有在 `maxSim.score >= minScore` 时才写入 `_semanticScores`。
- 没有语义命中时不会伪造 Hit 时间戳。
- 已新增 `test/semantic_hit_regression_test.dart` 验证有/无 Hit 两种数据映射状态。

当前结论：

- 未发现明确数据映射缺陷。
- 代码保持不变，等待真实 UI 截图确认 Hit 标记显示。

## 8. 模型目录迁移回滚测试

新增 `test/model_directory_migration_test.dart`，使用独立临时目录验证：

- 迁移校验失败时，配置回滚到旧目录。
- 旧模型文件保持不变。
- 目标目录原有文件保持不变。
- 冲突文件不会被覆盖。
- 已复制文件在失败时被清理。

相关实现已提取为可测试函数：

- `copyEmbeddingModelDirectory`
- `migrateEmbeddingModelDirectory`

## 9. 最终合并风险

1. 分支差异较大（UI 重构 + AI 稳定性 + 测试），合并前建议完整人工回归。
2. `docs/ui-upgrade` 包含大量截图与日志，仓库体积较大；不阻断合并，但可后续清理。
3. 语义搜索 Hit 的真实 UI 显示仍待截图确认，代码未做额外修改。
4. 模型目录迁移失败回滚已有受控测试，但 FilePicker 交互本身仍建议人工验证。
5. 未执行真实 LM Studio 连接、真实 542MB 模型下载和真实视频端到端索引的人工验收。

## 10. 建议

- 在用户批准后执行 `git merge --no-ff feat/dark-ui-workspace` 到 `master`。
- 合并前不要执行 `git reset --hard`、`git clean`、force push 或 Release 创建。
- 合并后建议运行一次 `flutter test` 与 Windows Release 构建作为最终确认。
- 保留当前分支，直到人工验收与截图归档完成。
