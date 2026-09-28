import AppKit
@preconcurrency import SwiftTerm
import SwiftUI

/// Glint's terminal: SwiftTerm's local-process view, following light and dark
/// mode. `KeyMonitor` recognises it and leaves typing here alone.
final class GlintTerminalView: LocalProcessTerminalView {
  /// Called when you click into this pane, so the tab knows which pane
  /// you're in. SwiftTerm's responder methods can't be overridden, so a
  /// click recognizer that doesn't hold back the click stands in.
  var onFocus: (() -> Void)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
    click.delaysPrimaryMouseButtonEvents = false
    addGestureRecognizer(click)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  @objc private func clicked() {
    onFocus?()
  }

  enum PaneCommand: Int {
    case splitRight, splitDown, close
  }

  /// Runs a pane command from the right-click menu, for this pane.
  var onPaneCommand: ((PaneCommand) -> Void)?

  /// Right-click: copy and paste, then the pane commands with their keys.
  /// The pane you right-click becomes the one you're in.
  override func menu(for event: NSEvent) -> NSMenu? {
    onFocus?()
    let menu = NSMenu()
    menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
    menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(paneItem("Split Right", .splitRight, AppCommand.splitTerminalRight))
    menu.addItem(paneItem("Split Down", .splitDown, AppCommand.splitTerminalDown))
    menu.addItem(.separator())
    menu.addItem(paneItem("Close Pane", .close, AppCommand.closeTerminalTab))
    return menu
  }

  private func paneItem(_ title: String, _ command: PaneCommand, _ shortcut: AppCommand) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(runPaneCommand(_:)), keyEquivalent: "")
    item.target = self
    item.tag = command.rawValue
    // Shows your key for it, as the menu bar does.
    if let key = ShortcutStore.shared.shortcut(for: shortcut), key.key.count == 1 {
      item.keyEquivalent = key.key
      var flags: NSEvent.ModifierFlags = []
      if key.command { flags.insert(.command) }
      if key.option { flags.insert(.option) }
      if key.control { flags.insert(.control) }
      if key.shift { flags.insert(.shift) }
      item.keyEquivalentModifierMask = flags
    }
    return item
  }

  @objc private func runPaneCommand(_ sender: NSMenuItem) {
    guard let command = PaneCommand(rawValue: sender.tag) else { return }
    onPaneCommand?(command)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColors()
  }

  func applyColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      nativeBackgroundColor = .textBackgroundColor
      nativeForegroundColor = .textColor
      caretColor = Theme.shared.accentColor
    }
  }
}

enum PaneDirection: Sendable {
  case left, right, up, down
}

/// `.horizontal` puts panes side by side, `.vertical` stacks them.
enum SplitAxis: Sendable {
  case horizontal, vertical
}

