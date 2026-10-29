# Stage 3 Report: Clip Editor UI Refactor

Branch: `feat/dark-ui-workspace` (baseline commit `bb7c614`). Accepted by the user after manual Windows testing (see section 5).

## Follow-up observations (not changed)

Recorded from the lifecycle audit (`STAGE3_LIFECYCLE_AUDIT.md`). No code was changed for either item, per the user's decision.

1. `player.dispose()` in `ClipEditorScreen.dispose()` is not awaited and does not wait for `_seekLoop`. A seek already in flight on a disposed player could throw. The loop catches errors and checks `mounted`, but this was not observed at runtime. Setting `_queuedSeek = null` would only stop further queued seeks; it would not cancel a seek already running.
2. `ClipEditorScreen` does not call `ScreenshotService.prepareForPlayback()`. It only pauses `PreviewService` pre-generation. That pause does not mean `ScreenshotService` is idle, so its hidden host may still be active while the editor's Player exists. `prepareForPlayback()` is called only by `PlaylistsTab` and `PlaylistPlaybackScreen`. The 10x open/close test passed, but this remains an item to watch.

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

## 5. Manual Verification by Human Operator

**Status**: Stage 3 accepted by the user on 2026-10-27 after a manual test on a real Windows window.

User-reported result: 6/6 items passed.
1. Video playback
2. Seek
3. IN/OUT millisecond editing
4. Save and cancel
5. Portrait video and narrow-window layout
6. Opening and closing the editor 10 times in a row

These six results were reported by the user as a summary. They were not mapped to the individual checklist items below, so those boxes are left unticked. Items not named above (for example IME input, AI tagging, cover capture, missing-file handling, delete confirmation, and the six required screenshots) have no individual result on record.

Automated UI verification was not used (the UIA tree problem described below is unresolved).

### Manual Verification Checklist (reference list; not individually ticked)

**Required assets**: a test database with at least two videos (one landscape, one portrait, each >= 30 seconds, valid paths). Do not use production data. Preferably use the generated sample database from `tool/stage2_desktop_capture.py fixture`.

**Entry**: Run `flutter run -d windows` or the Debug build, navigate to the Videos tab, click a video card → New Clip.

#### A. Video playback and seeking
- [ ] A1. Video frame displays (not black, not frozen).
- [ ] A2. Pressing Space toggles play/pause; transport shows "Play" or "Pause" tooltip.
- [ ] A3. Dragging the timeline playhead updates the video frame.
- [ ] A4. Clicking the "Go to IN" and "Go to OUT" buttons seek correctly.
- [ ] A5. Pressing Left (100 ms back) and Right (100 ms forward) seek without errors.
- [ ] A6. Pressing Shift+Left (1 s back) and Shift+Right (1 s forward) seek.
- [ ] A7. Pressing S toggles mute; transport shows "Mute" or "Unmute" tooltip.

#### B. IN/OUT point editing
- [ ] B1. Dragging the IN handle (green left edge) updates the IN timecode.
- [ ] B2. Dragging the OUT handle (orange right edge) updates the OUT timecode.
- [ ] B3. IN cannot be dragged to or beyond OUT.
- [ ] B4. OUT cannot be dragged to or below IN.
- [ ] B5. Clicking inside a timecode field, typing a valid time (e.g., `00:05.500`), and pressing Enter updates the timeline.
- [ ] B6. Typing an invalid time (e.g., `abc`, `99:99:99.999`, or time > video duration) and pressing Enter reverts the field to the current value or shows an error.
- [ ] B7. Pressing Up/Down arrows in a timecode field nudges the value by 100 ms; Shift+Up/Down nudges by 1 s.
- [ ] B8. Pressing I (or 1) sets IN to the current playhead position.
- [ ] B9. Pressing O (or 2) sets OUT to the current playhead position.

#### C. Keyboard shortcuts and focus safety
- [ ] C1. Typing in the clip title field (Properties tab) does not trigger Space (play/pause), I, O, or Left/Right shortcuts.
- [ ] C2. Typing in the Tags field does not trigger shortcuts.
- [ ] C3. Typing in the Notes field (multi-line) does not trigger shortcuts.
- [ ] C4. Typing in a timecode field does not trigger shortcuts except Up/Down/Esc/Enter.
- [ ] C5. After clicking away from a text field, pressing Space resumes play/pause.
- [ ] C6. Pressing Ctrl+S at any time (in or out of a text field) triggers Save without firing any other shortcut.
- [ ] C7. During Chinese IME composition (if available), Space and single letters do not trigger shortcuts.

