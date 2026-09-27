import AppKit
@preconcurrency import SwiftTerm
import SwiftUI

/// Glint's terminal: SwiftTerm's local-process view, following light and dark
/// mode. `KeyMonitor` recognises it and leaves typing here alone.
final class GlintTerminalView: LocalProcessTerminalView {
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyColors()
  }

  func applyColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      nativeBackgroundColor = .textBackgroundColor
      nativeForegroundColor = .textColor
      caretColor = .controlAccentColor
    }
  }
}

/// One terminal tab: a shell and the title it sets (usually the running
/// command or the folder).
@MainActor
final class TerminalTab: Identifiable {
  let id = UUID()
  let view: GlintTerminalView
  var title: String

  init(view: GlintTerminalView, title: String) {
    self.view = view
    self.title = title
  }
}

/// Each repository's terminal tabs, kept running while the panel is hidden,
/// so showing it again puts you back where you were. A tab whose shell exits
/// closes.
@MainActor
@Observable
final class TerminalStore: NSObject, LocalProcessTerminalViewDelegate {
  private(set) var tabs: [URL: [TerminalTab]] = [:]
  private(set) var selected: [URL: UUID] = [:]
  /// Bumped when a tab's title changes, so the strip redraws.
  private(set) var titlesVersion = 0

  func tabs(for folder: URL) -> [TerminalTab] { tabs[folder.standardizedFileURL] ?? [] }

  /// The selected tab, if the repository has any.
  func current(for folder: URL) -> TerminalTab? {
    let key = folder.standardizedFileURL
    let list = tabs[key] ?? []
    if let id = selected[key], let tab = list.first(where: { $0.id == id }) { return tab }
    return list.first
  }

  @discardableResult
  func newTab(for folder: URL) -> TerminalTab {
    let key = folder.standardizedFileURL
    let start = ContinuousClock.now
    let view = GlintTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
    view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    view.applyColors()
    view.processDelegate = self
    let tab = TerminalTab(view: view, title: key.lastPathComponent)
    tabs[key, default: []].append(tab)
    selected[key] = tab.id
    Task {
      let environment = await Self.environment()
      let shell = environment["SHELL"] ?? "/bin/zsh"
      // A leading dash in argv[0] makes it a login shell, like a new
      // Terminal window.
      view.startProcess(
        executable: shell, args: [],
        environment: environment.map { "\($0.key)=\($0.value)" },
        execName: "-" + (shell as NSString).lastPathComponent,
        currentDirectory: key.path)
      Timing.report("terminal started", since: start, budget: 100)
    }
    return tab
  }

  func select(_ tab: TerminalTab, in folder: URL) {
    selected[folder.standardizedFileURL] = tab.id
  }

  /// Moves to the next or previous tab, wrapping around.
  func cycle(_ step: Int, in folder: URL) {
    let list = tabs(for: folder)
    guard list.count > 1, let index = list.firstIndex(where: { $0.id == current(for: folder)?.id }) else { return }
    select(list[(index + step + list.count) % list.count], in: folder)
  }

  /// Closes a tab and ends its shell. Returns false when it was the last one.
  @discardableResult
  func close(_ tab: TerminalTab, in folder: URL) -> Bool {
    let key = folder.standardizedFileURL
    guard var list = tabs[key], let index = list.firstIndex(where: { $0.id == tab.id }) else { return true }
    list.remove(at: index)
    tab.view.terminate()
    tab.view.removeFromSuperview()
    tabs[key] = list
    if selected[key] == tab.id { selected[key] = list.isEmpty ? nil : list[max(0, index - 1)].id }
    return !list.isEmpty
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
      if let tab = list.first(where: { $0.view === source }) { return (folder, tab) }
    }
    return nil
  }

  // MARK: LocalProcessTerminalViewDelegate

  nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
  nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

  nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
    let id = ObjectIdentifier(source)
    Task { @MainActor in
      guard let (_, tab) = self.find(source), ObjectIdentifier(tab.view) == id, !title.isEmpty else { return }
      tab.title = title
      self.titlesVersion += 1
    }
  }

  nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
    Task { @MainActor in
      guard let (folder, tab) = self.find(source) else { return }
      self.close(tab, in: folder)
    }
  }
}

/// The panel under the diff: a strip of tabs, and the selected tab's shell.
struct TerminalPanel: View {
  let folder: URL
  let store: TerminalStore
  let hide: () -> Void

  var body: some View {
    if let current = store.current(for: folder) {
      VStack(spacing: 0) {
        TerminalTabStrip(folder: folder, store: store, current: current, hide: hide)
        TerminalHost(terminal: current.view)
      }
    } else {
      // First time for this repository: start its first shell.
      Color.clear.onAppear { store.newTab(for: folder) }
    }
  }
}

private struct TerminalTabStrip: View {
  let folder: URL
  let store: TerminalStore
  let current: TerminalTab
  let hide: () -> Void

  var body: some View {
    let _ = store.titlesVersion
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
      Button {
        store.newTab(for: folder)
      } label: {
        Image(systemName: "plus").hitTarget()
      }
      .buttonStyle(.borderless)
      .help(AppCommand.newTerminalTab.hint("New tab"))
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
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
          .font(.caption2.weight(.semibold))
          .frame(width: 16, height: 16)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .opacity(isHovered || isSelected ? 1 : 0)
      .help(AppCommand.closeTerminalTab.hint("Close tab"))
      .padding(.trailing, 4)
    }
    .font(.callout)
    .foregroundStyle(isSelected ? .primary : .secondary)
    .background(
      RoundedRectangle(cornerRadius: 5).fill(isSelected ? Color.primary.opacity(0.08) : .clear))
    .onHover { isHovered = $0 }
  }
}

/// Hosts one terminal view. Switching tabs re-parents the chosen shell's view
/// into this container, so shells keep running while hidden.
private struct TerminalHost: NSViewRepresentable {
  let terminal: GlintTerminalView

  func makeNSView(context: Context) -> NSView {
    let container = NSView()
    show(in: container, focus: true)
    return container
  }

  func updateNSView(_ container: NSView, context: Context) {
    show(in: container, focus: false)
  }

  private func show(in container: NSView, focus: Bool) {
    guard terminal.superview !== container else { return }
    let hadFocus = container.window?.firstResponder is GlintTerminalView
    container.subviews.forEach { $0.removeFromSuperview() }
    terminal.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(terminal)
    NSLayoutConstraint.activate([
      terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
      terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      terminal.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
      terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    // Focus when the panel opens, or when switching tabs from inside the
    // terminal; never on a repository switch, which would swallow j and k.
    if focus || hadFocus { DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) } }
  }
}
