import AppKit
import SwiftUI

/// Help > Version History: what changed in each version, newest first, from
/// the CHANGELOG.md that ships in the app. The one you're running is marked.
enum VersionHistory {
  struct Version: Identifiable, Equatable {
    let number: String
    let changes: [String]
    var id: String { number }
  }

  /// Parses `# 0.2.0` headings and `- ` items.
  static func parse(_ markdown: String) -> [Version] {
    var versions: [Version] = []
    var number: String?
    var changes: [String] = []
    func flush() {
      if let number { versions.append(Version(number: number, changes: changes)) }
    }
    for line in markdown.components(separatedBy: .newlines) {
      if line.hasPrefix("# ") {
        flush()
        number = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        changes = []
      } else if line.hasPrefix("- ") {
        changes.append(String(line.dropFirst(2)))
      }
    }
    flush()
    return versions
  }

  static var bundled: [Version] {
    guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }
    return parse(text)
  }

  @MainActor private static var window: NSWindow?

  @MainActor static func show() {
    if let window {
      window.makeKeyAndOrderFront(nil)
      return
    }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "Version History"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: VersionHistoryView(versions: bundled))
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate()
    self.window = window
  }
}

private struct VersionHistoryView: View {
  let versions: [VersionHistory.Version]
  private let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("You're running Glint \(Diagnostics.version).")
          .foregroundStyle(.secondary)
        ForEach(versions) { version in
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
              Text(version.number).font(.app(.title3)).fontWeight(.semibold)
              if version.number == current {
                Text("Installed")
                  .font(.app(.caption))
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2)
                  .background(Capsule().fill(Color.themeAccent.opacity(0.18)))
              }
            }
            ForEach(version.changes, id: \.self) { change in
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\u{2022}").foregroundStyle(.secondary)
                Text((try? AttributedString(markdown: change)) ?? AttributedString(change))
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
        }
      }
      .font(.app(.body))
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minWidth: 420, minHeight: 360)
  }
}
