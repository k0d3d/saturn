# Saturn's visual language

Saturn is one fullscreen workspace. There is no collapsed or pinned panel:
the bar opens the same five-card grid on every display, and each card can
expand to fill that workspace.

The grid is deliberately asymmetric and stable. Tasks take the tall left
column; Notepad and Focus share the middle; Events and Mail share the right.
Cards do not reorder themselves when counts change. Narrow widths keep the same
slots in a two-column arrangement and let each card scroll internally.

## One cue, one meaning

| Cue | Meaning | Where it appears |
| --- | --- | --- |
| Exposed layers behind a card | Volume band: 1–2, 3–7, or 8+ items. Never one layer per item. | Tasks, notes, events, mail |
| Small dot, top-left | Needs attention. Accent for unread mail or work due today; urgent colour for overdue tasks. | Tasks, mail |
| Surface lift on hover | Interactive surface, not importance. Only the stack and highlight move. | Every card |
| `⤢` / `×` control | Expands that card to the full workspace, or returns to the grid. | Every card |

Cards are borderless. Separation comes from solid surface contrast, spacing and
the exposed stack layers — not outlines. Volume and urgency are independent: a
card can hold many notes and be calm, or hold one overdue task and need
attention.

The header subtitle rotates through twenty lines: original aphorisms and
attributed quotations about time as an absolute constraint, attention and work.
It opens on a random line and changes every nine seconds with a short fade.

The pure rules live in `Visual.js`. `grid()`, `volume()`, `attention()` and
`forDay()` are unit tested in `tests/visual.test.cjs`. `grid()` returns
non-overlapping rectangles that fit the viewport at desktop and narrow widths.
`Service.qml` exposes `notesForDay()` as a derived, never-persisted query.

## Expanding a card

Hover a card and use `⤢`, or press `1`–`5` anywhere in the workspace:

1. Tasks
2. Notepad
3. Focus
4. Events
5. Mail

The selected card animates from its grid slot to 84% of the workspace over
220 ms; the other cards fade out and return as a `SWITCH` rail in the remaining
strip. Each tile shows its icon, name and a live caption (todo count, timer,
events today, unread mail); clicking one swaps focus without returning to the
grid. `Esc`, `0` or `×` returns to the same grid, preserving spatial memory.
Escape is a window shortcut, so it works even while a text field owns focus: one
press leaves a focused card, the next closes the workspace. A card's controls
never move during hover; only the surface and its stack are animated.

Controls are text-first. Filters and view switches are tabs with an animated
underline, task actions appear only on hover, and the Focus card is driven by a
clickable timer dial rather than a row of Start/Pause buttons. The daily note is
still the hub: library notes dated to the selected day appear beneath it as
`@Title` rows. Click a row to open it, or use its `@` action to insert an
explicit mention into the daily note. Nothing is inserted silently.

## Motion

- Expanding or collapsing a card animates its position and size over 220 ms.
- Stack layers settle by 3 px on hover over 140 ms.
- View changes fade the incoming pane in over 180 ms.
- Completing a task gives a 190 ms bounce on the check control. Completed work
  stays visible.
- Durations go through `Style.duration()`, so Omarchy's animation toggle turns
  them off. No pointer-following, parallax or continuous tilt loops.

## Frosted backdrop

Frost is on by default and can be toggled with the **Frost** button. It uses a
single `ScreencopyView` still plus `QtQuick.Effects.MultiEffect`, captured once
when the workspace opens. There is no live screen capture loop. Until the
capture lands, the workspace stays opaque, so text never flashes against an
unprepared backdrop.

Why a still instead of compositor blur: Saturn is a layer-shell panel, and the
screencopy route works across the compositors Omarchy supports without editing
Hyprland config. The trade-off is that the blurred desktop is a snapshot from
open, not a live view. It keeps input latency predictable.

## Performance budget

- One blur effect, active only while the workspace is visible.
- No per-frame JavaScript, no perpetual animations, and at most three stack
  layers per card.
- The notes library and Connections pane are created on first open and then
  hidden, so they never delay the initial workspace paint. Mail loads on first
  expansion; the collapsed card shows a cheap summary.
- Volume and attention are recalculated from existing arrays on store changes.
- Long lists remain `ListView`-based and virtualised.
- Measure open, expand/collapse, scroll and typing with frost on and off at the
  display frame budget (16.7 ms at 60 Hz, 8.3 ms at 120 Hz).

## Tasks card

The task row is the interaction. A single click selects it; double-click the
title or the due text to edit in place. `Enter` commits, `Esc` cancels. The check
circle completes the task; focus and archive appear only while the row is
hovered. There are no persistent per-row action buttons.

Filters are text tabs with counts. The composer is two inline fields — task and
optional due date — with `Enter` to add. `N` focuses the composer, even when the
grid is showing.

Rows are grouped by the day they were created, newest group first, with a quiet
uppercase date header and a count. Tasks with no creation stamp close the list
under `Older`.

Expanded Tasks is one card split into two panes, not two cards. The list side is
40% and a shade darker; the detail side is 60% and is the card surface itself. A
single hairline runs from the card's top edge to its bottom edge between them.
The right pane has no border or radius of its own: the full title, metadata,
body and connections sit directly on the card. The list truncates; the pane
never does.

A `Tags` tab turns the list pane into a tag cloud: chips sized by how often a tag
appears. Picking one switches to `All` with that tag filtered and selects the
first match; the filter can be cleared from the row above the list. While
browsing Tags the detail pane explains the mode instead of showing a stale task.

Minimal hairline borders (10% text alpha, accent at 50% for selection) give the
rows and the pane edges without heavier card chrome.

Actions use Lucide stroke icons tinted to the theme: play for focus, pencil for
edit, archive/undo for the task. Tags are interactive — clicking one filters the
list to that tag, shows a clear control, and updates the tab counts; clicking it
again clears the filter. Below the body, `CONNECTED` lists the selected task's
graph neighbours (tasks and notes), each clickable.

## Open design questions

Card interactions are being designed one card at a time. The current grid is a
base, not a final component spec.

- **Expanded Tasks right pane** — deliberately open beyond the selected task.
  Candidates to evaluate: related notes from the knowledge graph, a day agenda,
  or a task board. Keep the full title and body first.
- **Notepad** — how much of the note body should stay visible versus writing
  in a focused editor; whether day navigation should be a scrubber.
- **Focus** — dial interaction beyond start/pause: drag to set duration, preset
  memory, session history.
- **Events** — inline capture versus a compact agenda; how much calendar
  context belongs in the card.
- **Mail** — summary card versus reading surface; which actions deserve direct
  manipulation.

## Not in this pass

- `@` autocomplete popup and mention chips in the notes editor.
- Per-card "changed since you last looked" markers; they need per-feature
  revision counters rather than one global revision.
- Visual treatments for Insights and Connections beyond the shared reveal.
- An automatic graph reindex after writing a mention. Graph commands refresh on
  read, so a mention becomes an edge on the next graph query.
