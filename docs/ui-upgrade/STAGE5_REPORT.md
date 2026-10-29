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
| Double click | Plays once. On VideosTab this first opened the clip editor (user decision `editor_play`); **superseded by section 11**, which opens an original-video preview instead. |
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

## 11. Follow-up: original-video preview dialog (after user acceptance round 1)

User manual acceptance of Stage 5 passed items 1 to 7 (ClipsTab and PlaylistsTab interaction, M3U8 in library and playlist, M3U8 custom IN/OUT and cross-clip jump, local and missing media, layout near 900/1100/1280 px, Release start/play/close). These were run by the user on a real Windows desktop, not by me. The one open item was VideosTab, where double click, the play icon and the scissors icon all opened `ClipEditorScreen`. This section separates preview from clip creation.

### 11.1 New interaction on VideosTab (list and grid)

| Gesture | Result |
|---|---|
| Single click | Selects. |
| Double click | Opens the original-video preview dialog (once). |
| Play button (`Preview` tooltip) | Opens the preview dialog. The grid tile had no play button before; one was added. |
| Scissors button (`Create Clip`) | Goes straight to `ClipEditorScreen` / `OnlineClipEditorScreen`, no player in between. |
| Right click, `Play` | Opens the preview. |
| Right click, `Create Clip` | Goes to the editor. |
| `Clip from Whole Video`, `Delete Video`, More menu | Unchanged. |

ClipsTab and PlaylistsTab were not edited in this round.

### 11.2 Reuse check (done before writing code)

- `ClipPlaybackScreen` is a clip player (clip IN/OUT range, prev/next clip, rating, tags). Its position listener pauses at the clip end, which is wrong for a whole-video preview, so it was not reused.
- `ClipEditorScreen` / `OnlineClipEditorScreen` own IN/OUT editing and saving; explicitly out of scope for the preview.
- `UnifiedVideoPlayer` (a `ChangeNotifier` service) and `CustomPlayerControls` are not referenced by any other file in `lib`, so they are not part of a working playback path today. I did not evaluate them further and did not reuse them.
- Reused: `resolveMediaSource` / `mediaFailureMessage` / `classifyOpenError` (Stage 5 M3U8 fix), `OnlineVideoCacheService.isVideoUrlExpired` (same expiry rule as the online editor), the `Video(controls: NoVideoControls, fit: BoxFit.contain)` pattern from `ClipEditorScreen`, the playlist screen's `PreviewService().pauseGlobalPreGeneration()` + `ScreenshotService().prepareForPlayback()` start-up and `markReady()` shutdown, and the `media_kit_video` native fullscreen channel through `defaultEnterNativeFullscreen` / `defaultExitNativeFullscreen` (already part of the plugin; the Windows runner was not modified).

### 11.3 Files changed

New:
- `lib/widgets/video_preview/video_preview_dialog.dart` (dialog, `VideoPreviewEnvironment`, fullscreen route)
- `lib/widgets/video_preview/preview_playback.dart` (`PreviewPlayback` interface and the media_kit implementation; one `Player` + one `VideoController`)
- `lib/utils/preview_source.dart` (`resolvePreviewSource`, `isDirectMediaUrl`, `formatPreviewClock`)
- `test/stage5_video_preview_test.dart` (33 tests)

Modified:
- `lib/screens/tabs/videos_tab.dart` (+73/-8 lines: `_openPreview`, handlers, grid Preview button, menu entry `Play`, test hooks `onOpenPreview` and `previewEnvironment`)
- `test/stage5_videos_tab_test.dart` (+48/-6 lines: updated for the new routing, two new tests)
- `docs/ui-upgrade/STAGE5_REPORT.md` (this section)

Not touched: `AppState`, JSON models and schema, `ScreenshotService`, `PreviewService`, `ClipPlaybackScreen`, `ClipEditorScreen`, `OnlineClipEditorScreen`, `ClipsTab`, `PlaylistsTab`, `playlist_playback_screen.dart`, `pubspec.yaml` (no new dependency), the Windows runner.

### 11.4 How the preview works

- Header: video name, kind (Local file / Network stream / Online + platform), duration, pixel size (marked `portrait` when height is larger), clip count, source path (tooltip for the full text).
- Controls: play/pause, seek slider with `position / total`, mute/unmute (restores the previous volume), fullscreen, `Create Clip`. No IN/OUT, no save.
- Keys: Esc closes the dialog, or leaves fullscreen first when fullscreen. Space plays/pauses only when no button holds focus.
- Aspect ratio: `BoxFit.contain` on a black background, so landscape and portrait sources are never stretched or cropped.
- Sources: local files must exist (missing file gives the existing "file does not exist" message and **no player is created**); `http(s)/rtmp/rtsp` and `.m3u8` are not checked on disk; online videos use the downloaded file, then a fresh cached direct link with its saved headers, then a direct media/HLS URL. If an online video only has a page URL (for example a YouTube watch page) and no valid cached link, the dialog says so and points to `Create Clip`, which owns the sniffing flow. The preview does not sniff.
- Load errors: missing file, open failure and open timeout (8 s local, 20 s network) are shown in the dialog, not mixed up.
- Start-up: `PreviewService().pauseGlobalPreGeneration()` and `await ScreenshotService().prepareForPlayback()` run before the dialog is shown.
- Lifecycle: the dialog creates one `Player` and one `VideoController` after the source is resolved. `_release()` is guarded by a single future, so subscriptions, the load timer and the player are released once, then `resumeGlobalPreGeneration()` and `ScreenshotService().markReady()` run. Closing by button, Esc, barrier click or `Create Clip` all go through it.
- Fullscreen: a root-navigator route that shows `playback.buildVideo()` on the **same** controller, plus native window fullscreen via the plugin's channel. It never calls `Player()` or `VideoController()`. Leaving the route (Esc, button) leaves native fullscreen.
- Create Clip: the video is removed from the tree, one frame is awaited, the player is disposed, and only then does the dialog return `PreviewAction.createClip`; `VideosTab` opens the editor afterwards. A test records that no preview player is alive when the editor opens.
- Double-open guard: `_previewBusy` blocks a second preview while one is starting or open; the shared `DoubleTapTracker` already resets after a double click.

