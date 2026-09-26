# Premium polish: the whole app

- **Date:** 2026-09-26
- **Scope:** every screen of Glint on macOS (the only platform it ships on)
- **Description:** audit against the nine premium-polish criteria, then a
  ranked list of changes
- **Problem:** v0.1 is feature complete, but a handful of broken promises
  (wrong empty state, spinner flashes, raw git errors, lost focus) make it feel
  less finished than it is fast

Evidence: three code audits (motion, consistency, states) and screenshots of
Changes with a staged file, a clean tree and an untracked binary, in light and
dark.

## Scorecard

| # | Criterion | Score | Evidence |
|---|---|---|---|
| 1 | Anticipates needs | 1 | Staging is instant and the next action is suggested (Pull N, Push N; `+Remote.swift:8`). But focus gets lost (`TerminalPanel.swift:105`, `CommitPanel.swift:50`), drafts don't survive a quit (`RepositorySession.swift:161`), and the terminal's state isn't remembered (`:34`) |
| 2 | Intentional transitions | 1 | Nothing animates, which is right. But the header spinner flashes on every stage and save (`RepositorySession.swift:480`), the sync button changes width (`CommitPanel.swift:178`), the AI note row pushes the list (`:35`), and a slow open shows a blank window (`RootView.swift:46`) |
| 3 | Delight | 1 | Undo last commit and "Written by X" work well. A commit, push or pull finishes silently (`+Commit.swift:59`, `+Remote.swift:62`) |
| 4 | Knows when not to animate | 2 | No animation on any repeated path (`DiffTableView.swift:124`). The only motion is the opacity pulse while AI writes |
| 5 | Invisible consistency | 1 | No raw colours, one spinner style. But there are two status-badge designs (`ChangesView.swift:172` vs `DiffRowCell.swift:75`), five copies of `+N -N` (only one uses monospaced digits), four staging controls at three sizes, and tooltips that hardcode keys you can rebind |
| 6 | Empty states | 1 | Mostly prescriptive. But the diff pane says "Your working tree matches the last commit" when files have changed and none is selected (`DiffPane.swift:33`). A clean tree says "No changes to commit" twice. A branch search that matches nothing is blank |
| 7 | Rewards discovery | 1 | Most tooltips show the key. The single keys (J, K, N, P, S, C, Space) are only listed in Settings |
| 8 | Prescriptive errors | 1 | The lock and no-branch copy are models to follow. But a rejected push, a failed login, a conflict and being offline all show raw git stderr or `NSURLErrorDomain` text (`+Remote.swift:64`, `+Commit.swift:65`, `+AI.swift:96`). Every alert is titled "That didn't work", setup hints included |
| 9 | Premium performance | 1 | Fast paths are measured. Five budgets are still over (see the v0.1 plan). A slow open shows nothing |

## Bugs (logged in `docs/plans/v0.1-git-panel.md`)

| Sev | Bug | Where |
|---|---|---|
| P2 | Commit size doesn't show after opening a repository until something changes | `RepositorySession.swift:384` sets `status` without `refreshCommitSize()` |
| P2 | Diff pane says your tree matches the last commit when it doesn't (files changed, none selected) | `DiffPane.swift:33-36` |
| P2 | Rejected push, failed login, conflicts and offline show raw git or URL error text | `+Remote.swift:64`, `+Commit.swift:65`, `+AI.swift:96`, `GitError.swift:17` |
| P2 | Saving an API key says "Saved" even when the Keychain refused it | `AISettings.swift:80` |
| P2 | Header spinner flashes on every stage, save and uncached j/k | `RepositorySession.swift:480` |
| P2 | Showing or hiding the terminal rebuilds the diff, loses your scroll and resets the terminal height | `RootView.swift:53-62` |
| P2 | Switching repository with the terminal open moves focus into the shell, so j/k stop working | `TerminalPanel.swift:93,105` (`focus` is never read) |
| P3 | Pressing C in History switches tab but doesn't focus the message | `CommitPanel.swift:50` |
| P3 | Tooltips show the default keys after you rebind them | `CommitPanel.swift:84,86,138,160,241`, `ChangesView.swift:158`, `DiffPane.swift:111,114`, `RootView.swift:71` |
| P3 | A binary untracked file shows "No content changes." with +0 -0, and its badge is U in the list but A in the diff | `DiffRows.swift:56-58`, `DiffRowCell.swift:75` |
| P3 | Return in the branch picker picks a row nothing marks, and ↑/↓ can't change it | `BranchPicker.swift:27-44` |

