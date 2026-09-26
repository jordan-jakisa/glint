# Decision log

Durable decisions with their evidence. Weigh changes against these. Do not
re-litigate without new evidence.

## Name: Adit (2026-09-26)

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

## Scope: a viewer, not a git client (2026-09-26)

Adit reads diffs and drafts commit messages. It does not do branching, remotes,
rebasing, stashing, or merge conflict resolution. Tower, Fork, and Sourcetree
already do those well, and competing with them means becoming slow.

The test for any proposed feature: does it make reading a diff or writing a message
faster? If not, it does not belong.

## Build order: viewer before AI (2026-09-26)

The diff viewer ships first, with no AI at all. Three reasons:

1. It is the actual problem. Reading a diff without leaving the editor is the pain.
2. It is the risky part. Rendering thousands of hunks at native speed is where the
   app either feels instant or feels like Electron. An API call is solved and dull.
3. Generating a message needs the staged diff anyway, so the reading layer has to
   be built and correct regardless.

## libgit2, not subprocess git (2026-09-26)

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

## Xcode project with a synchronized root group (2026-09-26)

The project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16 and later), so
source files are discovered from the folder instead of being listed individually in
the project file. This removes the merge conflicts and churn that normally make
`project.pbxproj` painful in git, which matters for a project whose whole subject is
diffs.

Signing is ad-hoc (`CODE_SIGN_IDENTITY = "-"`) so the project builds with no
developer team configured. A real team and notarization get added when there is
something worth distributing.

## Sandboxed, with user-selected file access (2026-09-26)

Enabled rather than disabled, despite being more work (security-scoped bookmarks
are needed to remember repositories across launches). A tool that reads source code
should be able to touch the repositories the user chose and nothing else.

## Open question: where the AI runs (undecided)

A hosted model API is simpler and better at writing prose. A local model keeps code
on the machine, which some users will require. Undecided, and not needed until
v0.2. Whichever ships first, the privacy behaviour is stated plainly in the UI and
never silent.