/// How a tab's shells are arranged: one pane, or two arrangements side by
/// side (`.horizontal`) or stacked (`.vertical`), nested like tmux splits.
@MainActor
indirect enum PaneLayout {
  case pane(GlintTerminalView)
  case split(id: UUID, axis: SplitAxis, first: PaneLayout, second: PaneLayout)

  var panes: [GlintTerminalView] {
    switch self {
    case .pane(let view): [view]
    case .split(_, _, let first, let second): first.panes + second.panes
    }
  }

  func replacing(_ target: GlintTerminalView, with replacement: PaneLayout) -> PaneLayout {
    switch self {
    case .pane(let view): view === target ? replacement : self
    case .split(let id, let axis, let first, let second):
      .split(
        id: id, axis: axis, first: first.replacing(target, with: replacement),
        second: second.replacing(target, with: replacement))
    }
  }

  /// The layout without `target`, its sibling taking the space. Nil when
  /// `target` was the only pane.
  func removing(_ target: GlintTerminalView) -> PaneLayout? {
    switch self {
    case .pane(let view): return view === target ? nil : self
    case .split(let id, let axis, let first, let second):
      guard let newFirst = first.removing(target) else { return second }
      guard let newSecond = second.removing(target) else { return first }
      return .split(id: id, axis: axis, first: newFirst, second: newSecond)
    }
  }

  /// The pane to move to when `target` closes: the nearest one on the other
  /// side of its split, like tmux.
  func neighbour(of target: GlintTerminalView) -> GlintTerminalView? {
    guard case .split(_, _, let first, let second) = self else { return nil }
    if case .pane(let view) = first, view === target { return second.panes.first }
    if case .pane(let view) = second, view === target { return first.panes.last }
    return first.neighbour(of: target) ?? second.neighbour(of: target)
  }

  /// Panes folded away while docked: each stack shows only the side you're
  /// in, so the other side's panes are hidden.
  func foldedCount(focused: GlintTerminalView) -> Int {
    switch self {
    case .pane: return 0
    case .split(_, let axis, let first, let second):
      guard axis == .vertical else {
        return first.foldedCount(focused: focused) + second.foldedCount(focused: focused)
      }
      let (shown, hidden) = first.panes.contains { $0 === focused } ? (first, second) : (second, first)
      return hidden.panes.count + shown.foldedCount(focused: focused)
    }
  }

  /// Where each pane sits, for moving focus by direction.
  func frames(in rect: CGRect, fractions: [UUID: CGFloat]) -> [(GlintTerminalView, CGRect)] {
    switch self {
    case .pane(let view): return [(view, rect)]
    case .split(let id, let axis, let first, let second):
      let fraction = fractions[id] ?? 0.5
      let (a, b) =
        axis == .horizontal
        ? rect.divided(atDistance: rect.width * fraction, from: .minXEdge)
        : rect.divided(atDistance: rect.height * fraction, from: .minYEdge)
      return first.frames(in: a, fractions: fractions) + second.frames(in: b, fractions: fractions)
    }
  }
}

/// One terminal tab: one or more shells in split panes, and the pane you're
/// in. The tab shows that pane's title (usually the running command or the
/// folder).
@MainActor
@Observable
final class TerminalTab: Identifiable {
  let id = UUID()
  var layout: PaneLayout
  var focused: GlintTerminalView
  /// Each split's share for its first side, by split id. 0.5 when unset.
  var fractions: [UUID: CGFloat] = [:]
  var titles: [ObjectIdentifier: String] = [:]
  /// Set when you asked for the terminal (opened it, split, switched tab,
  /// closed a pane), so the pane you're in takes focus once it's on screen.
  /// Never set by a repository switch, which would swallow J and K.
  @ObservationIgnored var wantsFocus = false
  private let folderName: String

  init(view: GlintTerminalView, folderName: String) {
    layout = .pane(view)
    focused = view
    self.folderName = folderName
  }

  var title: String { titles[ObjectIdentifier(focused)] ?? folderName }

  /// True once, for the pane you're in, when focus was asked for.
  func claimFocus(_ view: GlintTerminalView) -> Bool {
    guard wantsFocus, focused === view else { return false }
    wantsFocus = false
    return true
  }
  var panes: [GlintTerminalView] { layout.panes }
}

/// Each repository's terminal tabs, kept running while the panel is hidden,
/// so showing it again puts you back where you were. A pane whose shell exits
/// closes, and a tab closes with its last pane.
@MainActor
@Observable
final class TerminalStore: NSObject, LocalProcessTerminalViewDelegate {
  private(set) var tabs: [URL: [TerminalTab]] = [:]
  private(set) var selected: [URL: UUID] = [:]
  /// Called when a repository's last tab closes on its own (you typed
  /// `exit`), so the panel hides instead of starting a new shell.
  @ObservationIgnored var lastTabClosed: (URL) -> Void = { _ in }
  /// Runs a right-click pane command through the session, which knows to
  /// expand the terminal before stacking and to hide it after the last pane.
  @ObservationIgnored var paneCommand: (GlintTerminalView.PaneCommand, URL) -> Void = { _, _ in }
  @ObservationIgnored private var textSizeObserver: NSObjectProtocol?
  @ObservationIgnored private var themeObserver: NSObjectProtocol?

