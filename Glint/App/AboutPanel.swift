import AppKit

/// The standard About panel, with the tagline and the open-source libraries
/// Glint is built on, and their licences.
enum AboutPanel {
  @MainActor static func show() {
    let body = NSMutableAttributedString(
      string: "Every change, at a glance.\n\n",
      attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor])
    let credits = """
      Built on libgit2 (GPLv2 with the linking exception) and SwiftTerm (MIT). Their licences are under Help > Acknowledgements. Glint is MIT licensed.
      A glint is a quick flash of light: the one look you need to see what changed.
      """
    body.append(
      NSAttributedString(
        string: credits,
        attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
    NSApp.orderFrontStandardAboutPanel(options: [.credits: body])
    NSApp.activate()
  }

  /// The licences of the open-source software Glint ships with, in your text
  /// editor.
  @MainActor static func showAcknowledgements() {
    guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") else { return }
    NSWorkspace.shared.open(url)
  }
}
