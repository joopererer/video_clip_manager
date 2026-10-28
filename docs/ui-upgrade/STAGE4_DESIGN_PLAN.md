# Stage 4 Design Plan: Playlist Workbench UI Refactor

**Date**: 2026-10-27 (after Stage 3 acceptance)  
**Branch**: `feat/dark-ui-workspace`  
**Baseline for Stage 4**: `af42909` (post-Stage 3)

---

## 1. Scope & Objectives

### 1.1 Target Screens/Tabs

1. **PlaylistsTab** (`lib/screens/tabs/playlists_tab.dart`):
   - Unified header (search, sort, new playlist, refresh)
   - Playlist cards: thumbnail (visual indicator of contents), title, clip count, total duration, quick actions (play, edit, delete, export)
   - Grid/list toggle (stage 2 achieved grid; verify responsive at 900/1280 px)
   - Multi-select keyboard support (only if safe per stage 3 learnings)
   - Selected / hovered / playing states

2. **PlaylistManagementScreen** (`lib/screens/playlist/playlist_management_screen.dart`):
   - Compact summary: playlist title, total clips, cumulative duration, actions (save, cancel, reset)
   - Queue rows: drag handles, clip thumbnail, title, time range (IN–OUT), length, tags, delete button
   - Timeline view: proportional visual timeline, showing actual clip durations and cumulative position
   - Insertion indicator (when dragging): clear visual feedback of where the clip will be inserted
   - Dirty state tracking (Save/Cancel/Reset buttons disabled/enabled based on changes)
   - Transactional: changes are drafts until Save; Cancel/Reset discards without persisting