  override init() {
    super.init()
    // Every shell follows your text size, including ones in hidden tabs
    // and other repositories.
    textSizeObserver = NotificationCenter.default.addObserver(
      forName: TextSize.didChange, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        let font = AppFont.ns(size: AppFont.codeBody)
        for view in self?.tabs.values.flatMap({ $0 }).flatMap(\.panes) ?? [] { view.font = font }
      }
    }
    themeObserver = NotificationCenter.default.addObserver(
      forName: Theme.didChange, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        for view in self?.tabs.values.flatMap({ $0 }).flatMap(\.panes) ?? [] { view.applyColors() }
      }
    }
  }

  func tabs(for folder: URL) -> [TerminalTab] { tabs[folder.standardizedFileURL] ?? [] }

  /// The selected tab, if the repository has any.
  func current(for folder: URL) -> TerminalTab? {
    let key = folder.standardizedFileURL
    let list = tabs[key] ?? []
    if let id = selected[key], let tab = list.first(where: { $0.id == id }) { return tab }
    return list.first
  }

  /// A new shell in its own tab. `focus` is false for the first shell a
  /// repository gets on its own (at launch, or switching to it), so the
  /// diff keeps your keys.
  @discardableResult
  func newTab(for folder: URL, focus: Bool = true) -> TerminalTab {
    let key = folder.standardizedFileURL
    let tab = TerminalTab(view: makeShell(in: key), folderName: key.lastPathComponent)
    tabs[key, default: []].append(tab)
    selected[key] = tab.id
    if focus { focusSoon(tab) }
    return tab
  }

  /// Splits the pane you're in and moves you to the new shell: `.horizontal`
  /// puts it on the right, `.vertical` below.
  func split(_ axis: SplitAxis, in folder: URL) {
    guard let tab = current(for: folder) else { return }
    let shell = makeShell(in: folder.standardizedFileURL)
    tab.layout = tab.layout.replacing(
      tab.focused, with: .split(id: UUID(), axis: axis, first: .pane(tab.focused), second: .pane(shell)))
    tab.focused = shell
    focusSoon(tab)
  }

  /// Closes the pane you're in, or its tab when it's the last pane. Returns
  /// false when that was the last tab.
  @discardableResult
  func closePane(in folder: URL) -> Bool {
    guard let tab = current(for: folder) else { return true }
    return closePane(tab.focused, of: tab, in: folder)
  }

  /// Moves you to the nearest pane in `direction`, like tmux's arrow keys.
  func moveFocus(_ direction: PaneDirection, in folder: URL) {
    guard let tab = current(for: folder) else { return }
    let frames = tab.layout.frames(in: CGRect(x: 0, y: 0, width: 1, height: 1), fractions: tab.fractions)
    guard let from = frames.first(where: { $0.0 === tab.focused })?.1 else { return }
    let epsilon = 0.001
    let candidates = frames.filter { _, frame in
      switch direction {
      case .left: frame.maxX <= from.minX + epsilon && frame.minY < from.maxY && frame.maxY > from.minY
      case .right: frame.minX >= from.maxX - epsilon && frame.minY < from.maxY && frame.maxY > from.minY
      case .up: frame.maxY <= from.minY + epsilon && frame.minX < from.maxX && frame.maxX > from.minX
      case .down: frame.minY >= from.maxY - epsilon && frame.minX < from.maxX && frame.maxX > from.minX
      }
    }
    let distance = { (frame: CGRect) in hypot(frame.midX - from.midX, frame.midY - from.midY) }
    guard let target = candidates.min(by: { distance($0.1) < distance($1.1) })?.0 else { return }
    tab.focused = target
    // A docked stack may bring this pane on screen first.
    focusSoon(tab)
  }

  /// Puts you in the terminal: the pane you're in takes focus once it's on
  /// screen. For showing the panel and maximizing it.
  func requestFocus(in folder: URL) {
    guard let tab = current(for: folder) else { return }
    focusSoon(tab)
  }

  private func focusSoon(_ tab: TerminalTab) {
    tab.wantsFocus = true
    // If the pane is already on screen and isn't re-hosted, no container
    // attaches to claim it; take focus after this layout pass instead.
    DispatchQueue.main.async { [weak tab] in
      guard let tab, tab.wantsFocus, let window = tab.focused.window else { return }
      tab.wantsFocus = false
      window.makeFirstResponder(tab.focused)
    }
  }

  func select(_ tab: TerminalTab, in folder: URL) {
    selected[folder.standardizedFileURL] = tab.id
    focusSoon(tab)
  }

  /// Moves to the next or previous tab, wrapping around.
  func cycle(_ step: Int, in folder: URL) {
    let list = tabs(for: folder)
    guard list.count > 1, let index = list.firstIndex(where: { $0.id == current(for: folder)?.id }) else { return }
    select(list[(index + step + list.count) % list.count], in: folder)
  }

  /// Closes a tab and ends its shells. Returns false when it was the last one.
  @discardableResult
  func close(_ tab: TerminalTab, in folder: URL) -> Bool {
    let key = folder.standardizedFileURL
    guard var list = tabs[key], let index = list.firstIndex(where: { $0.id == tab.id }) else { return true }
    list.remove(at: index)
    for view in tab.panes {
      view.terminate()
      view.removeFromSuperview()
    }
    tabs[key] = list
    if selected[key] == tab.id { selected[key] = list.isEmpty ? nil : list[max(0, index - 1)].id }
    return !list.isEmpty
  }

  private func closePane(_ view: GlintTerminalView, of tab: TerminalTab, in folder: URL) -> Bool {
    guard let rest = tab.layout.removing(view) else { return close(tab, in: folder) }
    let neighbour = tab.layout.neighbour(of: view)
    tab.layout = rest
    tab.titles[ObjectIdentifier(view)] = nil
    view.terminate()
    view.removeFromSuperview()
    if tab.focused === view, let next = neighbour ?? rest.panes.first {
      tab.focused = next
      focusSoon(tab)
    }
    return true
  }

  private func makeShell(in folder: URL) -> GlintTerminalView {
    let start = ContinuousClock.now
    let view = GlintTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
    view.font = AppFont.ns(size: AppFont.codeBody)
    view.applyColors()
    view.processDelegate = self
    view.onFocus = { [weak self, weak view] in
      guard let self, let view, let (_, tab) = self.find(view) else { return }
      tab.focused = view
    }
    view.onPaneCommand = { [weak self, weak view] command in
      guard let self, let view, let (folder, tab) = self.find(view) else { return }
      tab.focused = view
      self.paneCommand(command, folder)
    }
    Task {
      let environment = await Self.environment()
      let shell = environment["SHELL"] ?? "/bin/zsh"
      // A leading dash in argv[0] makes it a login shell, like a new
      // Terminal window.
      view.startProcess(
        executable: shell, args: [],
        environment: environment.map { "\($0.key)=\($0.value)" },
        execName: "-" + (shell as NSString).lastPathComponent,
        currentDirectory: folder.path)
      Timing.report("terminal started", since: start, budget: 100)
    }
    return view
  }

  /// Your environment with your login shell's PATH, minus the settings Glint
  /// uses to keep its own git calls non-interactive.
  private static func environment() async -> [String: String] {
    var variables = await LoginEnvironment.shared.value.variables
    variables["GIT_TERMINAL_PROMPT"] = nil
    variables["GIT_EDITOR"] = nil
    variables["TERM"] = "xterm-256color"
    variables["COLORTERM"] = "truecolor"
    if variables["LANG"] == nil { variables["LANG"] = "en_US.UTF-8" }
    return variables
  }

  private func find(_ source: AnyObject) -> (URL, TerminalTab)? {
    for (folder, list) in tabs {
      if let tab = list.first(where: { tab in tab.panes.contains { $0 === source } }) { return (folder, tab) }
    }
    return nil
  }

  /// Shells title themselves `user@host:path`; the folder is the part worth
  /// a tab's width. Anything else, like a running command, stays as is.
  nonisolated static func shortTitle(_ title: String) -> String {
    guard let colon = title.firstIndex(of: ":"), title[..<colon].contains("@") else { return title }
    let path = title[title.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    guard !path.isEmpty, path != "~" else { return path.isEmpty ? title : "~" }
    return (path as NSString).lastPathComponent
  }

  // MARK: LocalProcessTerminalViewDelegate

  nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
  nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

  nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
    let short = Self.shortTitle(title)
    Task { @MainActor in
      guard !short.isEmpty, let (_, tab) = self.find(source) else { return }
      tab.titles[ObjectIdentifier(source)] = short
    }
  }

  nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
    Task { @MainActor in
      guard let (folder, tab) = self.find(source), let view = source as? GlintTerminalView else { return }
      if !self.closePane(view, of: tab, in: folder) { self.lastTabClosed(folder) }
    }
  }
}