## Changes, ranked by impact per effort

### Tier 1: trust breakers

1. **Commit size on open.** Call `refreshCommitSize()` in `install`.
   `RepositorySession.swift`. +1.
2. **The right empty state in the diff pane.** Pick one per state:
   - Changes, nothing selected: "Pick a file" / "Press J to start, Space
     to stage, S for a hunk." This also teaches the single keys (criterion 7).
   - Changes, clean tree: shown once, in the diff pane only (see Tier 4, 1).
     The sidebar row becomes a one-line caption.
   - History, nothing selected: add "Choose one on the left, or press J."
   - Branch search with no match: "No branch matches "x"."
   - Research: NN/g empty states (status, learning cue, direct pathway).
   - Files: `DiffPane.swift`, `ChangesView.swift`, `BranchPicker.swift`.
     About +15 / -8.
3. **Errors that say what to do.** One mapping from git stderr and
   `URLError` to plain copy. Keep the raw text in the log and behind a
   "Show Details" button.
   - Rejected push: "The remote has commits you don't have. Pull, then push again."
   - Login failed: "Git couldn't sign in to the remote. Run `git push` once in the terminal (⌘T) so it saves your login."
   - Conflicts: "Fix the files marked ! and stage them, then commit."
   - Lock: the same copy as `GitRepository.swift:218`.
   - Offline: "You look offline. Connect and try again."
   - libgit2 errors: Glint's own context message first.
   - Alerts are titled by what failed ("Couldn't push"). AI setup hints get
     an "Open Settings" button and aren't called failures.
   - Research: NN/g error messages (visible, precise, constructive).
   - Files: new `Git/FriendlyError.swift`, `GitError.swift`, `RootView.swift`,
     the call sites. About +90 / -15.
4. **Keychain save failure.** Show "Couldn't save your key to the Keychain.
   Unlock your login keychain and try again." instead of "Saved".
   `AISettings.swift`, `AISettingsView.swift`. About +6.
5. **No spinner flash.** Don't set `isLoadingDiff` for in-place reloads, and
   show the header spinner only after 150 ms.
   - Research: Nielsen's 0.1 s limit; NN/g on delayed progress indicators.
   - Files: `RepositorySession.swift`, `DiffPane.swift`. About +8 / -3.
6. **Terminal toggle keeps your place.** Keep the diff pane in one slot of
   the split view and collapse the terminal instead of removing it. Remember
   whether it's shown and how tall. Only take focus when you open it.
   `RootView.swift`, `TerminalPanel.swift`, `RepositorySession.swift`.
   About +20 / -12.
7. **Focus follows the key.** Make C from History work (`onChange(initial:)`).
   After a commit, focus leaves the message box so J and K work.
   `CommitPanel.swift`, `+Commit.swift`. About +5.
8. **Tooltips follow your keys.** Build every shortcut hint from
   `ShortcutStore`. One helper, `AppCommand.hint(_:)`, used at the ten call
   sites. About +10 / -10.

### Tier 2: invisible consistency (removes code)

1. **One status badge.** The tinted tile everywhere: sidebar, diff header and
   commit file lists, from one letter and colour table. Untracked is U in
   both places. Binary files say "Binary file, not shown" with no +0 -0.
   About +10 / -40.
2. **One `ChangeStats` view** with monospaced digits, replacing the five
   copies. About +15 / -35.
3. **Staging controls at one size.** The diff header's Stage File and Unstage
   File buttons become `.small`, like the sidebar's. The hunk action gets a
   pointing-hand cursor and a hover tint, since it's drawn text rather than a
   button. `DiffPane.swift`, `DiffTableView.swift`, `DiffRowCell.swift`.
   About +15.
4. **One View All.** Drop the toolbar's View All: the Staged and Changes
   headers already have one each. `ChangesView.swift`. About -8.
5. **One name per command.** Settings > Shortcuts reuses the menu titles.
   Also: "Open Repository…", "Publish Branch", "Get a Key", "Unstaged".
   About ±20.
