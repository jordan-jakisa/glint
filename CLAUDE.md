# CLAUDE.md

Guidance for Claude Code working in this repository.

Adit is a lightweight native macOS git panel (changes, diffs, staging, commits),
with AI-generated commit messages to come. SwiftUI, Swift 6 with complete strict
concurrency, libgit2 vendored in `Packages/Clibgit2`. Bundle id
`com.kerustudios.adit`. Pre-v0.1: history and diffs work; staging and committing
are next.

## Read first

- `docs/DECISIONS.md` - durable decisions and their evidence. Read before proposing
  a change to the name, scope, stack, or build order.
- `docs/ARCHITECTURE.md` - layering, and why each stack choice was made.
- `docs/plans/v0.1-git-panel.md` - what ships first, in order.

## The constraint

Speed is the product. Adit exists because opening a git client to read a diff is too
slow. Before adding anything, ask whether it makes reading a diff or writing a
commit message faster. If not, it does not belong. See the scope decision in
`docs/DECISIONS.md`.

## Commands

```bash
xcodebuild -project Adit.xcodeproj -scheme Adit -configuration Debug build
xcodebuild -project Adit.xcodeproj -scheme Adit test
```

## Conventions

- 2-space indentation.
- The project uses a synchronized root group: files added under `Adit/` are picked
  up automatically. Do not hand-edit `project.pbxproj` to add sources.
- `Views/` never imports `Git/`. libgit2 types are converted to Sendable value
  types at the git boundary.
- User-facing copy: you-form, casual, no em dashes.
- Secrets (model API keys) go in the Keychain. Never in `UserDefaults`, never
  committed.
