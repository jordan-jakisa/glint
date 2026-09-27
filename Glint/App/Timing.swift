import Foundation
import os

/// Measures the speed budgets in docs/plans/v0.1-diff-viewer.md. Durations go to
/// the unified log (subsystem com.kerustudios.glint, category timing) and as
/// signposts for Instruments. Watch them with:
///
///     log stream --level info --predicate 'subsystem == "com.kerustudios.glint"'
enum Timing {
  static let log = Logger(subsystem: "com.kerustudios.glint", category: "timing")
  /// Every write Glint makes to a repository, so an unexpected change can be
  /// traced back to the action that made it.
  static let writes = Logger(subsystem: "com.kerustudios.glint", category: "writes")
  static let signposter = OSSignposter(logger: log)

  /// Milliseconds elapsed since `start`, a `ContinuousClock` instant.
  static func milliseconds(since start: ContinuousClock.Instant) -> Double {
    let elapsed = ContinuousClock.now - start
    return Double(elapsed.components.seconds) * 1_000
      + Double(elapsed.components.attoseconds) / 1e15
  }

  static func report(_ what: StaticString, since start: ContinuousClock.Instant, budget: Double) {
    let ms = milliseconds(since: start)
    let verdict = ms <= budget ? "ok" : "OVER BUDGET"
    log.info("\(what, privacy: .public): \(ms, format: .fixed(precision: 1)) ms (budget \(budget, format: .fixed(precision: 0)) ms, \(verdict, privacy: .public))")
  }

  /// Milliseconds since the process started, from the kernel's record of the
  /// launch. Covers everything before `main`, which a clock started in the app
  /// would miss.
  static func millisecondsSinceLaunch() -> Double? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
    let start = info.kp_proc.p_un.__p_starttime
    let started = Double(start.tv_sec) + Double(start.tv_usec) / 1e6
    return (Date().timeIntervalSince1970 - started) * 1_000
  }

  /// Logged once, the first time the commit list has rows on screen.
  @MainActor private static var reportedLaunch = false

  @MainActor static func reportLaunchIfNeeded() {
    guard !reportedLaunch, let ms = millisecondsSinceLaunch() else { return }
    reportedLaunch = true
    let verdict = ms <= 300 ? "ok" : "OVER BUDGET"
    log.info("launch to first list: \(ms, format: .fixed(precision: 1)) ms (budget 300 ms, \(verdict, privacy: .public))")
  }
}
