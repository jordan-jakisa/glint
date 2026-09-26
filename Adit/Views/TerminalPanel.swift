import AppKit
@preconcurrency import SwiftTerm
import SwiftUI

/// Adit's terminal: SwiftTerm's local-process view, following light and dark
/// mode. `KeyMonitor` recognises it and leaves typing here alone.
final class AditTerminalView: LocalProcessTerminalView {
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

/// One shell per repository, kept running while the panel is hidden, so
/// showing it again puts you back where you were. A shell you've exited is
/// replaced next time the panel is shown.
@MainActor
final class TerminalStore: NSObject, LocalProcessTerminalViewDelegate {
  private var terminals: [URL: AditTerminalView] = [:]
  private var ended: Set<ObjectIdentifier> = []

  func terminal(for folder: URL) -> AditTerminalView {
    let key = folder.standardizedFileURL
    if let existing = terminals[key], !ended.contains(ObjectIdentifier(existing)) { return existing }
    let start = ContinuousClock.now
    let view = AditTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
    view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    view.applyColors()
    view.processDelegate = self
    terminals[key] = view
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
    return view
  }

  /// Your environment with your login shell's PATH, minus the settings Adit
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

  // MARK: LocalProcessTerminalViewDelegate

  nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
  nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
  nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

  nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
    let id = ObjectIdentifier(source)
    Task { @MainActor in self.ended.insert(id) }
  }
}

/// The panel under the diff. Hosts the active repository's terminal.
struct TerminalPanel: NSViewRepresentable {
  let folder: URL
  let store: TerminalStore

  func makeNSView(context: Context) -> NSView {
    let container = NSView()
    show(in: container, focus: true)
    return container
  }

  func updateNSView(_ container: NSView, context: Context) {
    show(in: container, focus: false)
  }

  private func show(in container: NSView, focus: Bool) {
    let terminal = store.terminal(for: folder)
    guard terminal.superview !== container else { return }
    container.subviews.forEach { $0.removeFromSuperview() }
    terminal.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(terminal)
    NSLayoutConstraint.activate([
      terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
      terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      terminal.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
      terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
  }
}
