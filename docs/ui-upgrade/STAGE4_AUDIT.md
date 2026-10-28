# Stage 4 Audit: Playlist Workbench

Baseline: HEAD `af42909` on `feat/dark-ui-workspace`. Read-only audit. No lib code changed yet.

## Coverage

Read in full: `playlists_tab.dart` (1224 lines), `playlist_management_screen.dart` (523), `playlist_timeline_view.dart` (340).
`playlist_playback_screen.dart` (2568 lines): read lines 1-600 and 1432-1800 only. Lines 600-1431 (position listener, next/previous, shuffle generation) and 1800-2568 (queue rows, progress bars, hover preview) are NOT yet read. Findings for that file are partial.
Models and AppState playlist methods were read (`models.dart` PlaylistItem/Playlist, `app_state.dart` 1049-1150).

## Data model facts (verified)

- `PlaylistItem { id, clipId, order, customStartTime?, customEndTime?, duration? }`. Times serialize as milliseconds.
- `PlaylistItem.getDuration(clip)` uses custom times only when both are set, else `clip.endTime - clip.startTime`.
- `PlaylistItemWithClip.effectiveDuration` = `item.getDuration(clip)`.
- `Playlist.totalDuration` sums the cached `item.duration` (null counts as zero). It does not use `effectiveDuration`. The tab header and cards use this value, the management screen and timeline use `effectiveDuration`. The two can disagree.
- `AppState.updatePlaylist(id, {name, description, items})` can replace all items in one call.
- `reorderPlaylistItems(id, old, new)` applies the Flutter-style `newIndex -= 1` adjustment, then rewrites `order` using `items.indexOf(item)`.

## PlaylistsTab

- Grid uses `crossAxisCount: 6` fixed. At 900 px this gives very narrow cards. Needs a width-based column count.
- Header is a single `Row` with stats `Wrap` plus three labeled action boxes. Overflow at 900 px not verified.
- Card tap both selects and starts playback (`_playPlaylist`). Easy to start playback by accident. Needs a decision: single tap select, double tap or play button to play.
- Grid card has two near-identical action button blocks (empty vs non-empty). Hard-coded `Colors.white` / `Colors.black` in thumbnail overlays.
- Per-card `getPlaylistItemsWithClips` is called in build. Acceptable now, noted for performance.
- Already uses Stage 1 tokens (`context.appColors`, `AppRadius`), so it is partly themed.
- `_playPlaylist` calls `PreviewService().pauseGlobalPreGeneration()` and `ScreenshotService().prepareForPlayback()` before pushing. The playback screen calls both again in `_bootPlaylistPlayer`. Existing behavior, keep as is.
- Delete confirmation exists. Import/export dialogs are separate widgets, out of scope.

## PlaylistManagementScreen

Not themed: uses `Colors.purple.shade50`, `Colors.blue.shade*`, `Colors.grey.shade*`. Will look wrong on the dark theme.

Transaction logic issues (verified by reading):
1. `_saveChanges` applies removals, then reorders with a loop that calls `reorderPlaylistItems` once and `break`s. After the first mismatch it stops, so a draft with more than one move is not fully persisted. It also passes `i` as `newIndex` into a method that subtracts 1 when `old < new`, so the landing index can be off by one.
2. No back-navigation guard. Leaving with unsaved changes discards them silently. There is no Cancel button, only Reset and Save (shown only when `_hasChanges`).
3. `_refreshFromExternalChanges()` is called inside `build()` and can call `setState`. `didChangeDependencies` also calls it. Risky pattern.
4. `_isEditing` is a `final bool` always false, so the "not editing" branches always run.
5. Duration shown as `m:ss` from `inSeconds`. Drops milliseconds, and shows `90:00` style for long lists (no hours).
6. Row tap shows a SnackBar with a TODO. `_scrollToItem` is an empty TODO.
7. "Play" in the app bar builds a copy playlist from the draft and pushes the playback screen without saving. This is useful behavior (preview of draft) and must be kept.
8. Remove has a confirmation dialog. Removal is only applied to AppState on Save.
9. Rows use `ReorderableListView` with default handles. Reorder is draft-only until Save.

