import AppKit
import MetricKit
import OSLog

/// What Glint records to find and fix problems, all on this Mac: errors you
/// were shown, crash and hang reports from macOS (MetricKit), and the
/// timings in `Timing`. Nothing is sent anywhere. Help > Export Diagnostics
/// gathers it into one file you can choose to share.
enum Diagnostics {
  static let subsystem = "com.kerustudios.glint"
  /// Every alert shown, and failures that never reach one.
  static let errors = Logger(subsystem: subsystem, category: "errors")

  /// Where MetricKit's reports are kept.
  static var reportsFolder: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("Glint/Diagnostics", isDirectory: true)
  }

  /// The version you're running: "0.2.0 (412)".
  static var version: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(short) (\(build))"
  }

  @MainActor private static let receiver = MetricReceiver()

  /// Starts listening for crash and hang reports. macOS delivers them on a
  /// later launch, at most once a day.
  @MainActor static func start() {
    MXMetricManager.shared.add(receiver)
    errors.notice("launch \(version, privacy: .public) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public)")
  }

  /// Help > Export Diagnostics: the version, the last three days of Glint's
  /// log, and any crash or hang reports, in one text file.
  @MainActor static func export() {
    let panel = NSSavePanel()
    let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
    panel.nameFieldStringValue = "Glint Diagnostics \(stamp).txt"
    panel.message = "Your repositories' paths and file names stay out of it; errors and timings are in."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try report().write(to: url, atomically: true, encoding: .utf8)
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } catch {
      errors.error("export diagnostics failed: \(error.localizedDescription, privacy: .public)")
      NSSound.beep()
    }
  }

  static func report(since: Date = Date().addingTimeInterval(-3 * 86_400)) -> String {
    var lines = [
      "Glint \(version)",
      "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
      "Exported \(Date().formatted(.iso8601))",
      "",
      "## Log",
    ]
    if let store = try? OSLogStore(scope: .currentProcessIdentifier),
      let entries = try? store.getEntries(
        at: store.position(date: since), matching: NSPredicate(format: "subsystem == %@", subsystem))
    {
      for case let entry as OSLogEntryLog in entries {
        lines.append("\(entry.date.formatted(.iso8601)) [\(entry.category)] \(level(entry.level)) \(entry.composedMessage)")
      }
    } else {
      lines.append("(macOS didn't hand over this launch's log)")
    }
    lines.append("")
    lines.append("## Crash and hang reports")
    let reports = (try? FileManager.default.contentsOfDirectory(at: reportsFolder, includingPropertiesForKeys: nil)) ?? []
    if reports.isEmpty { lines.append("(none)") }
    for report in reports.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
      lines.append("### \(report.lastPathComponent)")
      lines.append((try? String(contentsOf: report, encoding: .utf8)) ?? "(unreadable)")
    }
    return lines.joined(separator: "\n")
  }

  private static func level(_ level: OSLogEntryLog.Level) -> String {
    switch level {
    case .fault: "FAULT"
    case .error: "ERROR"
    case .notice: "notice"
    case .info: "info"
    case .debug: "debug"
    default: ""
    }
  }

  /// Keeps each report MetricKit delivers as JSON, at most 20.
  static func save(_ payloads: [(name: String, json: Data)]) {
    let folder = reportsFolder
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for payload in payloads {
      try? payload.json.write(to: folder.appendingPathComponent(payload.name))
      errors.fault("macOS reported a problem in an earlier session: \(payload.name, privacy: .public)")
    }
    let all = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
    for old in all.dropFirst(20) { try? FileManager.default.removeItem(at: old) }
  }
}

private final class MetricReceiver: NSObject, MXMetricManagerSubscriber {
  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    let stamp = ISO8601DateFormatter()
    Diagnostics.save(
      payloads.enumerated().map { index, payload in
        (name: "diagnostic-\(stamp.string(from: payload.timeStampEnd))-\(index).json", json: payload.jsonRepresentation())
      })
  }
}
