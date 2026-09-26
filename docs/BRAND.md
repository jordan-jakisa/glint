# Glint brand

One page: what Glint is called, how it looks, how it talks, and why. The brand
board with every piece laid out is the "Glint brand" canvas.

## Name and tagline

- **Glint**: a quick flash of light, the one look you need to see what changed.
  Always "Glint", never "GLINT" in running text. Why this name: the naming
  decision in `DECISIONS.md`.
- **Tagline:** "Every change, at a glance." Sentence case, with the period.
  Glint and glance share a root (Middle English *glenten*, to gleam; etymonline).

## Icon

A `>` prompt and a cursor on a graphite tile. The cursor fades from white into
violet: the one glowing element, the glint.

- Source: `scripts/draw-icon.swift` draws every size into
  `Glint/Assets.xcassets/AppIcon.appiconset` (`light` draws the light variant).
  Change the script, not the PNGs.
- Only one thing glows. A target that differs in colour and brightness is found
  without searching (Treisman & Gelade 1980; Itti, Koch & Niebur 1998), so the
  eye lands on the cursor first.
- Curves, round stroke ends. People prefer curved shapes to sharp angles
  (Bar & Neta 2006).
- Reads at 16 px: heavier strokes at small sizes, no fine detail. Simple,
  schematic icons with few shapes are the easiest to recognise small (Apple HIG,
  App icons; Harley 2014, NN/g).
- Tried and dropped: a letter G (too close to Google), sparkle stars (read as
  the AI symbol), stacked bars (read as a to-do app), optical imagery (reads as a
  Kaleidoscope clone).

## Colors

| Role | Light | Dark | Where |
|---|---|---|---|
| Accent (Glint violet) | `#5B47F0` | `#9A8FFF` | Selection, hunk actions, sparkle button, the glint |
| Added | system green | system green | Diff additions, "+" counts |
| Removed | system red | system red | Diff deletions, "-" counts |
| Graphite | `#2B2E36` to `#0A0B0E` | same | Icon tile |
| Mist | `#E9E8F2` | | Light icon tile, light surfaces in brand material |

Additions and removals use the system colours so they follow accessibility
settings. Violet stays clear of green and red so it never reads as a diff colour.
It's chosen for contrast and distinctness, not a claimed feeling: colour-emotion
links for purple vary the most across cultures (Jonauskaite et al. 2020).

## Type

System fonts only: SF Pro for the interface, SF Mono (the system monospaced
font) at 12 pt for code and line numbers.

## Voice

From `CLAUDE.md`, and it applies to every string in the app:

- **You-form.** "Pick the folder that contains .git", not "The user selects".
- **Casual and plain.** Short sentences, everyday words.
- **No em dashes.** Use a comma, a colon, or a new sentence.
- **Errors say what to do.** "The remote has commits you don't have. Pull, then
  push again." Not git's raw stderr.
- **Name where data goes.** Anything sent off the machine (AI messages) says
  where, before it's sent.
- **Quiet wins.** "Committed a1b2c3d", "Pushed 3", "All caught up". No
  confetti.

## Open questions

- A website, and a domain for it.
- A screenshot for the README, once the polish pass settles.
