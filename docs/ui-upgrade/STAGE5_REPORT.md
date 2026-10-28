# Stage 5 Report: Unified Card Interaction and Playlist M3U8 Fix

Branch: `feat/dark-ui-workspace` (baseline `ff32493`, Stage 4 accepted by user manual verification).
Status: **implemented, awaiting user acceptance.** Not merged to master. No GitHub Release created.

Legend used below: **Automated** = ran in `flutter test` / `flutter analyze`. **Build** = compiled. **Manual** = a person ran it on a real window. **Not verified** = not done.

## 1. Git workspace audit (before changes)

Commands run: `git status`, `git diff --stat`, `git diff --ignore-all-space`, `git log -n 8 --oneline`. No `reset --hard`, `clean`, force overwrite or repo-wide format was used.

| Class | Files | Handling |
|---|---|---|
| Pure format / line-ending differences | About 40 `lib/` and `test/` files that were shown as modified at the start of the session | Already committed in `ff32493` (format only, no behavior change). Nothing left. |
| Stage 3 sidebar and MainScreen changes | `lib/widgets/common/app_sidebar.dart`, `lib/screens/main_screen.dart` | Already committed in `5806fa9` ("remove sidebar buttons duplicated in the top bar"). Nothing left to rescue. |
| Test helpers | `test/fixtures/stage2_desktop_fixture.dart`, Stage 2 tests | Committed in earlier commits. |
| Stage 3 logs and screenshots | `docs/ui-upgrade/logs/stage3`, `screenshots/stage3` | Committed in `897fdf3`. |
| User files left untouched | `.github/.github/workflows/release.yml`, `models/` (ONNX and tokenizer files), `video_clip_manager-windows-x64.zip` | Untracked, **not** committed, not in any Stage 5 commit. `build/` and `.dart_tool/` are git-ignored. |
| Stage 5 files | See section 2 | Committed in separate commits (section 9). |

The "ignore all space" diff on `playlist_playback_screen.dart` was used to confirm that the real change is only the media-source logic (181 insertions and 83 deletions across the 5 modified files, after ignoring whitespace and CR).

Git printed "CRLF will be replaced by LF" warnings for `clip_card.dart`, `clip_list_row.dart` and `playlist_card_parts.dart`. Those files have CRLF working copies; I did not renormalise them.

## 2. Files changed

New:
- `lib/widgets/common/media_card_activation.dart` (shared `DoubleTapTracker`, `MediaCardActivation`, `MediaCardInteractor`)
- `lib/utils/media_source.dart` (media source classification and error messages)
- `test/stage5_card_interaction_test.dart` (25 tests)
- `test/stage5_videos_tab_test.dart` (14 tests)
- `test/stage5_media_source_test.dart` (14 tests)

Modified:
- `lib/widgets/clip_card.dart`, `lib/widgets/clip_list_row.dart`
- `lib/widgets/playlist_card_parts.dart` (re-exports `DoubleTapTracker`, uses `MediaCardInteractor`)
- `lib/screens/tabs/videos_tab.dart`
- `lib/screens/player/playlist_playback_screen.dart`
- `docs/ui-upgrade/STAGE4_REPORT.md` (user manual verification recorded as manual, not automated)

Not touched: `AppState`, JSON models, `Player`/`VideoController` creation, `ScreenshotService`, `PreviewService`, the Windows runner.

## 3. Task A: unified card interaction

Policy on ClipsTab, VideosTab and PlaylistsTab, in grid and list mode:

| Gesture | Result |
|---|---|
| Single click | Selects immediately. No wait for the double-click window. |
| Double click | Plays once. On VideosTab, opens the existing `ClipEditorScreen` or `OnlineClipEditorScreen` (user decision `editor_play`). |
| Right click | Selects, then opens the context menu. |
| Explicit play button | Plays immediately. |
| Favorite, rating, edit, new clip, more menu | Run their own action only. They do not select or play the card. |
| Enter on the focused card | Activates (play), as before. |

Implementation:
- One `DoubleTapTracker` (350 ms window, previously only in the playlist cards) now lives in `common/media_card_activation.dart`. The playlist cards re-export it so existing imports keep working.
- `MediaCardInteractor` wraps the card body with tap, secondary-tap-down and keyboard activation. All three tabs use it, so there is a single double-click decision.
- A third click inside the window does not play again (tracker resets after a double), so a rapid triple click opens one player.
- VideosTab gained selection state (`_selectedVideoId`) with a visible highlight, an explicit Play button and an explicit "new clip" button in both modes, and a context menu with Open and Create Clip. The "Clip from whole video" entry is still there.
- One regression found and fixed while running the Stage 2 tests: opening the context menu with the "更多操作" button on a clip card no longer selected the card. `clip_card.dart` now calls `onSelect` from that button, as the original code did.

