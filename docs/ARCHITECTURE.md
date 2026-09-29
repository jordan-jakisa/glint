# Architecture

**Date:** 2026-09-26
**Status:** Git access, history, and diff rendering are built. Staging and
committing are next (see `docs/plans/v0.1-git-panel.md`).

## The one constraint that shapes everything

Glint exists because opening a git client to read a diff is too slow. Every
architectural choice below is subordinate to keeping the path from "I want to see
my changes" to "I am looking at my changes" under about 100ms.

That rules out two things other tools do:

1. **No shelling out to `git`.** Each `Process` spawn costs roughly 10-30ms before
   git does any work, and a commit list plus per-file diffs means dozens of calls.
   Glint links libgit2 in-process instead.
2. **No web view.** The diff is the hot path. It renders with native text layout.

## Layering

```
App/         Scenes, menus, and RepositorySession: the per-window state that
             talks to Git/ and hands Models/ values to the views.
Views/       Presentation only. No git types cross into this layer.
Models/      Value types: Commit, FileChange, Hunk, Line. Sendable structs.
Git/         libgit2 wrapper. The only layer that knows libgit2 exists.
Intelligence/  Commit-message generation: providers, prompt, streaming client,
               settings, Keychain.
```

The rule that keeps this honest: `Views/` imports `Models/` but never `Git/`. Git
objects are converted to plain Sendable value types at the boundary. This is what
makes the views previewable and testable without a repository on disk.

## Git access

**libgit2, vendored from source** (`Packages/Clibgit2`, see `VENDORED.md`), with
Glint's own thin wrapper in `Git/`. libgit2 is the same library GitHub, GitKraken, and
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

Measured, as planned. A SwiftUI `LazyVStack` of rows took 75 to 95 ms per commit
switch against a 50 ms budget: it measured every row, and `NavigationSplitView`
preference passes walked all of them.

The diff body is now an `NSTableView` (`Views/DiffTableView.swift`) with a
custom-drawn cell per row (`Views/DiffRowCell.swift`):

- Only rows on screen exist. File headers float as group rows.
- The font is monospaced, so row heights are arithmetic (characters per line
  divided into the text length), not text layout. Non-ASCII lines fall back to
  measuring.
- Long lines wrap by character, so the arithmetic and the drawing agree.
- Keyboard jumps reach the table through `DiffScroller`, skipping SwiftUI.

SwiftUI still owns everything around the diff: the window, sidebar, header,
and toolbar.

## Syntax highlighting

A small hand-written lexer (`Models/Syntax.swift`, languages in
`SyntaxLanguages.swift`): comments, strings, numbers, keywords and naming
conventions for about forty languages, coloured with Zed's One Dark and One Light
syntax keys. Not tree-sitter: a diff row is lexed as it's drawn, one line at a time,
which costs less than typesetting the line, so it never delays the first paint and
adds no dependency. Lines inside a `/* */` block are recognised by their leading `*`.
The hunk editor lexes its whole text, so comments and strings carry across lines.

## Editing in the diff

The editor (`LiveEdit`) holds some lines of a file and checks the file a few times
a second (a `stat`, and a read only when it changed). What changed on disk is merged
into what you have with a three-way line merge (`Models/LineMerge.swift`), so an
agent writing the file while you type shows up in place without losing your edit;
where both changed the same lines, yours win and the footer says so. Save merges
once more, then writes.

## Commit-message generation

Built in `Intelligence/`. A diff goes out to a model API, a message streams back
into the box.

- `AIProvider`: OpenCode Zen, Vercel AI Gateway, OpenRouter. All speak OpenAI
  chat completions; each has its own rule for spotting free models in its
  public `/models` listing.
- `CommitPrompt`: the prompt, the diff rendered as a patch, squeezed to 20 KB
  (long lines clipped, then trailing hunks of the biggest files left out), and
  cleanup of replies (reasoning blocks, code fences).
- `AIClient`: streams server-sent events.
- `AISettings` and `Keychain`: provider and model in UserDefaults, keys in the
  Keychain.

The user's code leaves the machine, so it's off until switched on, sends only on
request, and says where it's going. The output is a draft in an editable field,
never committed automatically.

## Sandbox

Off. Push, pull, and commits need the user's real keys, agent, git config,
credential helpers, and hooks, none of which a sandboxed app can reach. See the
decision log. libgit2 handles reads and index writes; system git handles
commit, branch switching, and network operations.
