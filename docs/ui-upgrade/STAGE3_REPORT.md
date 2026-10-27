# Stage 3 Report: Clip Editor UI Refactor

Branch: `feat/dark-ui-workspace` (baseline commit `bb7c614`). Awaiting acceptance. Stage 4 not started.

## 1. Files changed

New files:
- `lib/utils/timecode.dart` (pure): `formatTimecode` and `parseTimecode` (HH:MM:SS.mmm format, also accepts MM:SS.mmm, plain seconds, full-width `：` `。`), ms rounding and clamping helpers.
- `lib/utils/clip_range.dart` (pure): `ClipRangeRules` class enforcing `0 <= start < end <= sourceDuration`.
- `lib/utils/clip_edit_rules.dart` (pure): `composeClip`, `isClipDirty`, `validateClipForSave`.
- `lib/widgets/timecode_field.dart`: stateful editable timecode input.
- `lib/widgets/clip_range_timeline.dart`: CustomPainter timeline with draggable handles and hover preview.
- `lib/widgets/clip_editor_key_handler.dart`: key resolution and focus guard.
- `lib/widgets/clip_editor/clip_properties_panel.dart`: side panel for details, tags, notes, AI describe, rating, cover.
- `lib/widgets/clip_editor/clip_list_panel.dart`: clips list for the current video.
- `test/stage3_timecode_range_test.dart` and `test/stage3_widgets_test.dart`: unit and widget tests.

Modified:
- `lib/screens/player/clip_editor_screen.dart`: rebuilt layout and state handling. Player lifecycle preserved.

Not touched: data models, JSON serialization, other screens, other tabs.
Note: `git status` lists stage 1/2 changes still in the working tree. They are not part of this stage.

## 2. Features

- Top bar: back (unsaved-change prompt), title/status, new clip, discard, save.
- Wide (>= 1000 px): `MultiSplitView` with video workspace and a Properties/Clips tabbed panel.
- Narrow (< 1000 px): side panel moves to an end drawer.
- Transport: play/pause, nudges, go to IN/OUT, mute, preview.
- IN/OUT: editable timecode fields with millisecond precision. Timeline handles are draggable.
- Shortcuts: Space, I/1, O/2, Left/Right (100 ms, Shift 1 s, Ctrl 10 ms), Ctrl+S save, S mute, C cover, F1 hints.
- Shortcuts do not fire while a text field, timecode field or IME composition has focus. Ctrl+S no longer toggles mute.
- Frame accuracy is not claimed. Seeks are millisecond-level requests to the underlying media backend.

## 3. Checks

| Item | Result |
| --- | --- |
| `dart format` on the 9 new/changed lib files | 0 files reformatted |
| `flutter analyze` | 1350 issues: 0 errors, 97 warnings (no new ones), 1253 infos. Baseline was 1356. Log: `logs/stage3/analyze-stage3.txt` |
| `flutter test` | 99 tests passed. New: 69 tests in the two stage 3 test files. Log: `logs/stage3/test-stage3.txt` |
| `flutter build windows --debug` | Succeeded (exit 0, about 60 s). Produced `build\windows\x64\runner\Debug\video_clip_manager.exe`. Log: `logs/stage3/build-windows.txt` |

Test coverage: timecode parsing/formatting, range rules and clamping, timecode field commit/revert/nudge, key mapping and focus guard (including IME), timeline geometry and drag logic, 900 px layout without overflow.

Not covered by automated tests: the full `ClipEditorScreen` save/cancel/delete workflow against a real Player.

## 4. Code invariants

Verified by tests or code reading:
- No integer-second `RangeSlider`; all times are millisecond values.
- Single-key shortcuts do not fire in text fields or during IME composition. Ctrl+S is not consumed.
- IN/OUT boundaries are enforced; IN cannot equal or exceed OUT.
- Timeline drag respects bounds and never goes negative.
- Layout does not overflow at 900 px (widget test).

Verified by code reading only:
- Soft clipping is metadata only; no transcoding or export.
- No extra `Player` instances are created; the existing lifecycle is kept.
- Seeks are coalesced into a single in-flight job.
- No JSON schema change.

Not verified:
- Real playback and seek behavior on the Windows runner.
- Portrait video rendering on the desktop app.
- AI auto-tagging, cover capture and delete confirmation in the full screen.

## 5. Screenshots

Skipped as requested. Files under `docs/ui-upgrade/screenshots/stage3/windows/` (00_library_1280x800.png, 03_videos_tab.png, 04_clip_editor_wide_1280x800.png) were saved by the capture script, but I have not confirmed their contents. Click coordinates were estimated. **They are not accepted as evidence.** Still missing: portrait video, 900x700 narrow layout, timecode editing, existing-clip editing, missing file and invalid input states.

## 6. Windows build result

`flutter build windows --debug` succeeded with exit code 0 and built `video_clip_manager.exe`. This shows the code compiles and links. It does not show that the editor behaves correctly at runtime, since no verified screenshots or manual playback runs exist (see sections 4 and 5).

## 7. Risks

- Large rewrite of `clip_editor_screen.dart` (~1.3k lines added, ~1.2k removed). Recommend a full manual pass on real media.
- Keyboard focus handoff after mouse clicks is tested in the widget layer but not on a real window.
- Seeking precision depends on the media backend; no measurement was done.
- Stage 1/2 changes in the working tree need to be separated before committing.
