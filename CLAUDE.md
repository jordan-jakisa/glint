# CLAUDE.md

Guidance for Claude Code working in this repository.

Glint is a lightweight native macOS git panel: changes, diffs, staging (files,
hunks, lines), commits, branches, push/pull, a built-in terminal, folders of
several repositories, and AI commit messages from free hosted models. SwiftUI,
Swift 6 with complete strict concurrency, libgit2 vendored in `Packages/Clibgit2`,
SwiftTerm for the terminal. Bundle id `com.kerustudios.glint`. v0.1 is feature
complete and heading into a polish pass; the task tracker is in
`docs/plans/v0.1-git-panel.md`.

## Read first

- `docs/DECISIONS.md` - durable decisions and their evidence. Read before proposing
  a change to the name, scope, stack, or build order.
- `docs/ARCHITECTURE.md` - layering, and why each stack choice was made.
- `docs/plans/v0.1-git-panel.md` - what ships first, in order.

## The constraint

Speed is the product. Glint exists because opening a git client to read a diff is too
slow. Before adding anything, ask whether it makes reading a diff or writing a
commit message faster. If not, it does not belong. See the scope decision in
`docs/DECISIONS.md`.

## Commands

```bash
xcodebuild -project Glint.xcodeproj -scheme Glint -configuration Debug build
xcodebuild -project Glint.xcodeproj -scheme Glint test
```

## Conventions

- 2-space indentation.
- The project uses a synchronized root group: files added under `Glint/` are picked
  up automatically. Do not hand-edit `project.pbxproj` to add sources.
- `Views/` never imports `Git/`. libgit2 types are converted to Sendable value
  types at the git boundary.
- User-facing copy: you-form, casual, no em dashes.
- Secrets (model API keys) go in the Keychain. Never in `UserDefaults`, never
  committed.
