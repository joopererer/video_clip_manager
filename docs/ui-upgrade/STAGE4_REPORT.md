# Stage 4 Report: Playlist Workbench UI

Branch: `feat/dark-ui-workspace` (baseline `af42909`, Stage 3 accepted).
Status: **accepted after user manual verification on real Windows** (see section 5a). Stage 5 follows in `STAGE5_REPORT.md`.

## 1. Commits

| Part | Commit | Scope |
|---|---|---|
| 1 | `ff674d1` | `PlaylistDraft`, ms duration helpers, save bug fix, unit tests |
| 2 | `6c35921` | `PlaylistManagementScreen` dark workspace, transactional save/reset, unsaved-changes guard |
| 3 | `d973515` | `PlaylistTimelineView` dark theme, minimum segment width, real-time tooltips, drop indicator |
| 4 | `649902e` | `PlaylistsTab` responsive grid/list, select / double-click play / right-click menu |
| 5 | `7d00df5` | `PlaylistPlaybackScreen` dark layout, centered transport, compact queue panel |

## 2. Decisions applied

**Decision 1, card interaction.** Single click selects, double click plays, the play button plays directly, right-click opens a menu (play, edit, manage, export, delete). Hover, selected and focus states are styled. Selection is immediate (no 300 ms double-tap delay). Double-tap is detected by `DoubleTapTracker` with a 350 ms window.

**Decision 2, management save bug.** The old `_saveChanges` applied one reorder and then `break`ed. It now commits the whole draft in one call: `AppState.updatePlaylist(id, items: draft.commit())`.
- Reorder, move and remove only change the in-memory `PlaylistDraft`.
- Cancel / Reset / discard never write to `AppState`.
- Items whose clip was deleted (orphans) are kept on save.
- `customStartTime` / `customEndTime` are kept.
- Other playlist metadata is not touched.
- `PopScope` prompts when leaving with unsaved edits.

**Durations.** All playlist durations come from `PlaylistItemWithClip.effectiveDuration`, summed in milliseconds (`lib/utils/playlist_time.dart`). The cached `Playlist.totalDuration` is no longer used for display. In the player, the global percentage now uses milliseconds as well (`playbackPercent`); it used whole seconds before, which read 0% for playlists shorter than 1 s.

## 3. Part 5 details (`PlaylistPlaybackScreen`)

- Dark tokens via `context.appColors`, `AppSpacing`, `AppRadius`. Toolbar height 60.
- Layout (`lib/utils/playlist_playback_layout.dart`):
  - width >= 1100: video and controls on the left, queue panel on the right (320 px, 380 px at >= 1500).
  - width < 1100: queue below the video, height 26% of the window clamped to 112..220, horizontal list.
  - The same `Flex` tree is used for both, so the `Video` widget is not rebuilt when the window crosses the breakpoint.
- Control panel: current clip name, `n / total`, clip position, global position with percent, mode badge, progress bar, and a centered transport row (mute, previous, large play/pause, next, replay).
- Queue rows: clip colour stripe, index, name, duration, custom-range icon, play-order badge (only when it differs from the list index), state icon (playing / paused / played / idle). Current row is highlighted and scrolled into view.
- The queue toggle (I key / toolbar icon) replaces the old "info" toggle; the header info block it controlled is now the control panel, which is always shown.
- Clip colours use the same palette as the timeline (`playlistClipColor`, renamed from the private `_colorForClip`).
- Removed the red debug dot on the global progress bar hover.

**Not changed:** `_bootPlaylistPlayer`, `_initializePlayer`, `dispose()`, seek/play timeouts, `_pendingGlobalSeek*`, playback mode generation, key handling, `ScreenshotService.prepareForPlayback()/whenIdle()/markReady()`, `PreviewService` pause, and `CustomProgressBar`. I checked this against the commit diff. The only non-UI edits in the screen are: the percent helper, a `_queueScroll` controller (created, and disposed in `dispose()` before `super.dispose()`; the player disposal block is untouched), and format-only line wrapping described in section 7.

## 4. Checks

