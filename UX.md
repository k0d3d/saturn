# Saturn's visual language

Saturn's workspace is a grid of quiet cards. The layout is deliberately stable:
cards keep their positions so you build spatial memory. The surfaces carry the
state. This document is the contract for the first UI/UX pass — Tasks and the
daily-note hub.

## One cue, one meaning

| Cue | Meaning | Where it appears |
| --- | --- | --- |
| Leading edge on the left | Needs attention. Accent for unread mail or work due today; urgent colour for overdue tasks. | Tasks, mail |
| Small dot, top right | Same attention state, visible even when the edge is out of view. | Tasks, mail |
| Three short bars, bottom right | Volume band: 0, 1–2, 3–7, or 8+ items. Never one bar per item. | Tasks, notes, events, mail |
| Short accent tick, bottom left | The last view you opened. Session-local; clears on shell restart. | Whichever card you last used |
| Thin border lift on hover | Interactive surface, not importance. No layout shift. | Every card |

Volume and urgency are independent. A card can hold many notes and be calm, or
hold one overdue task and need attention.

The pure rules live in `Visual.js`. `volume()`, `attention()` and `forDay()` are
unit tested in `tests/visual.test.cjs` and used by QML through a single import.
`Service.qml` exposes `notesForDay()` as a derived, never-persisted query.

## The daily-note hub

The date-keyed daily note stays the master note. Library notes with the same
`date` appear beneath it as `@Title` rows. Click a row to open that note; click
the small `@` button to insert an explicit `@Title` mention into the daily
note. That mention becomes an edge the next time a graph command refreshes.

Nothing is inserted silently. The hub is an index; you decide when a note
becomes a graph connection. Adding a note with a date is already supported by
`notesV2`, so no schema change was needed.

## Motion

- Card borders and state changes animate over 160 ms using colour/opacity only.
- Switching views fades the incoming pane in over 200 ms; the outgoing pane is
  removed immediately, so no input waits on a transition.
- Completing a task gives a 190 ms bounce on the check control. Completed work
  stays visible, as before.
- No pointer-following, parallax or tilt loops. Buttons and text never move.
- All animations are short, interruptible, and use transform/opacity or colour.

A reduced-motion setting is deliberately not added in this pass: the current
durations are short and non-essential, but this should be revisited if motion
is extended.

## Frosted backdrop

Frost is on by default and can be toggled with the **Frost** button. It uses a
single `ScreencopyView` still plus `QtQuick.Effects.MultiEffect`, captured once
when the panel opens. There is no live screen capture loop. Until the capture
lands, the panel stays opaque, so text never flashes against an unprepared
backdrop. Turning frost off restores a fully opaque panel and releases the
effect immediately.

Why a still instead of compositor blur: Saturn is a layer-shell panel, and the
screencopy route works across the compositors Omarchy supports without editing
Hyprland config. The trade-off is that the blurred desktop is a snapshot from
panel open, not a live view. It was chosen to keep input latency predictable.

## Performance budget

- One blur effect, active only while the panel is visible.
- No per-frame JavaScript, no perpetual animations, no per-item stack layers.
- Volume is recalculated from existing arrays when the store revision changes.
- Long lists remain `ListView`-based and virtualised.
- Measure open, view switch, scroll and typing with frost on and off in both
  compact and full-screen modes. Target the display frame budget (16.7 ms at
  60 Hz, 8.3 ms at 120 Hz) and keep click-to-response immediate.

## Not in this pass

- `@` autocomplete popup and mention chips in the notes editor.
- Per-card "changed since you last looked" markers; they need per-feature
  revision counters rather than one global revision.
- Visual treatments for Insights and Connections beyond the shared reveal.
- An automatic graph reindex after writing a mention. Graph commands refresh on
  read, so a mention becomes an edge on the next graph query.
