# Architecture

**Date:** 2026-09-26
**Status:** Planned. Nothing below is built yet except the app shell.

## The one constraint that shapes everything

Adit exists because opening a git client to read a diff is too slow. Every
architectural choice below is subordinate to keeping the path from "I want to see
my changes" to "I am looking at my changes" under about 100ms.

That rules out two things other tools do:

1. **No shelling out to `git`.** Each `Process` spawn costs roughly 10-30ms before
   git does any work, and a commit list plus per-file diffs means dozens of calls.
   Adit links libgit2 in-process instead.
2. **No web view.** The diff is the hot path. It renders with native text layout.

## Layering

```
App/         SwiftUI scenes, window and menu configuration.
Views/       Presentation only. No git types cross into this layer.
Models/      Value types: Commit, FileChange, Hunk, Line. Sendable structs.
Git/         libgit2 wrapper. The only layer that knows libgit2 exists.
Intelligence/  Commit-message generation. Talks to a model API.
```

The rule that keeps this honest: `Views/` imports `Models/` but never `Git/`. Git
objects are converted to plain Sendable value types at the boundary. This is what
makes the views previewable and testable without a repository on disk.

## Git access

**libgit2, via SwiftGit2.** libgit2 is the same library GitHub, GitKraken, and
Xcode's own source control use. It is C, in-process, and has no subprocess cost.

Diff reading specifically uses libgit2's `git_diff` API with a configured
`git_diff_options`. Two settings matter for speed: context lines and the
similarity detection for rename/copy detection, which is expensive and should be
off until the user asks for it.

Concurrency: libgit2 objects are not Sendable and not thread-safe per repository.
The `Git/` layer confines each repository handle to its own actor and hands
`Sendable` value types across the boundary. This is why the whole target builds
with `SWIFT_STRICT_CONCURRENCY = complete`: getting this wrong is the most likely
source of hard-to-reproduce crashes in a tool like this.

## Rendering the diff

The naive SwiftUI approach, a `LazyVStack` of `Text` per line, falls over on large
diffs. Plan:

1. Start with `LazyVStack` and measure on a genuinely large diff, for example a
   lockfile change or a vendored dependency bump.
2. If it stutters, move to a single `NSTextView`-backed representable with a custom
   `NSTextStorage` per pane, which is what fast native editors use.

Do not pre-optimize this. Measure first, on real diffs.

## Syntax highlighting

Deferred to after v0.1. When added, it runs off the main actor and never blocks the
first paint: diff structure appears immediately, colour arrives when ready.

## Commit-message generation

A diff goes out to a model API, a message comes back. Design notes:

- The user's code leaves the machine. This must be explicit, opt-in per invocation
  at first, and never silent. Say so plainly in the UI.
- Large diffs exceed context. Summarize per file, then summarize the summaries.
- The output is a draft in an editable field, never committed automatically.
- The API key lives in the Keychain, not in `UserDefaults` and not in the repo.

## Sandbox

The app is sandboxed with `files.user-selected.read-write`. The user picks a
repository through an open panel, which grants access to that folder. Persisting
access across launches needs security-scoped bookmarks. This is more work than
disabling the sandbox, and it is the right posture for a tool that reads source
code: the app can touch the repositories the user chose and nothing else.