Automated coverage (53 new tests):
- Single click selects and does not play; double click plays once; triple click plays once; slow second click does not play.
- Right click selects and shows the menu; Enter plays; focus and selection remain visible.
- Inner buttons (play, edit, add to playlist, favorite, rating, menu) do not bubble to the card.
- VideosTab list and grid: double click opens the editor, a different card does not, Create Clip button remains and works, menu overflow at test font width.
- Existing Stage 2 and Stage 4 tests (including playlist card tests) still pass.

## 4. Task B: playlist M3U8 "file does not exist"

### Root cause
`PlaylistPlaybackScreen._initializePlayer` ran `File(clip.videoPath).exists()` on every item before opening it. For an `http://` or `https://` M3U8 URL that check always returns false, so the screen showed "文件不存在". `ClipPlaybackScreen` opens such sources without that check, which is why the same resource played in the library. This is not a URL expiry or network problem. The reference chain (PlaylistItem to Clip to `videoPath`) is unchanged; the playlist screen simply treated every path as a local file.

### Fix
- `resolveMediaSource(path)` classifies the path as `local`, `network` (http, https, rtmp, rtsp) or `invalid`.
  - Local paths (including Windows drive paths, Unicode names and local `.m3u8`) are still checked with the file system, and a missing file still reports "file does not exist".
  - Network sources are not checked on disk.
  - Empty or host-less URLs are `invalid`.
- Failures are classified as `localFileMissing`, `openTimeout` or `openFailed`. Only `localFileMissing` says the file does not exist. Open timeouts and open errors get their own message; the old code showed nothing for generic open errors.
- For network sources, the screen waits up to 12 s for the duration before seeking to the clip IN point, matching the HLS wait in `ClipPlaybackScreen`. If the wait expires it continues and the existing seek/play timeouts apply.
- The existing `Player`, `VideoController`, timers, `ScreenshotService` calls and timeouts are not changed. `dart:io` was removed from this screen because it is no longer used.

### Regression results (Automated)
`stage5_media_source_test.dart`, 14 tests, all pass:
- Local video usable; missing local video reports `localFileMissing`.
- Local `.m3u8` usable, missing one is not.
- HTTP and HTTPS `.m3u8` never touch the file system (verified with a throwing file checker).
- Invalid URL and empty path are classified apart; a throwing file check counts as missing.
- Timeout and open errors are not reported as "file missing"; message text checked.
- Custom IN/OUT stays in source time; accumulated playlist time is the sum of effective durations, not source time.

Gap: there is no widget or integration test that switches clips inside `PlaylistPlaybackScreen`. The screen creates a real media_kit `Player` and was not mocked (same limit as Stage 4). The cross-clip case is covered only by the time-mapping unit test above and by the Stage 4 manual check #6.

## 5. Stage 4 carry-over review

Code review only unless noted. No code was changed for these.

1. **1090 / 1100 / 1110 px resize.** The breakpoint is `playbackLayoutFor` at 1100. Wide and narrow layouts use the same `Flex` with identical child types and order; only `direction`, spacer sizes and the queue panel size change. `Video(controller: controller)` sits under the same `Expanded > Column > Expanded` path in both, so Flutter keeps the element and the `VideoController` is created once in `_initializePlayer`. I did not resize a live window across the breakpoint, so this is a code-level conclusion. Risk: low.
2. **Shuffle and loop highlight and scroll.** The current row is chosen by identity against `_currentItem`, and auto-scroll uses the row index of that same entry in `_playlistItems`, so the highlight follows the item actually playing even when the play order is shuffled. Scroll is skipped when the same clip id repeats (already in view). Reviewed in code. The user manually confirmed highlight in all three modes in Stage 4.
3. **`PlaylistDraft` reorder and save.** `commit()` rewrites only `order` through `copyWith`, so `customStartTime` and `customEndTime` are preserved. Orphan items are kept and appended. Other playlist metadata is not part of the commit. Covered by the 17 `playlist_draft_test` tests plus the Stage 4 manual check #2.
4. **ScreenshotService, PreviewService, Media Kit lifecycle.** The Stage 5 diff to the player screen does not touch `dispose()`, the boot and init flow, `ScreenshotService` calls, `PreviewService`, or any timeout. One behavioral addition: for network sources there can now be up to 12 s of waiting before the first seek. This happens after `open`, guarded by `mounted`. Theoretical risk: ready markers for a slow HLS stream come later than before. Not rewritten.
5. **Tiny clip hit width.** Visual segment width comes from `timeline_layout.dart` (`minSegment`, default 8 px). Durations and tooltips use `playlistItemDuration(...).inMilliseconds`. The two are separate.

