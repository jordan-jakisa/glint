<p align="center">
  <img src="docs/assets/icon.png" width="128" height="128" alt="Glint icon: a prompt whose cursor glows violet">
</p>

<h1 align="center">Glint</h1>

<p align="center"><strong>Every change, at a glance.</strong></p>

A fast, native macOS git panel: read the diff, stage exactly what you mean, and
commit with a message that says why. With AI-written commit messages from free
models.

A *glint* is a quick flash of light: the one look you need to see what changed.
Glint was called Adit until 2026-09-26; it brings your settings and keys over
on first launch.

## Why this exists

Reviewing a diff and writing a commit message means leaving whatever you are doing
and opening a full git client. The existing macOS options (Tower, Fork, Sourcetree)
are repository managers: they do branching, remotes, rebasing, stashing, and the
diff is one panel among many. Glint does the two things you actually do dozens of
times a day, and nothing else:

1. Read the diff.
2. Write the commit message.

Speed is the product. If it is not instant it has failed.

## Install

Download `Glint-<version>.dmg` from the latest
[release](https://github.com/jordan-jakisa/glint/releases), open it, and drag
Glint to Applications. Or with Homebrew:

```bash
brew install --cask jordan-jakisa/tap/glint
```

Needs macOS 15 or later. On first launch Glint walks you through setting up AI
commit messages (a free API key from OpenCode Zen, Vercel AI Gateway, or
OpenRouter) and opening your first project.

## What it does

- Your uncommitted changes and any commit's diff, unified or split, updating as
  you save.
- Stage files, hunks, or single lines. Commit, amend, and undo the last commit.
- Switch and create branches; fetch, pull, and push with your own git, so SSH
  keys, hooks, and signing work as in the terminal.
- A built-in terminal with tabs.
- Folders that hold several repositories, with a switcher for each and for your
  recent projects.
- Commit messages that say why, written by free AI models. Your diff is sent
  only when you ask.
- Every shortcut can be changed in Settings.

## Keys

All of these can be changed in Settings > Shortcuts.

| Key | Does |
|---|---|
| `j` / `k` | Next / previous file or commit |
| `n` / `p` | Next / previous hunk |
| `⌘↓` / `⌘↑` | Next / previous file in the diff |
| `o` | Collapse or expand the file |
| Space | Stage or unstage the selected file |
| `s` | Stage or unstage the selected lines, or the hunk at the top |
| `c` | Write the commit message (Escape leaves it) |
| `⌘↩` | Commit |
| `⌥⌘G` | Write the commit message with AI |
| `⌘T` / `⌥⌘T` | Terminal in Glint / in your terminal app |
| `⇧⌘T` / `⌥⌘W` | New / close terminal tab |
| `⌥⌘O` | Switch to a recent project |
| `⇧⌘R`, `⌘1`–`⌘9` | Switch repository (in a folder of several) |
| `⌘B` | Switch branch |
| `⌥⌘F` / `⌥⌘P` / `⌥⇧⌘P` | Fetch / pull / push |
| `⌥⌘S` / `⌥⌘U` | Stage all / unstage all |
| `⌘\` | Unified or split |
| `⌘R` | Reload |

## Build

```bash
xcodebuild -project Glint.xcodeproj -scheme Glint -configuration Debug build
```

Or open `Glint.xcodeproj` in Xcode and press Run. To build and install to
`/Applications`, run `scripts/install.sh`; it signs with your Apple Development
certificate if you have one, so macOS keeps Keychain permissions across updates. Requires Xcode 27 or later and
macOS 15 or later. Signs ad-hoc when there's no certificate, so no developer team
is needed for local builds. Releases: `docs/RELEASING.md`.

## Layout

```
Glint.xcodeproj      Xcode project. Uses a synchronized root group, so files added
                    on disk are picked up with no project-file edits.
Glint/               All app source.
docs/               Architecture, decision log, and plans.
```

## Docs

- `docs/ARCHITECTURE.md` - layering and the stack, with reasons.
- `docs/DECISIONS.md` - the decision log. Read before re-litigating a choice.
- `docs/plans/` - one file per planned release.
- `docs/BRAND.md` - name, icon, colors, and voice.

## License

MIT, see `LICENSE`. Glint ships with libgit2 (GPLv2 with the linking exception)
and SwiftTerm (MIT); their licences are in `Glint/Acknowledgements.txt` and under
Help > Acknowledgements in the app.