| Check | Result | Log |
|---|---|---|
| `dart format` on touched files | done | n/a |
| `flutter analyze` | 0 errors. Warnings and infos remain and all are in code this stage did not write (unused imports, `avoid_print`, deprecated `RawKeyboardListener`, etc.). | `logs/stage4/analyze.txt` |
| `flutter test` | **191 / 191 passed** | `logs/stage4/test.txt` |
| `flutter build windows --debug` | succeeded, `video_clip_manager.exe` built | `logs/stage4/build-windows.txt` |

New tests this stage: `playlist_draft_test` (17), `playlist_save_regression_test`, `stage4_playlist_management_test` (8), `stage4_playlist_timeline_test` (15), `stage4_playlists_tab_test` (33), `stage4_playlist_playback_test` (layout breakpoints, queue scroll offset, percent math).

## 5. What was NOT verified

- **Real Windows screenshots (1280x800, 900x700) were not captured.** No images exist under `docs/ui-upgrade/screenshots/stage4/`. UI Automation clicking was dropped in Stage 3 and I did not retry it.
- **`PlaylistPlaybackScreen` has no widget test.** It creates a real media_kit `Player` and goes through `ScreenshotService`, which I did not mock. Only its pure layout/percent helpers are unit tested. The screen itself has been compiled and linked, not run.
- Playback, seek, mode switching, clicking a queue row, global progress seek, and repeated open/close of the playlist player were not exercised on a running window.
- Overflow at 900x700 is covered by widget tests for the management screen and playlists tab only. The player screen's 900x700 layout is unchecked.

## 5a. User manual verification (real Windows app)

The following 8 items were verified by the user in the running Windows application and passed. These are **manual user verifications, not automated tests**, and the assistant did not run them.

| # | Item | Result |
|---|---|---|
| 1 | Playlist card: click selects, double-click plays, right-click menu | User manually verified, passed |
| 2 | Drag several clips in a row, save, reopen: order correct | User manually verified, passed |
| 3 | Reset, Cancel and unsaved-exit prompt | User manually verified, passed |
| 4 | 1280x800 player: right queue, control bar, highlight | User manually verified, passed |
| 5 | 900x700: queue moves below, no overflow | User manually verified, passed |
| 6 | Queue click, previous/next, cross-clip global seek | User manually verified, passed |
| 7 | Sequential, loop, random modes and queue highlight | User manually verified, passed |
| 8 | Open/close player 10 times: no black screen, crash or leftover audio | User manually verified, passed |

This supersedes the "not verified" list in section 5 for these behaviors. Items in section 5 outside this list (for example real-window screenshots) remain unverified.

## 6. Manual checklist for acceptance

Please run on a real Windows window with a playlist of at least 3 clips (include one portrait clip and one clip with a custom range).

1. Playlists tab: click selects, double-click plays, right-click menu, 900 and 1280 widths.
2. Management: drag two or more items, Save, reopen; order persists. Reset and Cancel leave saved data unchanged. Leave with unsaved edits shows the prompt.
3. Player at 1280x800: queue on the right, transport centered, current row highlighted and scrolled into view.
4. Player at 900x700: queue below, no overflow, video still dominant.
5. Space, arrows, M, P, I, S, F1, Ctrl+1..9 still work.
6. Click a queue row; use global progress bar seek across clips; switch modes (sequential, loop, random).
7. Open and close the player 10 times, then use the Library tab and screenshot generation to confirm the lifecycle is unaffected.

## 7. Working tree notes

- Part 5 commit includes the dart-format line wrapping that already sat uncommitted in `playlist_playback_screen.dart` (timeout/snackbar calls). It is whitespace and line-break only, verified by diffing with whitespace ignored.
- Still uncommitted and not part of Stage 4: `lib/screens/main_screen.dart` and `lib/widgets/common/app_sidebar.dart` (Stage 3 sidebar button removal), two Stage 2 test files, and about 40 files that differ from HEAD by formatting/line endings only. Untracked logs and screenshots from Stage 3 are also left alone.
