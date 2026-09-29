# Decision log

Durable decisions with their evidence. Weigh changes against these. Do not
re-litigate without new evidence.

## Name: Glint (2026-09-26, replaces Adit)

Adit's acronym (AI Diff Inspection Tool) stopped fitting once the app grew into a
full git panel: staging, commits, branches, push and pull, a terminal. AI is a
small part of it. The goal became a short, easy name with character, like Zed or
Ghostty.

**Glint**: a quick flash of light, the one look you need to see what changed. It
shares a root with "glance" (Middle English *glenten*, to gleam or look askance;
etymonline), which gives the tagline "Every change, at a glance."

- One syllable, spelled as it sounds. Easy-to-pronounce names are processed more
  fluently and rated better (Alter & Oppenheimer 2006, PNAS). The short front
  vowel reads as quick, light and small (Klink 2000, Marketing Letters).
- Homebrew cask and formula both free. No git or diff tool uses the name; the
  largest GitHub project called Glint has under 500 stars.
- Rejected: Diffy (a 3.8k-star diff tool has it), Flick, Scout, Tuck, Blip,
  Gleam, Snap (taken on Homebrew or by large projects), Spry (describes a feeling,
  not the job), Tick, Nib, Twig, Sprig, Kite, Graft, Peek (weaker fit or clashes).

The bundle id is `com.kerustudios.glint`. `LegacyMigration` copies Adit's
settings on first launch, and `Keychain` copies a key saved under Adit's service
the first time it's read.

## Name: Adit (2026-09-26, replaced the same day)

**A**I **D**iff **I**nspection **T**ool, and a real word: the horizontal entry
tunnel into a mine, cut for access and inspection.

Checked before choosing: Homebrew cask and formula both free, no software product
collision on GitHub (hits are people named Aditya plus a 34-star Windows remote
tool). npm is taken and irrelevant for a native Mac app. Short exact-match domains
are all squatted, as every four-letter `.app` is; `adit.sh` is free.

Rejected alternatives and why:

- **Stet** (the proofreader's mark for "let it stand") won every availability check
  and fit the review metaphor exactly, but the `st...t` clip is awkward to say and
  opaque spoken aloud.
- **Verso**, the left page of a book spread: a 5,400-star Servo-based browser owns
  the name.
- **Loupe**: a 3,200-star JS project, and it is a homophone for "loop", which is
  actively bad in a developer tool.
- **Amend**: real git verb and easy to say, but it names one narrow operation and
  undersells a viewer.
- **Delta**: an excellent existing CLI diff pager already has the name.

Also avoided the entire optical family (Prism, Lens, Facet) because Kaleidoscope is
an established macOS diff viewer and anything optical reads as a clone of it.

**Tagline:** "A way in to every change."

## Scope: a fast git panel, not a full git client (2026-09-26, revised)

Revised the same day. The first version read "a viewer, not a git client":
read diffs, draft messages, nothing else. Using it made clear that reading the
diff is only half the loop; the other half is staging and committing, and
leaving Adit for that defeats the point.

Adit now covers what Zed's git panel covers, borrowing its concepts without
copying its design: working-tree changes, diffs, staging
(files, hunks, lines), committing, branch switching, and push and pull. It
still does not do rebase, merge, conflict resolution, stash, or history
rewriting beyond amend. Tower, Fork, and Sourcetree do those, and competing
with them means becoming slow.

The test for any proposed feature: does it make the look, stage, commit loop
faster? If not, it does not belong.

## Scope: everything Zed's git does (2026-09-28, replaces the scope above)

Asked for directly: Glint covers all of Zed's git features, not only its
panel. On top of the look, stage, commit loop that means stash (create, list,
apply, pop, drop), blame (inline and per file), conflict resolution (use
current, incoming, or both), file history, word-level diff highlighting,
restoring hunks, a tree view, deleting branches, choosing a remote, force
push, pull with rebase, and permalinks. The "not a full git client" line above
no longer holds for these; rebase, merge and history rewriting beyond amend
are still out, as Zed leaves them to the terminal too.

With Liquid Glass off, Glint also looks like Zed: One Dark and One Light
colours, a flat panel, and Zed's default sizes (16 pt interface, 15 pt code),
which are now Glint's defaults everywhere.

Speed stays the product: each feature has to stay off the hot path (opening,
j/k, staging), and the budgets in the v0.1 plan still apply.

## Worktrees are first-class (2026-09-28)

Linked worktrees are how you run two branches at once: an agent on one, you
reviewing another, a hotfix beside a feature. Opening them used to mean the
terminal and ⌘O. Glint now treats them as places a branch lives:

- The branch picker marks a branch that's checked out in another worktree;
  picking it opens that worktree instead of failing to switch.
- ⌥↩ (or Option-click) on any branch, or on "Create branch", makes a new
  worktree for it in `../worktrees/<repo>-<branch>` (Zed's default folder)
  and opens it.
- A worktree can be removed from the picker; git refuses one with
  uncommitted work, and Glint says so in plain words.

It passes the scope test: it removes the slowest part of reviewing a second
branch (stash, switch, lose your place). Still out: moving, locking, pruning
and repairing worktrees. The terminal does those.

## Build order: viewer before AI (2026-09-26)

The diff viewer ships first, with no AI at all. Three reasons:

1. It is the actual problem. Reading a diff without leaving the editor is the pain.
2. It is the risky part. Rendering thousands of hunks at native speed is where the
   app either feels instant or feels like Electron. An API call is solved and dull.
3. Generating a message needs the staged diff anyway, so the reading layer has to
   be built and correct regardless.

## libgit2, not subprocess git, for reads (2026-09-26)

Each `Process` spawn costs roughly 10-30ms before git starts working, and listing
commits plus diffing files means dozens of calls per screen. In-process libgit2 via
SwiftGit2 removes that cost entirely. libgit2 is what GitHub, GitKraken, and
Xcode's own source control are built on.

Cost accepted: libgit2 handles are not thread-safe per repository, so the git layer
confines each handle to an actor and converts to Sendable value types at the
boundary. The target builds with complete strict concurrency to catch violations at
compile time rather than as field crashes.

## libgit2 vendored from source, not SwiftGit2 (2026-09-26)

Supersedes "via SwiftGit2" above. SwiftGit2 only builds with Carthage (no
Swift package), its last release was 2019, and its diff API hides the
`git_diff_options` that matter for speed. The SPM alternatives build libgit2
from one person's fork.

Instead, libgit2 v1.9.7 is vendored in `Packages/Clibgit2` as a local Swift
package, compiled from the official release with only the parts Adit needs (no
networking, no SSH). Adit's own thin wrapper in `Git/` covers exactly what v0.1
uses. Cost accepted: about 5 MB of C source in the repo, and upgrades are a
manual copy (steps in `Packages/Clibgit2/VENDORED.md`).

## Terminal: SwiftTerm, pinned to 1.11 (2026-09-26)

The built-in terminal panel uses SwiftTerm (MIT, maintained, used by several
Mac terminal apps) through Swift Package Manager: writing a terminal emulator
is out of scope. Pinned to 1.11.x on purpose: 1.12 and later add Metal shaders,
which need Xcode's separate Metal Toolchain download to build, and 1.19 adds a
build plugin Xcode asks you to trust. Revisit when the GPU renderer is worth
that setup.

## Terminal splits: tmux-lite, nothing more (2026-09-28)

A terminal tab can split into panes: right (⌘D) or down (⌘⇧D), move between
them with ⌥⌘ and an arrow, close the one you're in with ⌥⌘W, drag a divider
to resize. Stacking needs height, so Split Down first expands the terminal
over the diff, and while it's docked each stack shows only the pane you're
in (the rest keep running). Running a dev server beside a shell while reading the diff is part
of the look, stage, commit loop, and leaving for another app to get a second
shell breaks it.

Deliberately left out: saved layouts, auto-tiling, swapping panes, resizing by
keys, and zooming a pane. Ghostty, iTerm, and tmux (which runs fine inside
Glint's terminal) do those; `Open in Terminal App` is one key away.

## Xcode project with a synchronized root group (2026-09-26)

The project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16 and later), so
source files are discovered from the folder instead of being listed individually in
the project file. This removes the merge conflicts and churn that normally make
`project.pbxproj` painful in git, which matters for a project whose whole subject is
diffs.

Signing is ad-hoc (`CODE_SIGN_IDENTITY = "-"`) so the project builds with no
developer team configured. `scripts/install.sh` overrides that for installed
builds when an Apple Development certificate is available: an ad-hoc signature
changes with every build, and macOS ties Keychain "Always Allow" to it, so each
update asked for the API key again. A real team and notarization get added when there is
something worth distributing.

## Not sandboxed; system git for writes and network (2026-09-26, revised)

Revised the same day. The app started sandboxed with user-selected file access,
so it could touch only the repositories the user picked. That stopped working
once Adit took on push and pull: a sandboxed app can't read `~/.ssh`, the SSH
agent, `~/.gitconfig`, or credential helpers, and every process it starts
inherits the sandbox. The alternative, rebuilding libgit2 with its own HTTPS and
SSH stacks and asking for `~/.ssh` through an open panel, was a lot of work for
partial agent and `~/.ssh/config` support.

So the sandbox is off, and Adit splits git work by what it needs:

- **libgit2, in-process:** everything read often and fast. Status, history,
  diffs, and index writes (stage, unstage, hunk and line staging, discard).
- **System git, as a subprocess:** commit, branch switching, fetch, pull, push.
  These are rare, so the 10 to 30 ms spawn cost doesn't matter, and they then
  behave exactly like the terminal: same keys, agent, config, credential
  helpers, signing, and hooks.

Cost accepted: Adit can read anything the user can, and Mac App Store
distribution is off the table (it requires the sandbox).

## AI commit messages: hosted free models first (2026-09-26)

Decides the earlier open question "where the AI runs" for now: hosted, starting
with providers that offer free models, all through one OpenAI-compatible chat
completions client. OpenCode Zen, Vercel AI Gateway, and OpenRouter, in that
order. Only their free models are listed (zero-priced, or named as free where a
provider's listing has no prices).

Borrowed from Zed's git panel, which uses its language-model providers for this
(not ACP; ACP runs agents in Zed's agent panel): staged diff if anything is
staged, else every change; the diff squeezed to 20 KB; the user's subject line
kept; the repository's agent rules file sent along; the reply streamed into the
message box. Zed's code is GPL, so the prompt and truncation are written fresh,
not copied.

Privacy, as the architecture notes require: off until switched on in Settings,
nothing sent until you press the button, the provider named on the button, and
each provider's note about free-tier data use shown next to the model picker.
Keys live in the Keychain.

A local model is still open, for people who can't send code anywhere. ACP
agents (opencode, Claude Code, Gemini CLI) are the other candidate for later.

## Files tab: browse and edit any file (2026-09-29)

Asked for directly: a Files tab beside Changes and History lists the whole
project (every repository in a folder of repositories, each as a folder), with
files `.gitignore` hides shown dimmed and ignored folders read only when opened.
A file opens in the same editor as hunk edits: syntax colours, line numbers,
kept in step with the file on disk, ⌘S to save, saved when you switch files or
quit. This goes past "a git panel"; it earns its place because fixing what a
diff shows, or a file an agent just wrote, shouldn't mean opening another app.