## PlaylistTimelineView

- Light-theme colors (`Colors.grey.shade100/300`, white text). Not dark-theme ready.
- Widths come from `Expanded(flex: (ratio * 1000).round().clamp(1, 1000))`. A clip under 0.05% of the total gets flex 1 (acceptable) but flex is relative, so there is no guaranteed pixel minimum. A 100 ms clip in a 1 h list is far below 1 px. Requirement: minimum visual width with real time shown.
- Zero-duration items get flex 1. Total of zero gives ratio 0, handled.
- Drop handling in `onAcceptWithDetails` converts `details.offset` with `globalToLocal` and maps to an item by cumulative width. This is approximate (offset is the feedback's top-left, not the pointer). No insertion indicator. Reorder is off in both current callers (`enableReorder` false in tab; management screen does not pass `onReorder`).
- Item text only appears above 40 px width. No hover tooltip with the real in/out time.
- Color per clip comes from `clip.id.hashCode`. Keep so colors stay stable.

## PlaylistPlaybackScreen (partial)

- Lifecycle matches the invariants: `_bootPlaylistPlayer` calls `pauseGlobalPreGeneration`, `ScreenshotService().prepareForPlayback()`, then creates one `Player` and `VideoController`. `dispose()` cancels subscriptions, waits on `ScreenshotService().whenIdle()`, disposes the player, then `markReady()`. Do not change.
- Timeouts come from `AppState` (`openTimeoutSeconds`, `seekTimeoutSeconds`, `playTimeoutSeconds`).
- Layout is a `Column`: video (`flex 3`), optional info block, timeline (`flex 2`). The timeline area is a `ListView` of items, not a proportional timeline. Info block is a dense text row plus a 40 px progress bar.
- Keyboard: `RawKeyboardListener` with `keyLabel` switch (Space, R, arrows/A/D, M, P, I, S, F1, Ctrl+digits). It has no text input to conflict with today. If I add any text field, the Stage 3 focus guard approach is needed.
- Uses `Colors.blue/purple/orange/grey` directly. Not themed.
- Position math, random/loop generation and the global progress bar are in the unread ranges. Accumulated playlist time vs source time must be checked there before any change.

## Risks

- Fixing the Save logic (item 1 above) changes persistence behavior. It stays inside current JSON fields, but it fixes a real bug, so I will report it separately.
- Playback screen is 2568 lines and mostly logic. UI rework must not touch the stream listeners, seek loop or generated-playlist code.
- No tests exist for playlist draft logic yet (not checked beyond file names; will grep before writing new ones).

## Proposed order

1. Extract pure draft logic (apply reorder/removal, dirty check, total duration in ms) with unit tests.
2. Management screen: dark theme, summary, Save / Cancel / Reset, back guard, correct save via `updatePlaylist(items:)`.
3. Timeline widget: dark theme, minimum pixel width, hover time label, insertion indicator, keep color rule.
4. Tab: responsive columns, safer tap behavior, header at 900 px.
5. Playback screen: layout and theming only, after reading the unread ranges.

## Open questions for the user

- Card tap in the Playlists tab currently starts playback. Change to select only (play via button or double tap)?
- OK to fix the multi-move Save bug (item 1) as part of this stage?

## Supplementary audit (after user decisions)

Coverage is now complete: `playlist_playback_screen.dart` lines 600-1431 and 1800-2568 were read.

### Product decisions received
1. Playlist card: single click selects, double click plays, play button plays, right click opens a menu. Existing play/edit/delete/import/export stay.
2. Fix the multi-move Save bug in `PlaylistManagementScreen`, with a transactional draft, one commit via `AppState.updatePlaylist(id, items: ...)`, no JSON change.

### Playback screen findings (code reading only, nothing run)
- Time bookkeeping: `_totalDuration` sums `effectiveDuration` (ms). Current item progress uses `position - (customStartTime ?? clip.startTime)` clamped to the item range. Source time and playlist time are kept apart. OK.
- Mixed rule: range start/end use `custom ?? clip` per side, but `effectiveDuration` needs both custom times. Only differs if exactly one custom time is set. Not changed.
- `_getGlobalProgressPercentage` and its zero check use `inSeconds`. A total under 1 s shows 0%. Display text `_formatDuration` drops milliseconds. UI-only; may format with ms in the new layout but the underlying state is untouched.
- Loop mode: `_playedItems` only adds an index once, so `completedRounds` (`_playedItems.length ~/ n`) is 0 until all items were played once. Existing semantic, not changed.
- `_generateRandomPlaylistExcluding` calls `Random().nextInt(length - 1)`, which throws for a single-item list when that item is first. `_playNextItem` in random mode reaches it only when all items are played. Existing risk, not changed; noted for the report.
- Hover preview uses `PreviewService().getNearestKeyframe` (no extra Player). Keep.
- Global seek across clips stores `_pendingGlobalSeekTime` and calls `_jumpToClip`; `_initializePlayer` consumes it. Keep.
- `_initializePlayer` has several early `return`s after timeouts that leave `_isPlayerReady` false. Existing, not changed.
- Stage 4 will only change `build()` and the widgets it uses (`_buildPlaylistTimeline`, progress bar painting, colors). Stream listeners, `_initializePlayer`, next/previous and generation code stay untouched.

### Lifecycle impact check (ScreenshotService / PreviewService / Media Kit)
- Only `PlaylistPlaybackScreen` creates a Player in this stage. Creation stays in `_bootPlaylistPlayer`, disposal stays in `dispose()`.
- `playlists_tab.dart` `_playPlaylist` keeps `pauseGlobalPreGeneration()` + `prepareForPlayback()`. Double click, play button and context menu will all route through that same method.
- The management screen "play" button pushes the playback screen directly (no tab-side pause). The playback screen does its own pause and `prepareForPlayback()`, so behavior is the same as before. Kept.
- `resumeGlobalPreGeneration()` is never called after playlist playback (search result: only `clips_tab.dart` and `clip_editor_screen.dart` call it). Pre-existing. Not changed; follow-up item.
- Timeline hover labels will not create Players or screenshot jobs.

### Data-loss risk found in the draft design
- `getPlaylistItemsWithClips` drops items whose clip no longer exists. If Save wrote only the visible draft with `updatePlaylist(items:)`, those orphan items would be deleted silently. The new draft keeps orphans and appends them after the visible items on commit.
- Item ids can be empty or duplicated in old data (the tab already keys by list index for that reason). `_removeClipIds` + `removePlaylistItem(id)` removes every item sharing an id. The new draft removes by position, not by id.
- `AppState.reorderPlaylistItems` rewrites `order` with `items.indexOf(item)`, which is wrong for equal items. New commit writes `order = index` directly.
- Saving through `updatePlaylist(id, items: ...)` leaves name, description and createdAt unchanged (they pass null) and refreshes `updatedAt`.

### Git state before implementation
- HEAD `af42909`, branch `feat/dark-ui-workspace`, nothing staged.
- Uncommitted changes in files stage 4 will touch or depend on, all formatting-only as far as I checked: `lib/data/models.dart` (2 `firstWhere` blocks), `lib/screens/player/playlist_playback_screen.dart` (timeout/snackbar wrapping). `lib/data/app_state.dart` also has a formatting-only-looking diff (68 lines; not fully reviewed). Stage 4 will not edit `models.dart` or `app_state.dart`.
- Other uncommitted files (tests, docs, logs, `models/`, zip, png, `.github/.github/`) are unrelated and will not be staged. Each commit uses explicit paths.
- No existing playlist tests (`git ls-files test` has none).