/// The panel under the diff: a strip of tabs, and the selected tab's panes.
struct TerminalPanel: View {
  let folder: URL
  let store: TerminalStore
  let isMaximized: Bool
  let toggleMaximized: () -> Void
  let split: (SplitAxis) -> Void
  let hide: () -> Void

  var body: some View {
    if let current = store.current(for: folder) {
      VStack(spacing: 0) {
        TerminalTabStrip(
          folder: folder, store: store, current: current, isMaximized: isMaximized,
          toggleMaximized: toggleMaximized, split: split, hide: hide)
        PaneLayoutView(layout: current.layout, tab: current, isDocked: !isMaximized)
      }
    } else {
      // First time for this repository: start its first shell.
      Color.clear.onAppear { store.newTab(for: folder, focus: false) }
    }
  }
}

/// A tab's panes, drawn recursively. Panes you're not in are dimmed, like
/// Ghostty's unfocused splits, so you can tell where your typing goes.
/// Docked under the diff there's no height to stack panes, so each stack
/// shows only the side you're in; the others keep running and come back
/// when the terminal expands.
private struct PaneLayoutView: View {
  let layout: PaneLayout
  let tab: TerminalTab
  let isDocked: Bool

  var body: some View {
    switch layout {
    case .pane(let view):
      let isFocused = tab.focused === view
      TerminalHost(terminal: view, claimFocus: { tab.claimFocus(view) })
        .id(ObjectIdentifier(view))
        .overlay {
          if !isFocused {
            Color(nsColor: .textBackgroundColor).opacity(0.4).allowsHitTesting(false)
          }
        }
    case .split(_, .vertical, let first, let second) where isDocked:
      let focusedIsFirst = first.panes.contains { $0 === tab.focused }
      PaneLayoutView(layout: focusedIsFirst ? first : second, tab: tab, isDocked: true)
    case .split(let id, let axis, let first, let second):
      PaneSplit(
        axis: axis,
        fraction: Binding(get: { tab.fractions[id] ?? 0.5 }, set: { tab.fractions[id] = $0 })
      ) {
        PaneLayoutView(layout: first, tab: tab, isDocked: isDocked)
      } second: {
        PaneLayoutView(layout: second, tab: tab, isDocked: isDocked)
      }
    }
  }
}

