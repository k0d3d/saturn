# Saturn

**Your day, within reach.** A local-first workspace for Omarchy: tasks, focus, daily notes, calendar and mail.

[Website & interactive preview](https://saturn.vercel.app/) · [Visual language](UX.md) · [Releases](https://github.com/k0d3d/saturn/releases) · [Report an issue](https://github.com/k0d3d/saturn/issues)

Saturn runs inside Omarchy's Quickshell desktop. Hover over its bar icon for a quick look, click to pin it, or right-click for the full workspace. It follows your current theme. An application-menu launcher opens the same native workspace. This is an Omarchy Linux plugin, not an Electron wrapper or a cross-platform standalone app.

## Installation

Requires **Omarchy with its plugin-capable Quickshell shell** (tested on Omarchy 4.0.4), Git, Python 3.11+, Qt Quick Controls and `notify-send`. Omarchy supplies the desktop dependencies. Local tasks, notes and focus need no account. Node.js is only used for website development.

```sh
curl -fsSL https://saturn.vercel.app/install.sh | bash
```

[Inspect the installer](install.sh). It clones the public repository, validates the manifest, enables `k0d3d.saturn`, and installs a user-local application launcher. It never uses sudo, changes keyboard shortcuts or includes account credentials.

Alternatively, use Omarchy's plugin manager:

```sh
omarchy plugin add https://github.com/k0d3d/saturn.git --enable
bash ~/.config/omarchy/plugins/k0d3d.saturn/scripts/install-desktop.sh
```

The plugin also initializes its storage when installed directly through the plugin manager. Open **Saturn** in the application menu, or run `saturn`.

### Updating and removing

```sh
omarchy plugin update k0d3d.saturn
```

If a QML dependency remains cached, run `omarchy restart shell` after updating. Your local tasks, notes, credentials and focus history are stored outside the plugin directory.

Disable with `omarchy plugin disable k0d3d.saturn`; remove with `omarchy plugin remove k0d3d.saturn`. To remove launcher files too, remove `~/.local/bin/saturn`, the deprecated `~/.local/bin/omapulse` and `~/.local/bin/omaowl` aliases, `$XDG_DATA_HOME/applications/saturn.desktop` and `$XDG_DATA_HOME/icons/hicolor/scalable/apps/saturn.svg` (data home defaults to `~/.local/share`). User data is deliberately retained.

Upgrading from Oma Pulse (`kosta.omaowl`): remove the old id with `omarchy plugin remove kosta.omaowl` (keeps your data), then install Saturn. On first start Saturn migrates `~/.local/share/omaowl/workspace.json` to `~/.local/share/saturn/workspace.json` (schema 2) with a timestamped backup under `$XDG_DATA_HOME/omaowl-backups/`, and copies private credentials from `~/.config/omaowl` and `~/.config/oma-pulse` into `~/.config/saturn`. The originals are never deleted. For a local prototype, inspect `install.sh` and run `bash install.sh --adopt`. Ordinary installation refuses to overwrite an existing plugin.

### Keyboard shortcut

Bind `saturn command` in your Hyprland bindings using a key you choose. Existing Super+N bindings from the local prototype continue to work; a fresh install does not claim that shortcut. `saturn dashboard` opens the full workspace; Escape closes it, or returns from an expanded card first.

On this workstation, **Super+Alt+N** opens the full dashboard. Its binding is
`o.bind("SUPER + ALT + N", "Saturn full dashboard", "saturn dashboard")`.

## Formerly Oma Pulse / Oma Owl

Version 0.8.0 renames the project to **Saturn** and the plugin id to `k0d3d.saturn`. Data and credentials migrate automatically as described above. The deprecated `omapulse` and `omaowl` commands and IPC aliases keep existing shortcuts working for one release; new shortcuts should use `saturn`. Run the desktop installer once to refresh the app-menu name and icon.

## Connections

Open **Connections** to choose your mail and calendar providers. Tasks are always local and need no account; you can switch between HEY, Gmail, Outlook and IMAP mail, and between OmaCal and direct Google Calendar. See the [connection setup guide](CONNECTIONS.md). New Google/Microsoft adapters are beta and require your own OAuth app registration; live-account sign-in has not yet been verified.

All integrations are optional:

| Connection | Setup | Adds |
| --- | --- | --- |
| OmaCal | Install OmaCal and connect a calendar there | Read-only daily event feed and links to the full calendar |
| IMAP | Connections → TLS server, username and app password | Unread headers, mark read and Undo |
| Gmail / Outlook | Connections → account setup with your OAuth client ID | Unread inbox, mark read and Undo |
| Google Calendar | Connections → Google Calendar OAuth setup | Read-only eight-day feed without OmaCal |
| HEY | Install a compatible `hey` CLI and run `hey auth login` | New for You, mark read and Undo |

Third-party services may require accounts or paid plans. No service subscription is included.

## Interface

Saturn is a single fullscreen, borderless card workspace: Tasks on the tall
left, Notepad and Focus in the middle, Events and Mail on the right. A dot means
attention, exposed layers behind a card show a bounded volume band, and a small
tick marks the last view you opened. Hover `⤢` or press `1`–`5` to expand a
card; `Esc` or `0` returns to the grid. Frost blurs the desktop behind the
workspace once on open and can be turned off from the top bar. See
[UX.md](UX.md) for the full visual contract, motion rules and performance
budget.

The daily note is an index: library notes dated to the selected day appear as
`@Title` rows beneath it. Click one to open it, or use its `@` button to insert
an explicit mention into the daily note.

## Tasks

Tasks are local to this computer. No account is needed and nothing is uploaded.

- **Today** shows overdue and undated tasks plus anything due today.
- **Upcoming** shows future-dated tasks in date order; **All** shows every active task.
- **Completed** keeps finished tasks in view, newest first. The circle reopens a task.
- **Archive** hides a task from every active list. Use ↩ to restore it.
- The add field understands `tomorrow`, `today`, `next Mon` and `YYYY-MM-DD`;
  the **Today** / **Tomorrow** chips and the due field set an explicit date.
- ▶ selects a task for the focus timer. Long titles wrap in full.
- Tasks are stored with `due`, `completedAt`, `archived`, tags and timestamps in
  `~/.local/share/saturn/workspace.json`, so an AI agent can read and update them.
- `saturn tasks` lists tasks; `saturn tasks add "Buy milk tomorrow"`,
  `saturn tasks complete <id>`, `saturn tasks archive <id>`,
  `saturn tasks restore <id>` and `saturn tasks due <id> 2026-11-24` work from the shell.

## Notes

The Notepad card stays as quick daily capture. The **Notes** tab adds a library of titled, tagged, dated notes with full-text search across both the library and daily notes. Notes can be pinned, archived and restored; everything is stored locally in `~/.local/share/saturn/workspace.json`.

From the shell: `saturn notes list`, `saturn notes search "voice"`, `saturn notes add "Title" "Body" "tag1,tag2" 2026-11-24`, `saturn notes update <id> "New title" "New body" "tags"`, `saturn notes pin <id>`, `saturn notes archive <id>`, `saturn notes restore <id>`. `saturn notesOpen` shows the library in the workspace.

## Calendar

Use ‹ / › in the Events card to switch days, and **Back to today** to reset.
Choose the source in Connections: **Google Calendar** (your own OAuth client ID
and secret; needs the Calendar events scope for two-way writes), **CalDAV
(cPanel)** (HTTPS URL, username and app password entered manually), **OmaCal**
(read-only local feed) or **Off**.

Local events can be created with the add row in the Events card; they are stored
in `~/.local/share/saturn/workspace.json` and synced both ways with the selected
provider. `saturn calendar list|add|archive|sync|status` exposes the same data
from the shell. Sync compares each local and remote event against its last
synced snapshot. Two-sided changes preserve both versions for manual resolution
and are listed under `workspace.sync.conflicts`; no remote edit is sent for a
conflicted event. Archiving hides an event locally but does **not** delete it
from the remote calendar. Remote deletions are not propagated to the workspace.
Google Calendar events open in the browser; CalDAV events stay in the workspace.

## Focus and notes

25/50-minute presets, custom minutes, stopwatch, pause/resume and +5 minutes.
A small, square timer notch appears below the top bar while running and the workspace is closed.
Click its time/title to return to the workspace, or pause directly from the notch. It disappears
when paused or finished. Completion sends a desktop notification.
Sessions pause after sleep or a clock gap longer than three seconds. Restarts
restore sessions paused, so unattended time is not counted as active work.

Daily notes autosave. ‹ / › browse older days; Today resets the date.
Ctrl+Enter adds the current line to the selected task source and preserves the note.
Workspace and full-screen views share the same live data.

## HEY mail

The HEY card shows **New for You** from the recent Imbox, preserving HEY’s order. It uses stored
HEY CLI authentication and a websocket watch for live changes, plus refresh on reopening when
stale. Clicking a message opens it in the HEY web app. Listing mail never marks it seen.
Up to 50 recent Imbox entries are loaded; full mail remains available through **Open HEY**.

## Theme

All surfaces, text, accent colors and fonts bind to Omarchy’s live theme. Cards
are borderless and use theme-tinted surfaces; the workspace, command bar and
focus notch have square corners.

## Storage

`${XDG_DATA_HOME:-~/.local/share}/saturn/workspace.json` is the local-first source of truth:
tasks (including due dates and archived items), daily notes, the tagged note library,
timer state, activity, sync metadata and insights. It uses schema 2 and is migrated
automatically from older versions. Copy it to back up or export. Writes are atomic;
notes save after 300 ms and active timers checkpoint about every five seconds.
The shell watches the file for external edits and ignores its own write events, so an
agent can update data without a shell restart. Invalid saved workspace data is preserved
instead of silently overwritten. Credentials stay separately under
`${XDG_CONFIG_HOME:-~/.config}/saturn/` with private permissions.

## AI agent access

An OpenCode skill lets an agent read and update Saturn's tasks and notes without touching `workspace.json` directly. Install it with `bash ~/.config/omarchy/plugins/k0d3d.saturn/scripts/install-opencode-skill.sh`; it links `skills/saturn/` into `~/.config/opencode/skills/saturn/`.

- With the desktop shell running, use `saturn data <command>` (live, atomic, visible immediately).
- Without the shell, use `python3 ~/.config/omarchy/plugins/k0d3d.saturn/scripts/workspace_api.py <command>` (locked, validated, backed up; refuses to write while the shell is live).

Both print JSON. See `skills/saturn/SKILL.md` for the command reference, data shapes and safety rules. The shell records agent command names in `workspace.sync.audit` — never note bodies or credentials.

## Markdown vault

Saturn mirrors tasks, library notes and daily notes into a human-readable Git repository at `~/Documents/saturn/` (override with `SATURN_VAULT`):

- `tasks/YYYY-MM-DD-<id>.md`, `notes/YYYY-MM-DD-<slug>.md`, `daily/YYYY-MM-DD.md` — each with JSON front matter (`id`, `title`, tags, dates, state flags, timestamps) and a plain Markdown body.
- `saturn vault status` reports the mirror; `saturn vault sync` pulls vault edits and commits changes locally. The shell also pushes workspace changes after ~5 seconds and does a full sync every minute.
- Edits in both places are local-first: the newer `updatedAt` wins, two-sided changes keep the local version and are logged in `workspace.sync.conflicts` and `conflicts.md`. Deleting a vault file archives the local record and writes a tombstone rather than deleting data.
- No credentials are written to the vault, and nothing is pushed to a remote automatically.

## Knowledge graph

A local SQLite graph at `${XDG_DATA_HOME:-~/.local/share}/saturn/graph.sqlite`
stores relationships between tasks, notes, daily notes, events and tags. Edge
data is authoritative: deleting an item from the workspace does not silently
delete its relationships. Use `saturn graph forget <key>` when you really want
a node and its edges removed, and `saturn graph backup` to snapshot the database.

Nodes use qualified keys: `task:<id>`, `note:<id>`, `daily:<YYYY-MM-DD>`,
`event:<id>` and `tag:<tag>`. Commands also accept a unique, case-insensitive
title instead of a key. Connections come from three sources:

- **Wiki links** — `[[Title]]`, `[[note:<id>]]` and similar references in task
  bodies, library note bodies and daily notes.
- **`@` mentions** — `@Task title` resolves by unique case-insensitive title,
  `@task:<id>`
  is exact. The longest unique title prefix is used, so prose like
  `@Project X tomorrow` works; ambiguous names create no edge.
- **Shared tags** — each tag is a node; items connect to it with a `tagged`
  edge, so co-tagged items are two hops apart.
- **Agent edges** — explicit typed relations added with `saturn graph link`.

Tag and wiki edges are regenerated from workspace content on every graph
command; agent edges are never removed by a refresh. Every command prints JSON:

```sh
saturn graph status
saturn graph reindex
saturn graph link task:abc supports note:xyz "decision behind this task"
saturn graph unlink task:abc supports note:xyz
saturn graph neighbors task:abc 2
saturn graph backlinks note:xyz
saturn graph path task:abc note:xyz
saturn graph list nodes
saturn graph resolve "Project X"
saturn graph forget task:abc
saturn graph backup
```

The graph is local-only, never mirrored into the vault and never sent to a
provider. No credentials are stored in it.

## Commands

```sh
omarchy-shell saturn toggle
omarchy-shell saturn command
omarchy-shell saturn open
omarchy-shell saturn dashboard
omarchy-shell saturn close
omarchy-shell saturn status
omarchy-shell saturn notesOpen
saturn tasks [list|add|complete|archive|restore|due] ...
saturn notes [list|search|add|update|pin|archive|restore] ...
omarchy plugin disable k0d3d.saturn
omarchy plugin enable k0d3d.saturn
```

`open` pins the workspace; `toggle` toggles the command bar, a local quick-capture tool for tasks and notes — no AI service is involved. Use OpenCode for assistant work. `dashboard` opens full screen on the first
display; the workspace's Full screen button uses its own display. Messages, Assistant and all voice/Grok features were removed in 0.8.0; the deprecated commands print a notice instead of running.

Requires Omarchy's Quickshell shell, Qt Quick Controls, Python 3, and notify-send.
OmaCal and the HEY CLI provide optional calendar and mail integrations.

### HEY quick actions

Swipe an email left or click its ✓ button to mark it read in HEY. The widget confirms the remote status, then removes it from New for You. **Undo** marks the last email unread again; repeated Undo walks back the last 20 reads in this session. Failed updates show an error and leave the email available. Actions use the email’s own linked account.


## Build and verify

```sh
npm run check
npm test
npm run build:site
omarchy plugin validate .
```

`site/` is a responsive landing page with a limited interactive sample, not a browser port of the plugin. Website builds copy only that directory and the public installer. All visuals use sample data. GitHub Actions checks the source and creates a checksum-bearing source archive for version tags; Vercel hosts the static site.

## License and credits

Publicly viewable source; no open-source license is granted at this time (`UNLICENSED`), following Oma Beats' distribution model. Barlow is used under the included SIL Open Font License. The original workspace concept was inspired by NotchOwl; Saturn is an independent project, not affiliated with Omarchy or its connected services.
