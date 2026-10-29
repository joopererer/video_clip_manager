# Logo / Icon 候选（电影胶片主题）— 待用户确认

本目录只包含**候选与预览**。`windows/runner/resources/app_icon.ico` 未被修改，Windows Runner 也没有接入任何新图标。

## 设计约束（来自 v1.1.0 需求）

- 主体：一段横向电影胶片，上、下均有齿孔。
- 胶片内含若干连续画面，其中**一帧**突出显示为"被选中的视频片段"。
- 深色背景 + 紫色强调（`#8B7CF6`）。
- 无文字；不堆叠剪刀、播放按钮、AI 星星。
- 必须在 16 / 32 / 256 px 下保持辨识度。
- 现代、简洁，符合 Windows 应用图标习惯。

## 候选一览

| 候选 | 描述 | 强调帧位置 | 16 px 紫色像素 | 32 px 紫色像素 |
| --- | --- | --- | --- | --- |
| A `candidate_a` | 四帧胶片，第二帧选中 | 偏左 | 12 | 40 |
| B `candidate_b` | 三帧胶片，中间帧选中（最接近胶片负片） | 居中 | 16 | 61 |
| C `candidate_c` | 双帧极简，右帧选中（16 px 最清晰） | 右侧 | 20 | 110 |
| D `candidate_d` | 四帧微透视胶片带 | 中间 | 7 | 38 |

紫色像素统计是对 `*_16.png` / `*_32.png` 的实际采样（`R/G/B` 中蓝色分量 > 140 且 B−G > 40），用来客观判断"选中帧在最小尺寸下是否还看得见"。C 最佳，D 因为透视变换在 16 px 下最弱。

## 文件

- `candidate_{a,b,c,d}.svg` — 矢量母版（`viewBox 0 0 256 256`），后续 ICO 生产以此为准。
- `candidate_{a,b,c,d}_1024.png` — 4 倍超采样母版。
- `candidate_{a,b,c,d}_{256,64,48,32,16}.png` — 各尺寸渲染。
- `logo_candidates_preview.png` — 评审用对照图：每个候选 256 px 大图 + 64/48/32/16 px 小图 + 模拟 Windows 任务栏。
- `generate_candidates.py`、`generate_preview.py`、`generate_svg.py` — 可复现生成脚本（Pillow 10.x，无外部图形依赖）。

重新生成：

```bash
python docs/ui-upgrade/logo/generate_candidates.py
python docs/ui-upgrade/logo/generate_svg.py
python docs/ui-upgrade/logo/generate_preview.py
```

## 确认后的接入流程（本阶段不执行）

1. 用户确认最终候选（或给出调整意见）。
2. 用 SVG 母版导出 PNG：16 / 24 / 32 / 48 / 64 / 128 / 256。
3. 用多尺寸帧合成 `app_icon.ico`，覆盖 `windows/runner/resources/app_icon.ico`。
4. 需要时同步文档/商店展示图（本项目暂无 MSIX/Store 资产）。
5. `flutter build windows --release` 后确认 EXE 图标、任务栏图标、窗口标题栏图标。
6. 更新本文件记录最终选择与新的紫色像素统计。

## 未完成事项

- 视觉确认需要用户本人看图（本阶段只生成候选，不改正式图标）。
- 接入后需要重新录一次 16 px 任务栏实际效果截图。
