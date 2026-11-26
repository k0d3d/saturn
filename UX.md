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
| Short accent tick, bottom-left | The last view you opened. Session-local; clears on shell restart. | Whichever card you last used |
| Surface lift on hover | Interactive surface, not importance. Only the stack and highlight move. | Every card |
| `⤢` / `×` control | Expands that card to the full workspace, or returns to the grid. | Every card |

Cards are borderless. Separation comes from solid surface contrast, spacing and
the exposed stack layers — not outlines. Volume and urgency are independent: a
card can hold many notes and be calm, or hold one overdue task and need
attention.

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

The selected card animates from its grid slot to the full workspace over
220 ms; the other cards fade out. `Esc`, `0` or `×` returns to the same grid,
preserving spatial memory. A card's controls never move during hover; only
the surface and its stack are animated.

The daily note is still the hub. Library notes dated to the selected day appear
beneath it as `@Title` rows. Click a row to open it, or use its `@` button to
insert an explicit mention into the daily note. Nothing is inserted silently.

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
- Volume and attention are recalculated from existing arrays on store changes.
- Long lists remain `ListView`-based and virtualised.
- Measure open, expand/collapse, scroll and typing with frost on and off at the
  display frame budget (16.7 ms at 60 Hz, 8.3 ms at 120 Hz).

## Not in this pass

- `@` autocomplete popup and mention chips in the notes editor.
- Per-card "changed since you last looked" markers; they need per-feature
  revision counters rather than one global revision.
- Visual treatments for Insights and Connections beyond the shared reveal.
- An automatic graph reindex after writing a mention. Graph commands refresh on
  read, so a mention becomes an edge on the next graph query.
