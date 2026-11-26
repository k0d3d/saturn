# Changelog

## Unreleased

- Added a fullscreen, borderless card workspace: asymmetric five-card grid, exposed stack layers for volume, attention dot, session-local last-viewed tick, and animated expand/collapse focus.
- Removed the compact/collapsed workspace and hover-to-open behavior; the bar now opens the full workspace directly.
- Replaced filled button rows with text tabs, hover-only task actions, inline add fields and a clickable Focus timer dial.
- Deferred heavy panes: Notes and Connections load on first open, Mail loads on first expansion, and the frost capture only runs while the workspace is visible.
- Fixed the tint layer painting over the entire workspace; the backdrop is now below the cards, so text and surfaces keep their contrast.
- The daily note now acts as a hub for library notes dated to that day, with a one-click `@Title` insertion that becomes a graph mention.
- Added an optional frosted backdrop: one screencopy captured on open, blurred once, toggleable from the top bar.
- Documented the visual contract, motion rules and performance budget in `UX.md`.
- Added `saturn data set-tags <id> "a,b"` so agents can tag tasks without editing `workspace.json`; tags become tag nodes and `tagged` edges on the next graph refresh.
- Tasks now group by creation date with quiet headers, use a 40/60 list/detail split, and gain minimal hairline borders. The detail pane leads with the full title and body instead of truncating like the list.
- Replaced text glyphs with theme-tinted Lucide SVG icons for focus, edit, archive and restore; the task pane now lists graph-connected tasks and notes, and tags filter the list when clicked.
- Expanded Tasks is now a full-height two-pane split: a darker 40% list side, a borderless 60% detail side on the card itself, and one hairline divider. Added a `Tags` tab with a frequency-sized tag cloud that filters the list.
- A focused card now takes 84% of the workspace; the remaining strip is a `SWITCH` rail of the other cards as clickable mini cards with live captions.
- Escape is a window shortcut, so it closes the workspace even when a text field has focus.
- New Saturn brand mark generated with Recraft V3 SVG on Replicate; the shell uses a mipmapped PNG so the mark stays crisp at header size.
- The header tagline now rotates through twenty aphorisms and attributed quotations about time, attention and work. Removed the last-viewed bookmark tick from card chrome.
- Every card heading now carries its icon. Notepad was rebuilt around a larger daily editor, compact today's-note pills and an expanded board of tinted note cards; the old full-width linked-note rows are gone.
- Notepad has Write / All notes / full-card Note views; wiki links render as links in the reading view and are stripped from previews.
- Saturn now opens on the focused monitor only and dismisses itself when that monitor's workspace changes.

## 0.8.0

