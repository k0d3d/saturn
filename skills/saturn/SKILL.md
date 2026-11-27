---
name: saturn
description: >
  Read and update the local Saturn workspace (Omarchy plugin k0d3d.saturn): tasks,
  due dates, completion, archive, the tagged note library, daily notes and the
  SQLite knowledge graph. Use when the user asks about their Saturn tasks or
  notes, wants a task or note created/updated, wants to search notes, inspect
  workspace data, or explore/add connections between items. Saturn is a
  second brain stored in ~/.local/share/saturn/.
---

# Saturn workspace

Saturn is a local-first Omarchy workspace. All task and note data lives in
`~/.local/share/saturn/workspace.json` (schema 2). Never edit that file directly
from an agent — use one of the two interfaces below so writes stay atomic and
the running shell stays in sync.

## Which interface to use

- **Desktop shell running (normal):** `saturn data …` — the live shell mutates its
  in-memory workspace, persists atomically, and the UI updates immediately.
- **Shell not running:** `python3 ~/.config/omarchy/plugins/k0d3d.saturn/scripts/workspace_api.py …`
  — takes an exclusive lock, validates the schema, writes atomically and keeps a
  backup. It refuses to write while the shell is live; use `saturn data` instead.

Both interfaces print a single JSON object/array on stdout. There are no
credentials in workspace data; connection tokens live separately under
`~/.config/saturn/` and are never exposed by these commands.

## Commands

Read-only (safe in Plan mode):

```sh
saturn data get                  # whole workspace object
saturn data sync-status          # sync metadata and agent audit, no note bodies
saturn data tasks list           # all task objects
saturn data notes list           # library note objects
saturn data search "query" [limit]
saturn data settings             # LLM tag-pass config in workspace.settings.llm
saturn tags status               # schedule, model and pending task count
saturn tasks list                # short alias
saturn notes list                # short alias
```

Writes:

```sh
saturn data add-task "Title tomorrow" [YYYY-MM-DD]
saturn data complete-task <id>          # toggles done/completedAt
saturn data archive-task <id>           # hides from active views
saturn data restore-task <id>
saturn data set-due <id> YYYY-MM-DD      # empty value clears the date
saturn data set-tags <id> "tag1,tag2"    # replaces the task's tags
saturn data add-note "Title" "Body" "tag1,tag2" [YYYY-MM-DD]
saturn data update-note <id> "Title" "Body" "tag1,tag2"
saturn data pin-note <id>
saturn data archive-note <id>
saturn data restore-note <id>
saturn data settings-set '{"llm":{"hours":[9,18]}}'
saturn tags run                  # force the DeepSeek tag-refinement pass
```

The offline script accepts the same lowercase/underscore-free names:
`get`, `status`, `sync-status`, `tasks-list`, `notes-list`, `search`,
`add-task`, `complete-task`, `archive-task`, `restore-task`, `set-due`, `set-tags`,
`add-note`, `update-note`, `pin-note`, `archive-note`, `restore-note`,
`settings`, `settings-set`.

Task titles are tagged deterministically on add and rename; `saturn tags run`
asks OpenCode's DeepSeek model to refine them at configured hours.

## Data shapes

Task:
```json
{"id":"…","title":"…","done":false,"completedAt":0,"due":null,
 "createdAt":0,"updatedAt":0,"archived":false,"archivedAt":0,
 "body":"","tags":[],"source":"local","externalId":null}
```

Library note:
```json
{"id":"…","title":"…","body":"…","tags":[],"date":null,
 "createdAt":0,"updatedAt":0,"archived":false,"pinned":false}
```

Daily notes are keys of `notes` (`"YYYY-MM-DD": "text"`) and appear in search
results with ids like `daily:2026-11-23`. They cannot be pinned or archived.
In the UI the daily note is a hub: library notes whose `date` matches the
selected day appear as `@Title` rows, and the `@` button writes an explicit
mention into the daily note. `sync.audit` records agent command names with
timestamps — never note bodies.

## Knowledge graph

Tags are the cheapest way to give the graph structure: `set-tags` writes
lowercased, de-duplicated tags, and the next refresh turns each into a `tag:`
node with a `tagged` edge. Prefer a few stable tags over many one-off labels.

The graph lives in `~/.local/share/saturn/graph.sqlite` and is authoritative for
relationships. It is separate from `workspace.json`, which owns item content.
All graph commands work with or without the desktop shell and print JSON.

```sh
saturn graph status                 # counts, last refresh, database path
saturn graph reindex                # refresh tag and wiki edges
saturn graph link <src> <relation> <dst> ["label"]
saturn graph unlink <src> <relation> <dst>
saturn graph neighbors <key> [depth] [relation]
saturn graph backlinks <key> [relation]
saturn graph path <from> <to> [maxDepth]
saturn graph list [nodes|edges]
saturn graph resolve <key-or-title>
saturn graph forget <key>           # removes a node and every edge touching it
saturn graph backup                 # snapshot into the local backup folder
```

Node keys are `task:<id>`, `note:<id>`, `daily:<YYYY-MM-DD>`, `event:<id>` and
`tag:<tag>`. Commands also accept a unique title. Relations are lowercase
letters, digits, `-` and `_`, up to 40 characters. Pick meaningful relations
such as `supports`, `follows-up`, `derived-from` or `contradicts`; use the
optional label for short context. `[[Title]]` links, `@Title` mentions and shared tags in
note/task bodies are added automatically and refreshed on each command. Mentions
resolve by unique title, by exact key (`@task:<id>`), or by the longest unique
title prefix; ambiguous names create no edge. Use `backlinks` to find everything
that points at a task or note. Never remove an agent edge unless the user asks;
use `forget` only for an intentional deletion, since it removes the node and all
its edges.

## Safety rules

1. Read `get` or `tasks list` first and use real ids; never invent an id.
2. Confirm with the user before archiving tasks/notes or bulk changes. Completing
   a task is reversible, so it normally needs no confirmation.
3. Use `"tomorrow"`, `"today"`, `"next Mon"` or a `YYYY-MM-DD` date in a task
   title when the user specifies a time; do not guess a date otherwise.
4. Keep titles ≤ 500 chars, note bodies ≤ 20,000 chars, at most 12 tags.
5. Never put secrets, tokens or command output from unrelated files into tasks
   or notes, and never paste credentials into `workspace.json`.
6. After a write, verify with `saturn data get` or the relevant list command.
7. The Markdown mirror is at `~/Documents/saturn/` (override with `SATURN_VAULT`).
   Tasks are `tasks/*.md`, library notes `notes/*.md`, daily notes `daily/*.md`.
   Each file has a JSON front matter block with `id`, `title`, `updatedAt` and
   state flags. Edit those files with a normal editor, then run
   `saturn vault sync` to pull changes in and commit the batch to the local Git
   repo. Conflicts are local-first and listed in `conflicts.md`. Never hand-edit
   `workspace.json`, and never put secrets in vault files.
