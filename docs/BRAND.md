# Adit brand

One page: what Adit is called, how it looks, and how it talks.

## Name and tagline

- **Adit**: the horizontal tunnel miners cut to reach and inspect a seam. Also
  **A**I **D**iff **I**nspection **T**ool. Always written "Adit", never
  "ADIT" or "adit" in running text. See the naming decision in
  `DECISIONS.md` for what else was considered.
- **Tagline:** "A way in to every change." Sentence case, with the period.

## Icon

A timber-framed adit cut into dark rock, with the seam inside drawn as a
diff: green lines added, red removed, fading as they recede.

- Source: `scripts/draw-icon.swift` draws every size into
  `Adit/Assets.xcassets/AppIcon.appiconset`. Change the script, not the PNGs.
- Stays clear of optical imagery (lenses, prisms, loupes): that reads as a
  Kaleidoscope clone.
- Reads at 16 px: the frame and two or three bars are all that should survive.

## Colors

| Role | Light | Dark | Where |
|---|---|---|---|
| Accent (timber amber) | `#A4671C` | `#E3A04A` | Selection, hunk actions, sparkle button |
| Added | system green | system green | Diff additions, "+" counts |
| Removed | system red | system red | Diff deletions, "-" counts |
| Rock | `#3A4252` to `#1B2029` | same | Icon background only |

Additions and removals use the system colors so they follow accessibility
settings. The accent is kept away from green and red so it never reads as a
diff color.

## Type

System fonts only: SF Pro for the interface, SF Mono (the system monospaced
font) at 12 pt for code and line numbers.

## Voice

From `CLAUDE.md`, and it applies to every string in the app:

- **You-form.** "Pick the folder that contains .git", not "The user selects".
- **Casual and plain.** Short sentences, everyday words.
- **No em dashes.** Use a comma, a colon, or a new sentence.
- **Errors say what to do.** "Another git process is using this repository.
  Try again in a moment." Not "Error -14".
- **Name where data goes.** Anything sent off the machine (AI messages) says
  where, before it's sent.

## Open questions

- A website, and whether to register `adit.sh` (free when the name was
  chosen). Worth deciding when there's something to distribute.
- A screenshot for the README, once the UI settles after the polish pass.
