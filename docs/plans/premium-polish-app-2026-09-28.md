# Premium polish: the whole app, second pass

- **Date:** 2026-09-28
- **Scope:** every screen of Glint on macOS, with the new work first:
  JetBrains Mono and the type scale, text size, themes, Minimal mode,
  terminal splits and maximize, and the trimmed Settings
- **Description:** audit against the nine premium-polish criteria, then a
  ranked list of changes
- **Problem:** the new customisation landed fast. Minimal mode strands two
  commands, one old focus bug came back, and a few new controls don't follow
  the rules the rest of the app does

Evidence: three code audits (motion, consistency, states) of the uncommitted
work, and screenshots of Changes (clean tree), History with a commit diff,
Settings and Minimal, in light and dark. The first pass is
`premium-polish-app-2026-09-26.md`; its fixes are rechecked, not re-reported.

## Scorecard

| # | Criterion | Before (09-26 result) | Now | Evidence |
|---|---|---|---|---|
| 1 | Anticipates needs | 2 | 1 | Switching repository with the terminal open takes focus again (`TerminalPanel.swift:527-533`). Maximize leaves focus on the hidden diff, so typing stages files (`+Workspace.swift:41`). Maximize and a hidden sidebar aren't remembered (`RepositorySession.swift:45`, `RootView.swift:5`) |
| 2 | Intentional transitions | 2 | 1 | Minimal's commit box grows in two steps (`CommitPanel.swift:16-19, 73`). ⌘+ and ⌘- keep the pixel offset, not the line you were reading (`DiffTableView.swift:139`). Switching Interface rebuilds the window. Status-line tabs change width when bold (`StatusLine.swift:33`) |
| 3 | Delight | 2 | 2 | Unchanged: "Committed a1b2c3d", "Pushed 3", "All caught up" |
| 4 | Knows when not to animate | 2 | 1 | The commit box collapses with animation after every commit. Nothing reads Reduce Motion (`CommitPanel.swift:73`, `RootView.swift:256`) |
| 5 | Invisible consistency | 2 | 1 | Status colours clash with blue/orange diffs (`Common.swift:36-53`). Status badges don't follow text size (`Common.swift:61`). BranchPicker and the History branch row miss the app font. Settings ignores your accent and contrast (`GlintApp.swift:26`). Four hit targets under 22 pt |
| 6 | Empty states | 2 | 1 | Minimal drops the Pull, Push and Publish buttons but keeps copy that points at them (`AppFont.swift:106`, `DiffPane.swift:97-117`). Docked stacked panes vanish with no sign. `exit` in the last shell starts a new one |
| 7 | Rewards discovery | 2 | 1 | Split keys live only in the menu. Minimal has no way to reach the project switcher (⌥⌘O does nothing) or bring the sidebar back |
| 8 | Prescriptive errors | 2 | 1 | Minimal shows a diff load error as raw text with no title (`DiffPane.swift:10`, `RepositorySession.swift:602`) |
| 9 | Premium performance | 1 | 1 | Unchanged. Font and size lookups are cached per size; no new cost found |

## Bugs (logged in `docs/plans/v0.1-git-panel.md`)

| Sev | Bug | Where |
|---|---|---|
| P1 | Minimal: ⌥⌘O does nothing, and a hidden sidebar can't be brought back | `RootView.swift:213, 296`, `GlintApp.swift:22` |
| P1 | Maximize with ⌘⇧↩: focus stays on the hidden diff, so typed letters stage files | `+Workspace.swift:41-49`, `TerminalPanel.swift:535` |
| P2 | Switching repository with the terminal open takes focus, so J and K stop (regression) | `TerminalPanel.swift:367, 527-533` |
| P2 | Minimal empty states lose Pull, Push and Publish | `AppFont.swift:106-113` |
| P2 | Blue and orange diffs: Renamed reads as Added, Modified as Removed | `Common.swift:36-53` |
| P2 | Text size or theme change: the diff keeps its pixel offset, not your line, and drops line selections | `DiffTableView.swift:139-150` |
| P3 | Closing a pane focuses the first pane, not its neighbour | `TerminalPanel.swift:248-251` |
| P3 | `exit` in the last shell starts a new one instead of hiding the panel | `TerminalPanel.swift:324` |
| P3 | Pane divider cursor reverts mid-drag and can stay stuck | `TerminalPanel.swift:422-425` |
| P3 | Split diff leaves a half-point gap on Retina | `DiffRowCell.swift:172-174` |

## Changes, ranked by impact per effort

### Tier 1: trust breakers

1. **Minimal keeps every command.** The status line gets the project name
   (hosting the switcher popover, so ⌥⌘O works) and a sidebar button. Add
   `SidebarCommands()` so ⌃⌘S and View > Hide Sidebar work in every mode.
   `StatusLine.swift`, `GlintApp.swift`, `RootView.swift`. About +20.
2. **Focus follows the terminal, and only when asked.** Maximize focuses the
   pane you're in. A pane takes focus on attach only when the panel opens, a
   split or tab is made, or the terminal already had focus; never on a
   repository switch. Closing a pane focuses its neighbour.
   `TerminalPanel.swift`, `+Workspace.swift`. About +15 / -5.
3. **Minimal empty states keep their one action.** Minimal drops the icon
   and title, not the button. Diff errors keep "Couldn't load this diff" and
   go through the same plain-copy mapping as alerts. `AppFont.swift`,
   `DiffPane.swift`, `RepositorySession.swift`. About +10 / -4.
4. **Colour-blind mode stays readable.** In blue and orange, Modified and
   Renamed move to colours outside that pair (purple and teal) via Theme
   tokens; the "has changes" dots use the same token.
   `Theme.swift`, `Common.swift`, `RepositoryPicker.swift`,
   `CommitPanel.swift`. About +12 / -8.