- Renamed the project to **Saturn** and the plugin id to `k0d3d.saturn`; `saturn` is the new command, with deprecated `omapulse` and `omaowl` aliases for one release.
- Migrated local data to `~/.local/share/saturn/` with schema 2: dated/archivable tasks, a tagged note library, sync metadata and an insights hook. Original data is backed up, never deleted.
- Migrated private credentials from `~/.config/omaowl` and `~/.config/oma-pulse` into `~/.config/saturn`, preserving permissions.
- The shell now watches the workspace file and adopts external edits without echoing its own atomic writes back.
- Tasks are now local-only: Todoist, reminders and the task-source switch were removed.
- Added Today / Upcoming / All / Completed / Archive views; completed tasks stay visible and archived tasks can be restored.
- Added local due dates (`tomorrow`, `today`, `next Mon`, `YYYY-MM-DD`) and a `saturn tasks` shell command.
- Added a tagged, dated and searchable Notes library alongside the daily Notepad, with pin/archive/restore and a `saturn notes` shell command.
- Ships an `i18n/en.json` catalog for the new Notes UI strings.
- Removed Messages, Assistant, Codex, Voxtype, Grok/Hey Saturn voice and the Blip/Beeper bridge; the command bar is now a local task/notes launcher. Assistant work moves to OpenCode.
- Deprecated `messages`, `assistant`, `voice*` and `grok*` commands now print a pointer to OpenCode.
- Added `saturn data` for live agent reads/writes and an offline, locked `workspace_api.py` fallback.
- Added an installable OpenCode skill (`skills/saturn/SKILL.md`) with the data schema, command reference and safety rules.
- Added a human-readable Markdown mirror at `~/Documents/saturn/` with local Git commits, `saturn vault` commands, local-first conflict logging and tombstones.
- Added two-way calendar sync: Google Calendar write scope, a CalDAV adapter for cPanel endpoints, local events in the workspace, `saturn calendar` commands and local-first conflict handling.
- Added cPanel IMAP setup guidance and explicit CalDAV connection fields in Connections.
- Hardened calendar sync: Google events use stable provider IDs; local edits are pushed once via snapshots; two-sided changes keep both versions, record a single conflict and resolve when the user edits locally; failures report `ok: false`.
- CalDAV now preserves resource URLs and ETags, resolves absolute hrefs only inside the configured HTTPS calendar and honours `TZID` time zones; archived events are no longer deleted from the remote calendar.
- Fixed a provider race that could show a misleading “Unknown provider.” error instead of the real connection error.
- Google Calendar now requests both `calendar.events` and `calendar.readonly`; the events scope alone cannot read calendar metadata and caused a 403. Reconnect once to grant both.
- Added a local SQLite knowledge graph at `~/.local/share/saturn/graph.sqlite` with `saturn graph` commands, wiki links, tag hubs, agent-created typed edges, path/neighbour queries, explicit `forget` and backups. Edges are authoritative; workspace content stays in `workspace.json`.
- Added `@` mentions as a fourth edge source: unique-title or exact-key resolution with longest-prefix matching, plus `saturn graph backlinks`.
- Added a documentation page at `/docs.html` covering notes, links, the graph and agent use; fixed stale Oma Pulse branding and version on the landing pages.
- Updated launcher, icon, app-menu entry, manifest, documentation and website copy for the new name.

## 0.7.1

- Fixed Todoist helpers waiting for input EOF, which could leave syncing stuck and task checkboxes disabled.
- Read each JSON-line request immediately and bound helper execution to 90 seconds, with a retryable timeout message.
- Added a regression check that holds stdin open and verifies the request still completes.

## 0.7.0

- Added a Connections screen with persistent task, mail and calendar choices.
- Added beta Gmail and Outlook inbox adapters with user-owned OAuth setup, plus TLS IMAP with app-password setup.
- Added beta direct Google Calendar support, including calendar timezone, recurring and multi-day events.
- Preserved HEY, Todoist and OmaCal integrations; local tasks also work with assistant commands.
- Added full weekday names to calendar headings.
- Added connection setup documentation and updated the public website with supported choices and setup requirements.
- New adapters have automated protocol/UI coverage; live provider verification requires configured accounts.

## 0.6.0

- Renamed Oma Owl to **Oma Pulse**, with new branding, a pulse icon and an `omapulse` launcher.
- Retained old commands, plugin identity and data paths for a seamless upgrade.
- Added a fifth website preview card for HEY email: sample messages, open, mark read and Undo.
- Updated public URLs and added a redirect from the old website.
- Added Kosta Hantzis’s social links to a shared footer on every page, including the branded 404 page.

## 0.5.0

First public Omarchy release.

- Native bar plugin, compact workspace, full-screen workspace and command bar.
- Local tasks, daily notes, focus sessions, stopwatch and activity insights.
- Optional Todoist, OmaCal, HEY, Codex and Voxtype connections.
- Full task titles, direct Todoist task links, and event links to the full calendar.
- User-local installer, application launcher, Git-managed updates and backup-preserving prototype migration.
- Safe first-run workspace creation and remembered task-source selection.
- Responsive landing page with an interactive, account-free sample workspace.

## Earlier versions

Versions 0.1–0.4 were local prototypes, not public releases.