/// Two panes and a divider you drag to resize them.
private struct PaneSplit<First: View, Second: View>: View {
  let axis: SplitAxis
  @Binding var fraction: CGFloat
  @ViewBuilder let first: First
  @ViewBuilder let second: Second
  @State private var dragStart: CGFloat?

  var body: some View {
    GeometryReader { geometry in
      let total = axis == .horizontal ? geometry.size.width : geometry.size.height
      let firstSize = max(0, (total - 1) * fraction)
      if axis == .horizontal {
        HStack(spacing: 0) {
          first.frame(width: firstSize)
          divider(total: total)
          second
        }
      } else {
        VStack(spacing: 0) {
          first.frame(height: firstSize)
          divider(total: total)
          second
        }
      }
    }
  }

  private func divider(total: CGFloat) -> some View {
    Hairline(axis: axis == .horizontal ? .vertical : .horizontal)
      .padding(axis == .horizontal ? .horizontal : .vertical, 3)
      .contentShape(Rectangle())
      .padding(axis == .horizontal ? .horizontal : .vertical, -3)
      // Holds through a drag, unlike a pushed cursor.
      .pointerStyle(axis == .horizontal ? .columnResize : .rowResize)
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
          .onChanged { drag in
            let start = dragStart ?? fraction
            dragStart = start
            let moved = axis == .horizontal ? drag.translation.width : drag.translation.height
            fraction = min(0.85, max(0.15, start + moved / max(total, 1)))
          }
          .onEnded { _ in dragStart = nil })
  }
}

private struct TerminalTabStrip: View {
  let folder: URL
  let store: TerminalStore
  let current: TerminalTab
  let isMaximized: Bool
  let toggleMaximized: () -> Void
  let split: (SplitAxis) -> Void
  let hide: () -> Void

