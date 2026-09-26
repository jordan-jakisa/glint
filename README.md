# Adit

**A way in to every change.**

A lightweight, native macOS git panel: see your changes, stage, commit. With
AI-generated commit messages to come.

An *adit* is the horizontal tunnel miners cut to enter and inspect a seam. Adit is
the way in to look at your changes. It also expands to **A**I **D**iff
**I**nspection **T**ool.

## Why this exists

Reviewing a diff and writing a commit message means leaving whatever you are doing
and opening a full git client. The existing macOS options (Tower, Fork, Sourcetree)
are repository managers: they do branching, remotes, rebasing, stashing, and the
diff is one panel among many. Adit does the two things you actually do dozens of
times a day, and nothing else:

1. Read the diff.
2. Write the commit message.

Speed is the product. If it is not instant it has failed.

## Status

Pre-v0.1. Opens a repository, lists its history, and shows any commit's diff,
unified or split. Staging and committing are next. See
`docs/plans/v0.1-git-panel.md` for what ships first.

## Build

```bash
xcodebuild -project Adit.xcodeproj -scheme Adit -configuration Debug build
```

Or open `Adit.xcodeproj` in Xcode and press Run. Requires Xcode 27 or later and
macOS 15 or later. Signs ad-hoc, so no developer team is needed for local builds.

## Layout

```
Adit.xcodeproj      Xcode project. Uses a synchronized root group, so files added
                    on disk are picked up with no project-file edits.
Adit/               All app source.
docs/               Architecture, decision log, and plans.
```

## Docs

- `docs/ARCHITECTURE.md` - layering and the stack, with reasons.
- `docs/DECISIONS.md` - the decision log. Read before re-litigating a choice.
- `docs/plans/` - one file per planned release.