6. **Type.**
   - The welcome title uses SF Pro (the brand's rule), not Rounded.
   - Inline commit IDs use `.caption.monospaced()`, not 10 and 11 pt literals.
   - The only literal 12 pt is in `DiffMetrics`.
   - About ±8.
7. **Spacing on the grid.** The outliers (1, 3, 5, 11, 14) move to 2, 4, 6,
   10 or 12, and sidebar insets settle on 10. About ±12.
8. **Hit targets.** Undo, sparkles and the picker chevrons get a 22 pt
   minimum hit area. About +6.
9. **Stop symbol.** While AI writes, keep `sparkles` pulsing rather than
   swapping in the larger `stop.circle`. The tooltip still says "Stop
   writing". About -1.

### Tier 3: pacing and restraint

1. **Nothing jumps.**
   - The sync button keeps its label and width while working, with a small
     spinner inside.
   - The AI note row is reserved.
   - The commit summary in History always takes two lines.
   - `+N -N` counts no longer change width.
   - Files: `CommitPanel.swift`, `DiffPane.swift`. About +10 / -8.
2. **Delayed spinners** for commit and sync (150 ms), like the diff header.
   A hookless commit never flashes. About +6.
3. **Slow open.** After 300 ms, show "Opening papercheck…" instead of a blank
   window. The same applies when switching repository. `RootView.swift`.
   About +10.
4. **Remembered state.**
   - Commit message drafts per repository survive a quit, saved after you
     stop typing.
   - The tab stays put when you switch repository.
   - `RepositorySession.swift`. About +20.
5. **Keyboard pickers.** The branch picker highlights the row Return will
   pick, and ↑/↓ move it. The repository picker gets the same list, hover
   and keys. `BranchPicker.swift`, `RepositoryPicker.swift`. About +25 / -15.
6. **Open with the list focused,** so ↑/↓ work before you click.
7. **Increase Contrast.** The 5 to 8 percent tints in the diff rise to about
   16 percent when Increase Contrast is on. `DiffRowCell.swift`. About +6.

### Tier 4: peaks and discovery

1. **"All caught up."** The one peak in daily use. When the tree is clean and
   there's nothing to push, the diff pane says "All caught up" / "Everything's
   committed and pushed." When there are commits to push, it says "3 commits
   to push" with a Push button. It's quiet, uses a system symbol, and has no
   motion.
   - Research: peak-end rule; NN/g empty states as a direct pathway.
2. **Small acknowledgements.**
   - After a commit, the last-commit row shows its short id ("Committed
     a1b2c3d") for 2 s.
   - After a push or pull, the sync button says "Pushed 3" or "Up to date"
     for 2 s.
   - No sound, no burst.
3. **Keys where you look.** "Stage Hunk (S)" tooltips on the hunk action.
   The single keys also go in the J/K empty state (Tier 1, 2).

## What stays as is, and why

- **No new animation.** Speed is the product, and the repeated paths are
  instant on purpose. Reduce Motion needs no work: the only motion is an
  opacity pulse while AI writes.
- **Orange for modified.** It sits near the amber accent, but it's the git
  convention across Zed, VS Code and GitHub Desktop (Jakob's Law). Yellow
  fails contrast on white.
- **System green and red, and system colours throughout.** They already
  follow Increase Contrast and dark mode.
- **The welcome screen and discard dialog copy.** Both are already
  prescriptive.
- **The five speed budgets still over.** They stay in the v0.1 plan as their
  own track. They need profiling, not polish.

## Order of work

Tier 1 in listed order, one commit each. Then Tiers 2, 3 and 4. Screenshots
in light and dark are retaken at the end, and the scorecard is re-scored
here.

## Result (re-scored after the work)

| # | Criterion | Before | After | What changed |
|---|---|---|---|---|
| 1 | Anticipates needs | 1 | 2 | Focus follows the keys, drafts survive a quit, terminal state and History are kept, pickers work from the keyboard |
| 2 | Intentional transitions | 1 | 2 | Delayed spinners, no layout jumps, "Opening…" for slow opens |
| 3 | Delight | 1 | 2 | "Committed a1b2c3d", "Pushed 3", "All caught up" |
| 4 | Knows when not to animate | 2 | 2 | Unchanged: nothing animates on repeated paths |
| 5 | Invisible consistency | 1 | 2 | One badge, one stats view, one name per command, type and grid fixes, tooltips follow your keys |
| 6 | Empty states | 1 | 2 | Every empty state says why and what to do next |
| 7 | Rewards discovery | 1 | 2 | The empty diff pane teaches J, Space and S; Stage Hunk shows its key |
| 8 | Prescriptive errors | 1 | 2 | UserAlert: plain advice, raw text behind Copy Details |
| 9 | Premium performance | 1 | 1 | Slow opens show progress; the five over-budget measurements remain their own track |
