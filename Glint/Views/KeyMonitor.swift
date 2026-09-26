import AppKit
@preconcurrency import SwiftTerm
import SwiftUI

/// Single-key commands (j, k, n, p, o, Space, s, c) for one window. They can't
/// be menu shortcuts: a plain-letter menu shortcut can fire while you're typing
/// a commit message. This monitor skips every key while a text field has focus.
struct KeyMonitor: NSViewRepresentable {
  let handle: (Character) -> Bool

  func makeNSView(context: Context) -> MonitorView {
    let view = MonitorView()
    view.handle = handle
    return view
  }

  func updateNSView(_ view: MonitorView, context: Context) {
    view.handle = handle
  }

  final class MonitorView: NSView {
    var handle: (Character) -> Bool = { _ in false }
    private var monitor: Any?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, let key = event.charactersIgnoringModifiers?.first else { return event }
        let window = event.window
        let modifiers = event.modifierFlags
        // Local monitors run on the main thread.
        let handled = MainActor.assumeIsolated {
          self.shouldHandle(window: window, modifiers: modifiers) && self.handle(key)
        }
        return handled ? nil : event
      }
    }

    private func shouldHandle(window eventWindow: NSWindow?, modifiers: NSEvent.ModifierFlags) -> Bool {
      guard let window, eventWindow === window else { return false }
      guard modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
      // Typing in the commit message, a search field, or a sheet: hands off.
      if let text = window.firstResponder as? NSTextView, text.isEditable { return false }
      // Typing in the terminal panel belongs to the shell.
      if window.firstResponder is TerminalView { return false }
      return window.attachedSheet == nil
    }

    // Removed by the owning window going away; a view outliving its window
    // clears the monitor in viewDidMoveToWindow.
  }
}