## 6. Responsive and UI check

**Not verified on a real window at all five sizes.** I did not manually resize the real app to 900×700, 1090×800, 1110×800, 1280×800 and 1600×900, and I did not review dialogs, popup menus, tooltips and error states there.

What did run: widget tests cover the Library, VideosTab and PlaylistsTab at test sizes, and the existing Stage 2 to 4 tests cover 900 and 1280. VideosTab had one text overflow in a popup item that was caught by a test and fixed (ellipsis). No other layout changes were made.

## 7. Checks

| Check | Result | Kind |
|---|---|---|
| `dart format` on the 10 Stage 5 files | 0 files changed | Automated |
| `flutter analyze` on the 8 new/changed Stage 5 files (excluding `videos_tab.dart` and `playlist_playback_screen.dart`) | No issues | Automated |
| `flutter analyze` whole project | 0 errors. 1354 issues in total (warnings and infos), log `logs/stage5-analyze.txt`. The Stage 4 baseline log had 704 lines. | Automated |
| `flutter test` | **244 / 244 passed** (191 from Stage 4 plus 53 new) | Automated |
| `flutter build windows --debug` | Succeeded (`logs/stage5/build-debug.txt`) | Build |
| `flutter build windows --release` | Succeeded (`logs/stage5/build-release.txt`) | Build |

Analyze comparison with the Stage 4 baseline: the totals differ (704 vs 1354). I did not find the cause. The extra diagnostics in the Stage 5 log are in files this stage did not edit (for example `custom_player_controls.dart`, `add_to_playlist_dialog.dart`, `yt_dlp_service.dart`, `test/tag_utils_test.dart`), and the Stage 4 log may have been produced with a narrower scope. Treat the project-wide numbers as not comparable. Comparing only the two files this stage edited: `playlist_playback_screen.dart` went from 137 to 136 diagnostics and `videos_tab.dart` from 9 to 10. The remaining diagnostics (`avoid_print`, deprecated `RawKeyboardListener`, unused imports and fields) existed before this stage. I did not do a complete one-to-one diff of every diagnostic, which the task asked for, so that comparison is incomplete.

Release bundle contents (checked): `video_clip_manager.exe`, `flutter_windows.dll`, `libmpv-2.dll`, `onnxruntime.dll`, `d3dcompiler_47.dll`, `libEGL.dll`, `libGLESv2.dll`, `vk_swiftshader.dll`, `vulkan-1.dll`, `zlib.dll`, plugin DLLs (`desktop_drop`, `media_kit_video`, `media_kit_libs_windows_video`, `url_launcher_windows`, `volume_controller`), and `data/` with `app.so`, `icudtl.dat` and `flutter_assets`.

## 8. Windows run verification

| Item | Result |
|---|---|
| Release exe launch | Started by me; process stayed alive for 12 s with a window titled `video_clip_manager` (about 727 MB working set), then I closed it. Screenshot: `screenshots/stage5/release_launch.png` (1280×720 window). I have not confirmed from the image what screen was showing. |
| Debug exe launch | Not verified (built only) |
| Same M3U8 in library and playlist plays the same | **Not verified.** Needs a real run with a real M3U8 URL. |
| Double-click / right-click on the three tabs in the real app | **Not verified** (widget tests only) |
| Player, screenshot, preview and AI settings entries still work | **Not verified** on a real window. Their code was not modified. |

## 9. Commits

See `git log` on the branch. In order:
1. `docs(stage4)`: Stage 4 report records the 8 user manual verifications.
2. `feat(ui)`: unified card interaction (shared interactor, three tabs, tests).
3. `fix(playlist)`: M3U8 and network sources in the playlist player (media source resolver, tests).
4. `docs(stage5)`: this report, logs, launch screenshot.

## 10. Open issues and release risks

- M3U8 playback in the playlist is fixed by code and unit tests only. It must be confirmed on Windows with a real M3U8 URL before release.
- VideosTab double-click now opens the editor; users who expected double-click to play the video directly will see a change. The Play button is explicit on each card.
- Network sources can wait up to 12 s for duration before the first seek (see 5.4).
- Missing: a widget or integration test of `PlaylistPlaybackScreen` clip-to-clip switching.
- Whole-project analyze baseline comparison is incomplete (section 7).
- Responsive check on a real window at the five sizes was not done.
- Untracked user files (`models/`, `.github/.github/`, the zip) are outside this change; the `models/` ONNX data is large and needs a decision before any release packaging.