### 11.5 Automated checks (Automated unless marked)

| Check | Result |
|---|---|
| `dart format` on touched files | no remaining changes |
| `flutter analyze` on the 4 new/changed preview files (`lib/widgets/video_preview`, `lib/utils/preview_source.dart`, both test files) | No issues (`logs/stage5/preview-analyze-new-files.txt`) |
| `flutter analyze` whole project | 0 errors, 1354 issues (unchanged from the previous Stage 5 run; `logs/stage5/preview-analyze-all.txt`). `videos_tab.dart` still carries its older info/warning lines (unused `online_video_add_dialog.dart` import, `use_build_context_synchronously`, `unnecessary_import`); I did not clean them up to keep the diff small. |
| `flutter test` | **281 / 281 passed** (`logs/stage5/preview-flutter-test.txt`). The previous report said 244. This round added 33 tests in the new file and 2 in `stage5_videos_tab_test.dart` (that file now runs 18), which accounts for 35 of the 37 difference. I did not trace the other 2, so treat the 244 baseline as approximate. |
| `flutter build windows --debug` | Succeeded (`logs/stage5/preview-build-debug.txt`) |
| `flutter build windows --release` | Succeeded (`logs/stage5/preview-build-release.txt`) |

What the tests cover, with a fake player that counts create/open/dispose (media_kit is not loaded in `flutter test`):
- Double click (grid and list) opens the preview, not the editor; a rapid triple click never creates a second player; the Preview button opens the preview and does not select the card.
- Scissors button opens the editor with no player created. Right click `Play` opens the preview; right click `Create Clip` opens the editor.
- Dialog shows name, facts, portrait marker and clip count; one player per dialog; closing by button or Esc disposes it once and releases the services once.
- Ten open/close rounds create and dispose ten players, with exactly one alive while open and none after each close.
- Missing file: message shown, zero players created, play control disabled.
- Play/pause, slider drag causes one seek to the released position, mute sets volume 0 and unmute restores 100.
- Fullscreen enter/exit keeps one player, never disposes it, Esc leaves fullscreen first and keeps the dialog, three round trips still use one player.
- Create Clip: result is `createClip`, the player was already disposed when the result was delivered, and a second tap does not dispose twice; from `VideosTab` the editor opens with zero live preview players.
- Source rules: local exists / missing, local `.m3u8` must exist, network `.m3u8` never touches disk, online direct HLS, online page URL without cache (rejected), fresh cached link with headers and User-Agent, expired cache rejected.

### 11.6 Windows native evidence

- `screenshots/stage5/preview_release_launch.png`: Release exe launched by me, window `video_clip_manager` captured at 1280×720, then closed (process exited). This shows app start only. I did not open the preview dialog in a real window and did not check the content of this image beyond it being saved, so it is **not** evidence of the dialog.
- No screenshot of the preview dialog itself exists. A real-window screenshot needs a real video, which I did not drive.

### 11.7 Not verified (no automated or manual evidence)

Everything below needs a person on the real Windows desktop with real media. None of it was run by me.
- Landscape video playback in the preview.
- Portrait video playback and correct aspect ratio.
- Local file with Unicode / spaces in the path in the real player.
- M3U8 / network media in the preview.
- Real seek accuracy, pause, mute and actual audio silence.
- Real native fullscreen on Windows, Esc inside fullscreen on a real window, and returning to the dialog.
- Create Clip from the preview in the real app (editor starting right after the preview player is disposed).
- Ten consecutive open/close cycles in the real app: no black screen, no residual audio, no leftover memory. The test only proves the Dart-side create/dispose balance with a fake player.
- Window sizes 900×700 and 1280×800 with the dialog open (the dialog sizes itself to the window minus 48 px, not exercised on a real window).
- Preview of an online video with a cached direct link in the real app.

### 11.8 Risks

- The preview dialog pops its player in `dispose()` like the existing screens. If a real Windows run shows a flash or a black frame on close, the first place to look is the order of `Video` unmount and `Player.dispose()`.
- Esc handling in the fullscreen route relies on a `Focus` with `autofocus`. It is tested with the test key simulator, not on a real window.
- Online videos whose cached link is missing or expired cannot be previewed; the user is sent to `Create Clip`. This is intentional so the preview does not duplicate the sniffing flow, but it is a behavior change from "double click opens the online editor".
- The context menu entry `Open / Play` is now `Play` and the play button tooltip is now `Preview`. Anything that located them by the old text (only my own tests did) needs the new text.
- `ScreenshotService().markReady()` runs after each preview closes, matching the playlist screen. If thumbnails stop regenerating after previews, check that call first.

### 11.9 Commit

Feature commit on `feat/dark-ui-workspace`: `36908d4 feat(videos): add original-video preview dialog and split Play from Create Clip`, followed by one small docs-only commit that corrects the wording about `UnifiedVideoPlayer` / `CustomPlayerControls` in 11.2. Not merged to master. No Release was created or published.