  var body: some View {
    let folded = isMaximized ? 0 : current.layout.foldedCount(focused: current.focused)
    HStack(spacing: 2) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 2) {
          ForEach(store.tabs(for: folder)) { tab in
            TerminalTabButton(
              title: tab.title, isSelected: tab.id == current.id,
              select: { store.select(tab, in: folder) },
              close: { if !store.close(tab, in: folder) { hide() } })
          }
        }
      }
      // Stacked panes fold away while docked; say so, and expand on click.
      if folded > 0 {
        Button(folded == 1 ? "+1 pane" : "+\(folded) panes", action: toggleMaximized)
          .buttonStyle(.borderless)
          .font(.app(.caption))
          .foregroundStyle(.secondary)
          .help(AppCommand.maximizeTerminal.hint("Expand the terminal to see every pane"))
      }
      Button {
        split(NSEvent.modifierFlags.contains(.option) ? .vertical : .horizontal)
      } label: {
        Image(systemName: "rectangle.split.2x1").hitTarget()
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Split terminal")
      .help(AppCommand.splitTerminalRight.hint("Split right") + ". " + AppCommand.splitTerminalDown.hint("Option-click splits down"))
      Button {
        store.newTab(for: folder)
      } label: {
        Image(systemName: "plus").hitTarget()
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("New terminal tab")
      .help(AppCommand.newTerminalTab.hint("New tab"))
      Button(action: toggleMaximized) {
        Image(
          systemName: isMaximized
            ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        ).hitTarget()
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(isMaximized ? "Restore Terminal" : "Maximize Terminal")
      .help(AppCommand.maximizeTerminal.hint(isMaximized ? "Put the diff back" : "Give the terminal the diff's space"))
    }
    .padding(.horizontal, 6)
    // Matches the branch bar beside it, so the dividers line up.
    .frame(height: 30)
    .background(.bar)
  }
}

private struct TerminalTabButton: View {
  let title: String
  let isSelected: Bool
  let select: () -> Void
  let close: () -> Void
  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 4) {
      Button(action: select) {
        Text(title)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: 180)
          .padding(.leading, 8)
          .padding(.vertical, 3)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      Button(action: close) {
        Image(systemName: "xmark")
          .font(.app(.caption2))
          .hitTarget()
      }
      .buttonStyle(.plain)
      .opacity(isHovered || isSelected ? 1 : 0)
      .accessibilityLabel("Close tab")
      .help("Close tab")
      .padding(.trailing, 4)
    }
    .font(.app(.callout))
    .foregroundStyle(isSelected ? .primary : .secondary)
    .background(
      RoundedRectangle(cornerRadius: 5).fill(isSelected ? Color.primary.opacity(0.08) : .clear))
    .onHover { isHovered = $0 }
  }
}

/// Hosts one terminal view. Switching tabs or rearranging panes re-parents
/// the shell's view into a new container, so shells keep running while
/// hidden.
private struct TerminalHost: NSViewRepresentable {
  let terminal: GlintTerminalView
  /// True when you asked for the terminal and this is the pane you're in.
  let claimFocus: () -> Bool

  func makeNSView(context: Context) -> PaneContainer {
    let container = PaneContainer()
    container.terminal = terminal
    container.claimFocus = claimFocus
    return container
  }

  func updateNSView(_ container: PaneContainer, context: Context) {
    container.claimFocus = claimFocus
    guard container.terminal !== terminal else { return }
    container.terminal = terminal
    container.attach()
  }

  /// Takes its terminal when it joins the window, not when SwiftUI updates
  /// it: while panes rearrange, the outgoing container is still updated and
  /// would otherwise pull the shell back out of the incoming one.
  final class PaneContainer: NSView {
    var terminal: GlintTerminalView?
    var claimFocus: () -> Bool = { false }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      attach()
    }

    func attach() {
      guard window != nil, let terminal, terminal.superview !== self else { return }
      subviews.forEach { $0.removeFromSuperview() }
      terminal.translatesAutoresizingMaskIntoConstraints = false
      addSubview(terminal)
      NSLayoutConstraint.activate([
        terminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
        terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
        terminal.topAnchor.constraint(equalTo: topAnchor, constant: 4),
        terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
      if claimFocus() {
        DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
      }
    }
  }
}