5. **Text size keeps your place.** Remember the first visible row before the
   reload and scroll back to it; keep line selections. `DiffTableView.swift`.
   About +8.

### Tier 2: invisible consistency (removes code)

1. **The app font everywhere.** BranchPicker rows and the History branch row
   (a `Label`, which lists restyle) use `.app(.body)`. Settings gets the same
   accent and contrast as the main window; drop the duplicate
   `.themedTextLevels()`. About +6 / -2.
2. **Status badges follow text size.** Tile and letter derive from
   `AppFont.small`; the file header chevron too. `Common.swift`,
   `DiffRowCell.swift`. About ±6.
3. **Two weights, as the brand says.** Small semibold group headers and the
   hunk action become regular; status-line tabs show selection by colour, so
   nothing changes width. About ±6.
4. **Hit targets ≥22 pt.** Accent swatches (22 pt frame, 16 pt fill, spaced
   so the ring fits, `.isSelected` trait), tab close, status-line icons,
   branch-bar chevrons. About +8.
5. **One of each.** The terminal button is one view used by the toolbar and
   the status line. ProjectSwitcher uses the shared `.highlighted` style and
   `AppCommand.openRepository.title`. Spacing literals move onto the grid
   (14 → 12, 5 → 6, 3 → 4, 20 → 16). About +10 / -20.
6. **Onboarding symbol** sized from the type scale, not `.system(size: 48)`.

### Tier 3: pacing and restraint

1. **Minimal's commit box grows in one step and collapses instantly.** One
   motion value, no animation on the collapse after a commit, none at all
   with Reduce Motion. Same for the sidebar button. `CommitPanel.swift`,
   `RootView.swift`, a `Motion` token in `Theme.swift`. About +8 / -3.
2. **Switching Interface or glass keeps your place.** Conditions move inside
   the toolbar and inset content instead of branching the whole view, so the
   window isn't rebuilt. Drop `.id(usesLiquidGlass)` if the toolbar updates
   without it; keep it otherwise. `RootView.swift`, `SidebarView.swift`.
   About ±15.
3. **Remember maximize and the sidebar.** Saved like `isTerminalShown`.
   About +6.
4. **Pane divider cursor** uses `pointerStyle(.frameResize)`, so it holds
   through a drag. About -4.
5. **`exit` in the last shell hides the panel.** About +3.

### Tier 4: peaks and discovery

1. **Keys where you look.** A Split button in the terminal's tab strip (its
   tooltip shows ⌘D; ⌥-click splits down), and a pane context menu: Split
   Right, Split Down, Close Pane, each with its key. Text size and External
   terminal get their keys back as tooltips.
2. **Hidden panes say so.** While docked, the tab strip shows "+1 pane" when
   a stack is folded; clicking it expands the terminal.
3. **Settings labels that stand alone.** Interface gets a tooltip ("Minimal:
   no toolbar, one status line at the bottom"). "Most useful first" becomes
   "Source first". One spelling: "Diff colors" to match the rest of the UI.
   Onboarding says ✨ like Settings.

## What stays as is, and why

- **No new animation beyond the commit box.** Splits, maximize, text size and
  tab switches stay instant: they're repeated paths.
- **Two tab switchers.** The segmented picker (Standard) and the status-line
  tabs (Minimal) never show together.
- **Liquid Glass off leaves the sidebar and menus in glass.** macOS offers no
  app switch for those; recorded in `Theme.swift`.
- **Errors in red.** Consistent across Settings, onboarding and alerts.
- **Terminal tabs' own selection tint (primary 8%).** Tabs aren't list
  selection; a softer tint keeps the strip quiet.

## Order of work

Tier 1 in order, one commit each, then Tiers 2 to 4. Build and tests after
each tier; screenshots in light, dark and Minimal at the end, then re-score
here.

## Result (re-scored after the work)

| # | Criterion | Before | After | What changed |
|---|---|---|---|---|
| 1 | Anticipates needs | 1 | 2 | Focus goes to the terminal only when you ask for it; maximize puts you in the shell; closing a pane moves to its neighbour; sidebar and maximize are remembered |
| 2 | Intentional transitions | 1 | 2 | Commit box grows in one step; text size and theme keep your line and selections; status-line tabs don't shift |
| 3 | Delight | 2 | 2 | Unchanged |
| 4 | Knows when not to animate | 1 | 2 | One `Motion.reveal` token, off with Reduce Motion; no animation after commits |
| 5 | Invisible consistency | 1 | 2 | App font in every list; badges follow text size; two weights; 22 pt targets; status colours clear of the diff pair; one terminal toggle |
| 6 | Empty states | 1 | 2 | Minimal keeps Pull, Push and Publish; folded panes say "+1 pane"; `exit` hides the panel |
| 7 | Rewards discovery | 1 | 2 | Minimal reaches every command (status line, ⌃⌘S, ⌃⌘M); Split button with keys; Settings tooltips name their keys |
| 8 | Prescriptive errors | 1 | 2 | Diff load errors in plain words, titled in Minimal |
| 9 | Premium performance | 1 | 1 | Unchanged; the budgets remain their own track |

Also done during the pass, on request: Zed's fonts (IBM Plex Sans for the
interface, Lilex for code) replace JetBrains Mono, and ⌃⌘M toggles Minimal.

Not done: Tier 3.2 (switching Interface or Liquid Glass still rebuilds the
window, losing scroll). macOS 15's toolbar builder can't drop items
conditionally without a rebuild; it's a rare, deliberate switch. The pane
context menu from Tier 4.1 is left out: SwiftTerm owns the terminal's
right-click.
