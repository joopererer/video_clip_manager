# Dark Workspace — UI specification (v1)

## Information architecture
Sidebar: Clips, Original Videos, Playlists, Favorites; Settings/Help in bottom region. Top region: page title, context actions. Avoid vertical navigation duplication.

## Tokens
Colors: `background #171A20`, `sidebar #1E222B`, `surface #252A34`, `surfaceElevated #303644`, `primary #8B7CF6`, `textPrimary #F1F2F6`, `textSecondary #A5ACBA`, `border #3A404C`, `success #7BD6B6`, `warning #FFBC70`, `danger #F07887`.
Spacing: `4, 8, 12, 16, 24, 32`; typography: body 13–14, page 22–24, captions 11–12; duration/timecode use tabular numerals. Focus ring distinct from hover and selection.

## Desktop patterns
Grid cards: thumbnails 16:9, cover or letterbox respecting subject and aspect ratio, duration bottom corner, one-line title, favorite/rating summaries. Hover reveals primary play and secondary menu; right click context. Maintain accessibility with keyboard equivalents.
List rows: thumbnail, name, source, in/out, duration, tags, rating, favorite, overflow menu; adaptive hide optional columns at small widths.
Search/filter/sort pinned to a compact toolbar; show active filters and visible/total count.
Clip editor: two-column player:metadata at >=1100px; stacked narrower. Bottom timeline with ticks and IN/OUT; separate precise input fields. Guard in < out and positions within source duration. No implied frame accuracy if player can't guarantee it.
Playlist: summary, time ruler, proportional blocks, list reorder with insertion feedback; label short clips where too narrow to display text; show true total time with one single duration formatting utility.
Playlist player: clear transport and navigation; avoid giant blank area beneath player. Adjustable queue panel where feasible.

## UX states required
Loading / no library / no search results / missing source file / broken thumbnail / player open timeout / seek timeout / screenshot timeout / empty playlist / dragging / unsaved changes / save success or failure / keyboard focus.

## Non-goals
No transcoding, waveform extraction, new persistence layer, database migration, full professional NLE editor, mobile overhaul, and major state management rewrite.

## Sample acceptance scenarios
- User opens existing JSON data; all clips/playlists and tags/ratings survive and display correctly.
- Search combined with tag and favorite filters updates count and is persistent according to current app behavior.
- Create a clip 00:09.000–01:30.000 (duration 01:21.000) without modifying source video.
- Playlist 00:08 + 06:06 + 01:20 totals 07:34; drag reorder changes draft timeline, Reset restores original, Save commits once.
- Windows path with Chinese characters opens source file.
- Repeatedly open/close players and switch videos; no surviving listeners, timer leaks or native crashes.
- 900px wide UI does not overflow and keyboard focus remains visible.
