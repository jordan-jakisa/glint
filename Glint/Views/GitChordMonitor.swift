import AppKit
@preconcurrency import SwiftTerm
import SwiftUI

/// Zed's two-key git shortcuts: ⌃G, then ↑ push, ⇧↑ force push, ↓ pull,
/// ⇧↓ pull with rebase, or ⌃G again to fetch. Skipped while you type in the
/// terminal (⌃G belongs to the shell there) or in a text field.
struct GitChordMonitor: NSViewRepresentable {
  let run: (GitChord) -> Void

  enum GitChord {
    case push, forcePush, pull, pullRebase, fetch
  }

  func makeNSView(context: Context) -> MonitorView {
    let view = MonitorView()
    view.run = run
    return view
  }

  func updateNSView(_ view: MonitorView, context: Context) {
    view.run = run
  }

  final class MonitorView: NSView {
    var run: (GitChord) -> Void = { _ in }
    private var monitor: Any?
    /// When ⌃G was pressed; the second key has a second and a half.
    private var armedAt: Date?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self else { return event }
        let window = event.window
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        let code = event.keyCode
        let handled = MainActor.assumeIsolated { self.handle(window: window, flags: flags, key: key, code: code) }
        return handled ? nil : event
      }
    }

    private func handle(window eventWindow: NSWindow?, flags: NSEvent.ModifierFlags, key: String?, code: UInt16) -> Bool {
      guard let window, eventWindow === window, window.attachedSheet == nil else { return false }
      if window.firstResponder is TerminalView { return false }
      if let text = window.firstResponder as? NSTextView, text.isEditable { return false }
      let isControlG = flags == .control && key == "g"
      if let armed = armedAt, Date().timeIntervalSince(armed) < 1.5 {
        armedAt = nil
        switch (code, flags) {
        case (126, []): run(.push)
        case (126, .shift): run(.forcePush)
        case (125, []): run(.pull)
        case (125, .shift): run(.pullRebase)
        default:
          if isControlG { run(.fetch) } else { return false }
        }
        return true
      }
      if isControlG {
        armedAt = Date()
        return true
      }
      return false
    }
  }
}
