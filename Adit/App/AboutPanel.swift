import AppKit

/// The standard About panel, with the tagline and the open-source libraries
/// Adit is built on, and their licences.
enum AboutPanel {
  @MainActor static func show() {
    let body = NSMutableAttributedString(
      string: "A way in to every change.\n\n",
      attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor])
    let credits = """
      Built on libgit2 (GPLv2 with the linking exception) and SwiftTerm (MIT).
      An adit is the horizontal tunnel miners cut to reach and inspect a seam.
      """
    body.append(
      NSAttributedString(
        string: credits,
        attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
    NSApp.orderFrontStandardAboutPanel(options: [.credits: body])
    NSApp.activate()
  }
}