#### D. Clip creation and saving
- [ ] D1. Creating a new clip, setting a title and IN/OUT points, then pressing Save or Ctrl+S adds the clip to the list (Clips tab) and shows a success message or returns to the previous screen.
- [ ] D2. The saved clip appears in the Clips tab with the correct title, time range, and duration.
- [ ] D3. Clicking Cancel or back button before saving shows an "Unsaved changes" dialog if dirty.
- [ ] D4. Clicking Discard clears the form without saving.

#### E. Editing existing clips
- [ ] E1. Opening an existing clip (from the Clips tab or the Clips list in the editor) pre-fills the title, IN, OUT, tags, notes, rating, and favorite status.
- [ ] E2. Changing the title and saving updates the clip.
- [ ] E3. Changing IN/OUT and saving updates the clip time range.
- [ ] E4. Clicking Cancel restores the original values (dirty check works).
- [ ] E5. Clicking the delete button (trash icon) in the Clips panel shows a confirmation dialog and removes the clip if confirmed.

#### F. Layout and responsiveness
- [ ] F1. At 1280x800, the layout shows the video workspace on the left, and a Properties/Clips tabbed panel on the right (wide layout).
- [ ] F2. At 900x700 (resize the window), the side panel moves to an end drawer accessible via the menu button in the top bar; no overflow occurs.
- [ ] F3. Opening a portrait video (9:16 or similar) shows the full frame without cropping (black bars on sides).
- [ ] F4. Opening a landscape video (16:9) fills the available space.

#### G. Metadata and cover
- [ ] G1. Clicking the star rating in the Properties tab saves the rating after the clip is saved.
- [ ] G2. Clicking the favorite button toggles the favorite status (after save).
- [ ] G3. Clicking "Capture Cover" while playing or paused saves a thumbnail; the cover preview updates.
- [ ] G4. Clicking "AI Describe" (if configured with a working VLM backend) generates a caption; otherwise shows an error or pending state.

#### H. Error handling
- [ ] H1. If the source video file is deleted or moved, opening the editor shows an error message or missing-file indicator.
- [ ] H2. Attempting to save a clip with an empty title shows a validation error.
- [ ] H3. Attempting to save a clip with IN >= OUT shows a validation error.

#### I. Resource stability
- [ ] I1. Opening the editor, saving, and closing 10 times in a row does not crash or show memory/resource warnings.
- [ ] I2. Switching between two different source videos (Video A → Editor → Back → Video B → Editor → Back → Video A → Editor) does not show black frames, frozen frames, or texture errors.
- [ ] I3. Closing the editor (by back button or Cancel) stops video playback and does not leave audio playing in the background.

### Required screenshots (to be provided manually)
- `01_editor_landscape_1280x800.png`: editor with a landscape video at 1280x800.
- `02_editor_portrait_1280x800.png`: editor with a portrait video at 1280x800, showing black bars (not cropped).
- `03_editor_narrow_900x700.png`: editor at 900x700 with the side panel in the drawer (menu button visible).
- `04_timecode_editing.png`: a timecode field focused and being edited.
- `05_existing_clip_edit.png`: editor showing an existing clip with pre-filled data.
- `06_invalid_timecode.png`: a timecode field after entering an invalid value, showing revert or error.

All screenshots must clearly show the editor screen (back button, timeline, transport, timecode fields visible). Place them in `docs/ui-upgrade/screenshots/stage3/windows/manual/`.

**Status**: Not provided. The user did not supply manual screenshots but reported functional tests 6/6 passed. Since the application compiles, links, and runs, and the user verified the core workflows on a real device, stage 3 is accepted.

### Automated attempt log
- `ensureSemantics()` enabled in `test/fixtures/stage2_desktop_fixture.dart`.
- `tool/stage3_uia_probe.py` reads the application's UIA tree via `pywinauto`.
- Result: in the runs I made, only the FLUTTERVIEW pane and system buttons were listed; no Flutter widgets appeared.
- Root cause NOT determined. I did not check whether the probe connected correctly, whether semantics were actually enabled on the running build, or whether a longer wait or a different UIA backend would expose the tree. This is an unresolved tooling problem, not a proven limitation of Flutter on Windows.
- I stopped automated clicking, as the task instructed, because screen identity could not be confirmed.
- All items in the checklist above are **unverified**. No playback, seek, IN/OUT drag, data persistence, 10x open/close, video switching, keyboard, IME or missing-file test was executed on a real Windows window in this round.
- Note: `taskkill /IM video_clip_manager.exe` was used to clean up between launches. It matches by process name, so it may have ended a debug instance that was not started by this tooling.

## 5b. Round 2 changes