3. **PlaylistTimelineView** (`lib/widgets/playlist_timeline_view.dart`):
   - CustomPainter-based timeline (similar to clip editor's `ClipRangeTimeline`)
   - Shows all clips in the playlist as proportionally-sized segments (accounts for real durations)
   - Minimum visual width for tiny clips (e.g., 2 frames = ~80 ms at 24 fps) remains readable
   - Display actual time (not clip index) as tooltip/label on hover
   - Interaction: hover shows segment tooltip, click seeks playback (if playback screen is active), drag reorders (if management screen)
   - Handles zero-duration clips gracefully

4. **PlaylistPlaybackScreen** (`lib/screens/player/playlist_playback_screen.dart`):
   - Large video player (dominates top/left area)
   - Centered transport controls: play/pause, prev/next clip, mute, seek/nudge buttons
   - Current position / total duration in the playlist (not per-clip)
   - Compact queue panel: clip rows, current/next/previous indicators, optional scroll to current
   - Optional: thumbnail preview on hover for queue items

---

## 2. Design Tokens & Layout Principles

### 2.1 Dark Workspace Palette

- **Background**: `#171A20`
- **Sidebar**: `#1E222B`
- **Surface**: `#252A34`
- **Elevated**: `#303644`
- **Accent**: `#8B7CF6` (violet)
- **Text**: `#F1F2F6`
- **Spacing**: 4/8/12/16/24 px (4-unit grid)
- **Radius**: cards ~12 px, modal ~16 px

### 2.2 Responsive Breakpoints

- **Wide (≥ 1280 px)**: Side-by-side layout (player + queue), two-column management
- **Standard (1000–1279 px)**: Stacked or flow layout, queue below player
- **Narrow (900–999 px)**: Single column, queue in drawer/tabs, no overflow
- **Minimum (900 px)**: Grid/list cards still render, no horizontal scroll at this width

---

## 3. Invariants to Preserve

### 3.1 Player Lifecycle

- **Single Player instance**: One `Player` per screen lifetime (initState create, dispose destroy).
- **prepareForPlayback() call**: Before creating visible Player, call `ScreenshotService().prepareForPlayback()` to prevent GPU resource conflicts.
- **PreviewService pause/resume**: Pause on entry (`pauseGlobalPreGeneration()`), resume on exit (`resumeGlobalPreGeneration()`).
- **No extra Players**: No hover previews, no parallel screenshot jobs; use `PreviewService().getNearestKeyframe()` for timeline hover.

### 3.2 Soft Clipping Semantics

- Clips remain metadata-only (IN, OUT points as milliseconds relative to source video).
- No transcoding, no export, no modification of source file.
- Playlist items are references: `PlaylistItem { id, clipId, order, customStartTime?, customEndTime?, duration? }`.
- Reordering changes `order` only, not clip data.

### 3.3 Transactional Edits (PlaylistManagementScreen)

- Form state is a local draft (in-memory copy of playlist).
- Save button persists to `AppState.updatePlaylist()` and returns.
- Cancel button discards draft without saving.
- Reset button reverts to last-saved state.
- Unsaved-changes prompt on back button.

### 3.4 Millisecond-Accurate Duration Calculation

Two different durations exist. Do not mix them.

- Source clip length = `clip.endTime - clip.startTime`. This is the saved clip, in source-video time.
- Playlist effective duration = `PlaylistItemWithClip.effectiveDuration` = `item.getDuration(clip)`. It uses `customStartTime`/`customEndTime` when BOTH are set, otherwise the source clip length.
- Playlist total duration (stage 4 displays) = SUM of `effectiveDuration.inMilliseconds`. Do NOT use `Playlist.totalDuration`, which sums the cached nullable `item.duration` and can disagree.
- Current accumulated position = sum of effective durations before the current item + (player position - item range start), clamped to `[0, effectiveDuration]`. Player position is source time; accumulated time is playlist time.
- No integer-second rounding in new code (store and compute in milliseconds).
- Known pre-existing gap: playback uses `customStartTime ?? clip.startTime` and `customEndTime ?? clip.endTime` independently, while `getDuration` needs both. They differ only if exactly one custom time is set. Recorded in STAGE4_AUDIT.md, not changed.

### 3.5 JSON Persistence

- No schema change: `Playlist` remains `{ id, name, description?, createdAt, updatedAt, items }`.
- `PlaylistItem` remains `{ id, clipId, order, customStartTime?, customEndTime?, duration? }`.
- No migration logic needed.

---

## 4. Current Code Status

### 4.1 PlaylistsTab (`lib/screens/tabs/playlists_tab.dart`, ~1225 lines)

**Current state**:
- Header with search, sort dropdown, new/import/export actions.
- Playlist cards in a grid/list with selection and hover states.
- Empty state placeholder.
- Dialog for create/edit playlist.

**Issues / TODOs**:
- (TBD after audit)

### 4.2 PlaylistManagementScreen (`lib/screens/playlist/playlist_management_screen.dart`)

**Current state**:
- (TBD after audit)

**Issues / TODOs**:
- (TBD after audit)

### 4.3 PlaylistTimelineView (`lib/widgets/playlist_timeline_view.dart`)

**Current state**:
- (TBD after audit)

**Issues / TODOs**:
- (TBD after audit)

### 4.4 PlaylistPlaybackScreen (`lib/screens/player/playlist_playback_screen.dart`, ~1600+ lines)

**Current state**:
- Full-screen playlist player.
- Player creation, stream listeners, transport controls, queue display.
- Clip navigation (prev/next), transition between clips.
- Error handling and resource cleanup.

**Known lifecycle**:
- Calls `PreviewService().pauseGlobalPreGeneration()` and `ScreenshotService().prepareForPlayback()` in `_bootPlaylistPlayer()`.
- Waits for `ScreenshotService().whenIdle()` before disposing the player, then calls `markReady()`.
- Does NOT call `PreviewService().resumeGlobalPreGeneration()` (checked by search). Pre-existing, not changed in stage 4.

**Issues / TODOs**:
- (TBD after audit)

---

## 5. Stage 4 Implementation Roadmap

### Phase 5a: Audit & Analysis (Read-only)
- [ ] Read and analyze each target file (no edits)
- [ ] Identify current UI structure, state management, component hierarchy
- [ ] Note any pre-existing bugs or cosmetic issues
- [ ] Document layout responsiveness at 900, 1000, 1280 px

### Phase 5b: Design & Wireframe (Documentation)
- [ ] Create component tree and layout mockup (text or markdown diagrams)
- [ ] Specify new widget hierarchy for each screen
- [ ] Identify reusable components from Stage 3 (timecode field, timeline view, key handler)
- [ ] Document any new utilities or helpers needed

### Phase 5c: Implement Incrementally (PRs)
1. **Shared widgets & utilities**: Extract common patterns (card base, action buttons, etc.)
2. **PlaylistsTab refactor**: Header, card layout, selection/hover states
3. **PlaylistManagementScreen & PlaylistTimelineView**: Queue management, timeline, drag-drop
4. **PlaylistPlaybackScreen refactor**: Transport controls, queue panel, responsive layout
5. **Polish & regression**: Test at 900/1000/1280 px, keyboard/mouse, edge cases

### Phase 5d: Test & Verify
- `dart format` (modified files)
- `flutter analyze` (no new errors/warnings vs. baseline)
- `flutter test` (new tests for playlist logic, edge cases)
- `flutter build windows --debug`
- Manual verification on real Windows device (6 categories similar to Stage 3)

### Phase 5e: Deliver
- Commit(s) with clear messages
- Real Windows screenshots (at least 1280×800 and 900×700)
- Test results and coverage notes
- `STAGE4_REPORT.md` documenting all changes
- **Await acceptance**; do NOT auto-advance to Stage 5

---

## 6. Notes

- Stage 3 lifecycle observations (theoretical race conditions) are documented but not fixed.
- No changes to `AppState`, data models, JSON schema, or other screens (Library, Videos, Clips tabs, Clip Editor, Clip Playback).
- Font sizes, spacing, and color tokens follow Stage 1 dark theme (`AppColors`, `AppTypography`, `AppSpacing`).
- Keyboard shortcuts and focus safety (Stage 3 learnings) apply where applicable (e.g., queue search if added, but not forcing multiselect).

---

**Next step**: Begin Phase 5a (audit) by reading each file in detail.
