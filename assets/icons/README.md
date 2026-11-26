# Icons

Lucide icons (https://lucide.dev), ISC licensed, stored as 24×24 stroke SVGs.

The strokes are white in the files and tinted at runtime with `MultiEffect`
colorization, so the same asset follows the active Omarchy theme.

| File | Used for |
| --- | --- |
| `play.svg` | start focus / row focus action |
| `pencil.svg` | edit task |
| `archive.svg` | archive task |
| `undo.svg` | restore task |
| `x.svg` | clear tag filter |
| `link.svg` | connected task |
| `file-text.svg` | connected note |
| `check.svg` | completed task check |
| `list-todo.svg` | Tasks switch tile |
| `notebook-pen.svg` | Notepad switch tile |
| `calendar.svg` | Events switch tile |
| `mail.svg` | Mail switch tile |

`assets/saturn.svg` is the brand mark generated with Recraft V3 SVG on Replicate,
with the generated full-canvas backdrop removed so it blends into any surface.
`assets/saturn.png` is its 512px transparent raster for the bar, where it is
scaled down with mipmaps. The dashboard header uses the original split into
paint-order layers — `saturn-back.svg`, `saturn-planet.svg`, `saturn-ring.svg`
and five `saturn-star-N.svg` dots — so the ring can counter-rotate and the stars
twinkle in QML. Qt renders SVG statically, so the motion lives in `SaturnMark.qml`.