- Removed the sidebar buttons AI settings, scraper settings, appearance and about (`lib/widgets/common/app_sidebar.dart`, call site in `lib/screens/main_screen.dart`, and `test/stage2_visual_verification_test.dart`). The same actions remain in the top header. The unused `_buildActionItem` helper was removed too. `flutter analyze` on these three files: no issues. I did not look at the sidebar on a real window.
- `test/fixtures/stage2_desktop_fixture.dart`: added `ensureSemantics()` (fixture only, not production).
- `tool/stage3_uia_probe.py`: new UIA dump helper (see section 5).
- No defects were found in the editor this round, because no runtime test was executed. No editor logic was changed.

## 5c. Code review of lifecycle (`clip_editor_screen.dart`, code reading only)

- Player creation/disposal: one `Player` and one `VideoController` in `initState`. `dispose()` cancels the stream subscriptions and the load timer, resumes `PreviewService` pre-generation, then calls `player.dispose()`. Nothing is created in `build()`. The baseline (`c7011b2`) had the same pattern.
- `PreviewService`: `pauseGlobalPreGeneration()` in `initState`, `resumeGlobalPreGeneration()` in `dispose()`. Same as baseline.
- `ScreenshotService.prepareForPlayback`: **not called in this screen, and not in the baseline version either** (searched both). I cannot say where it is expected to be called. Not changed.
- Seek coalescing: `_seekTo` stores the latest target in `_queuedSeek`; one `_runSeekLoop` runs at a time (`_seekLoop`), each seek has a 5 s timeout, errors are caught, and `_seeking`/`_seekLoop` are reset in `finally`.
- Async safety after close: callbacks check `mounted` (position, duration, error stream, seek loop, save, AI caption, cover). Possible gap: `player.dispose()` is not awaited, so a seek already in flight on a disposed player would throw; it is caught by the `try` in the loop. Not exercised at runtime.
- Save/cancel/delete: reviewed only through the code paths listed above; not run against a real Player.

## 5d. Checks, round 2

| Item | Result | Log |
| --- | --- | --- |
| `dart format lib test tool` | run | none |
| `flutter test` | 99 passed | `logs/stage3/test-round2.txt` |
| `flutter analyze` | 1357 issues, 97 warnings, 0 errors. Previous run was 1350, baseline 1356. I did not identify the extra 7 infos; none were in the files touched this round (the ones listed are in `online_clip_editor_screen.dart`) | `logs/stage3/analyze-round2.txt` |
| `flutter build windows --debug` | Built `video_clip_manager.exe` | `logs/stage3/build-round2.txt` |
| Fixture build (`-t test/fixtures/stage2_desktop_fixture.dart`) | Built | `logs/stage3/build-windows-fixture3.txt` |

## 5e. Unverified items and reasons

Everything in section 2 of the round 2 request that needs a running editor: playback, pause, seek, IN/OUT drag, timecode input, repeated edits during playback, 10x open/close, switching videos, new/edit/cancel/save and reload of clips, ms round trip, tags/notes/rating/favorite/cover, AI tagging, 1280x800 landscape and portrait, 900x700, panel switching, focus and IME shortcuts, missing source file, and all six required screenshots. Reason: I could not identify the current screen from outside the app (section 5), and I did not run a manual session. The synthetic FFmpeg fixture database was generated and the app launches with it, but nothing past launch was verified.

## 5f. Git state

- HEAD: `af42909` (stage 3), above `bb7c614`.
- Uncommitted tracked changes: `lib/screens/main_screen.dart`, `lib/widgets/common/app_sidebar.dart`, `test/stage2_visual_verification_test.dart`, `test/fixtures/stage2_desktop_fixture.dart`, `docs/ui-upgrade/STAGE3_REPORT.md`, and two files under `docs/ui-upgrade/logs/stage3/`.
- New untracked: `tool/stage3_uia_probe.py`, new logs, two screenshots (`05_library_1280x800.png`, `06_videos_tab.png`, not reviewed, not evidence).
- Untracked, not mine and left alone: `models/`, `video_clip_manager-windows-x64.zip`, `flutter_01.png`, `.github/.github/`.
- Nothing from this round has been committed.

## 6. Windows build result

`flutter build windows --debug` succeeded with exit code 0 and built `video_clip_manager.exe`. This shows the code compiles and links. It does not show that the editor behaves correctly at runtime, since no verified screenshots or manual playback runs exist (see sections 4 and 5).

## 7. Risks

- Large rewrite of `clip_editor_screen.dart` (~1.3k lines added, ~1.2k removed). Recommend a full manual pass on real media.
- Keyboard focus handoff after mouse clicks is tested in the widget layer but not on a real window.
- Seeking precision depends on the media backend; no measurement was done.
- Stage 1/2 changes in the working tree need to be separated before committing.
