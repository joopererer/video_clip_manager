# Video Clip Manager — AI Agent Working Rules

## Scope
Upgrade the existing Flutter Windows desktop application UI to a cohesive dark media workspace. Work **in the actual repository at v1.0.1-dev**, never replace it wholesale with the reference prototype. Source of truth for current functionality is the repository, not the visual prototype.

## First action: audit
1. Identify `pubspec.yaml`, app entry point, routes, theme, screen widgets, Provider state, data models, playlist editing state, Media Kit integration and player/resource services. Discover actual filenames instead of assuming them.
2. Record baseline `flutter --version`, `flutter pub get`, `flutter analyze`, and available tests; if Windows runner is available, record desktop build/run status.
3. Produce `docs/ui-upgrade/CODEBASE_AUDIT.md` documenting files/components to modify, invariants, risks and proposed migration. Do not start large-scale changes before audit.
4. Make changes on `feat/dark-ui-workspace` branched from `v1.0.1-dev`; avoid unrelated modifications.

## Immutable behavior
- Soft clipping is metadata only: keep original video intact, no transcoding, no cut/export of media required to save a clip.
- Preserve existing serialized JSON formats and reading of existing project data. No silent migrations.
- Preserve Provider architecture, current media_kit player lifecycle, ScreenshotService serialized operations, timeouts, ready timers, file checking, cleanup, and existing persistent preferences.
- Do not introduce a new player implementation, unmanaged Media Kit instances, or parallel screenshot/seek jobs as part of cosmetic UI changes.
- Keep time range semantics and units consistent (in/out, duration); do not conflate source time with playlist accumulated time.
- Playlist management changes remain local drafts until Save; Cancel/Reset discards edits, with unsaved change prompt when needed.
- Protect user assets and data from irreversible deletion without confirmation. Avoid breaking Windows paths, Unicode file names and vertical videos.

## Design direction
- Desktop-first dark Material 3 media workspace, neutral surfaces, one primary violet accent.
- Tokens: background `#171A20`, sidebar `#1E222B`, surface `#252A34`, elevated `#303644`, accent `#8B7CF6`, text `#F1F2F6`.
- Spacing scale 4/8/12/16/24; cards radius ~12px, modal ~16px, top toolbar ~60px, sidebar ~208px collapsible to ~64px.
- Use mouse hover, secondary-click context menus, keyboard/focus support, semantic tooltips, accessible contrast, readable text sizes.
- Do not over-decorate with saturated gradient backgrounds, excessive shadows, or per-card button overload.
- Responsive at 900/1280/1600 logical px widths; avoid overflows at 900px.

## Page requirements
**Library:** unified shell/header; search/filter/sort; grid/list; responsive 16:9 thumbnail media boxes for landscape/portrait sources; selected/hovered/favorite/playing states; obvious add-to-playlist and quick play/edit; keyboard multiselect only when safe; preserve existing ratings, tags, favorites, counts.
**Clip editor:** player dominates left/top; properties to side when space allows; timecode IN/OUT/duration with millisecond precision; selectable timeline with legal boundaries; I/O shortcuts only if they don't collide with text editing; keyboard seek/frame step only when actually supported and accurate; existing clip preview/save semantics unchanged.
**Playlist management:** compact summary and proportionally sized timeline, including min visual width for tiny clips with accurate actual time displayed; queue rows with drag handles, insertion indicators; save/cancel/reset with dirty-state; keep edits transactional.
**Playlist player:** large video, centralized transport controls, current/total playlist progress, compact queue and clear selected/playing state.
**Clip player modal:** prioritize video; compact playback toolbar; collapsible metadata/details; quick favorite/rating/edit navigation.

## Engineering approach
- Incremental PRs: (1) theme + shared widgets, (2) library, (3) clip editor, (4) playlists/player, (5) polish and regression checks.
- Make widgets reusable but avoid unnecessary new architectural layers; follow actual repository conventions.
- Bind to existing AppState and services. Sample models/widgets from `reference/visual_prototype_only.zip` are visual ideas, not production modules and must not be copied over `lib/main.dart`.
- `dart format` touched files; run `flutter analyze` and available tests; add widget/unit tests for timecode parsing, range bounds, playlist transactional edits, filtering and responsive layout where feasible.
- When the agent cannot run a Windows integration test, report explicitly rather than claiming pass.

## Deliverables per stage
1. Files changed + concise explanation.
2. Screenshots at 1280×800 and 900×700 if runner available; label mock/sample media as placeholders.
3. Checks executed and results.
4. Behavior invariants verified and known risks.
5. Small, reviewable commits; no unrelated refactors.

## Stop-and-ask conditions
Request approval before changing JSON schema, switching player libraries, modifying native Windows runner, performing mass deletion, adding significant dependencies, or altering clip timing semantics. Otherwise progress autonomously stage by stage.
