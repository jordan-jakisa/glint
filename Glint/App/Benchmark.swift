import AppKit
import QuartzCore

/// Walks the open repository the way a reader would and logs every speed
/// budget, so step timing doesn't need anyone driving the UI. Start the app with
///
///     open Glint.app --args -GlintBenchmark YES
///
/// and read the results with the `log stream` command in `Timing`. Add
/// `-GlintRepository <path>` to benchmark a specific repository.
extension RepositorySession {
  static var isBenchmarking: Bool {
    UserDefaults.standard.bool(forKey: "GlintBenchmark")
  }

  /// `-GlintTestAI YES`: writes a commit message for the open repository's
  /// changes with the AI settings in effect, and logs the result and timing.
  /// For checking a provider end to end without clicking.
  static var isTestingAI: Bool { UserDefaults.standard.bool(forKey: "GlintTestAI") }

  func runAITest() async {
    try? await Task.sleep(for: .seconds(1))
    let settings = AISettings.shared
    Timing.log.info("AI test: provider \(settings.provider.rawValue, privacy: .public), model \(settings.modelID ?? "none", privacy: .public), ready \(settings.isReady)")
    let start = ContinuousClock.now
    generateCommitMessage()
    await messageTask?.value
    Timing.report("AI test, whole message", since: start, budget: 10_000)
    if let alert {
      Timing.log.info("AI test failed: \(alert.message, privacy: .public)")
    } else {
      Timing.log.info("AI test message (\(self.aiNote ?? "", privacy: .public)):\n\(self.commitMessage, privacy: .public)")
    }
  }

  func runBenchmark() async {
    // Let launch work settle so it doesn't bleed into the first sample.
    try? await Task.sleep(for: .seconds(1))
    Timing.log.info("benchmark: start")

    for _ in 0..<3 {
      refreshWorkingTree()
      try? await Task.sleep(for: .milliseconds(300))
    }
    tab = .history
    try? await Task.sleep(for: .milliseconds(300))

    for _ in 0..<15 {
      await measure("next commit, main thread", budget: 50, throughSwiftUI: true) { selectNextItem() }
      try? await Task.sleep(for: .milliseconds(100))
    }
    // Back up through commits that are now cached.
    for _ in 0..<5 {
      await measure("previous commit, main thread", budget: 50, throughSwiftUI: true) { selectPreviousItem() }
      try? await Task.sleep(for: .milliseconds(100))
    }
    // Back to the newest commit, which is the large one in the bench repo.
    selectedCommitID = commits.first?.id
    try? await Task.sleep(for: .milliseconds(600))

    await measure("toggle layout", throughSwiftUI: true) { toggleLayout() }
    await measure("toggle layout back", throughSwiftUI: true) { toggleLayout() }
    for _ in 0..<3 { await measure("next hunk") { nextHunk() } }
    for _ in 0..<3 { await measure("next file") { nextFile() } }
    await measure("previous hunk") { previousHunk() }
    await measure("collapse file", throughSwiftUI: true) { toggleCurrentFileCollapsed() }
    await measure("expand file", throughSwiftUI: true) { toggleCurrentFileCollapsed() }

    Timing.log.info("benchmark: done")
  }

  /// Main-thread work to put the result on screen: the action, then layout
  /// and display forced synchronously, then the Core Animation commit. This
  /// is what has to fit in a frame. Waiting for vsync isn't counted: earlier
  /// versions of this awaited the main queue afterwards, and a profile showed
  /// the main thread idle for nearly all of that time.
  ///
  /// Actions that go through SwiftUI state (layout, collapse) need one
  /// SwiftUI update before there's anything to lay out; `throughSwiftUI`
  /// yields for it, which also brings some frame pacing into the number.
  /// Default budget: one frame.
  private func measure(
    _ what: StaticString, budget: Double = 16, throughSwiftUI: Bool = false, _ action: () -> Void
  ) async {
    let start = ContinuousClock.now
    action()
    if throughSwiftUI { await Task.yield() }
    for window in NSApp.windows where window.isVisible {
      window.layoutIfNeeded()
      window.displayIfNeeded()
    }
    CATransaction.flush()
    Timing.report(what, since: start, budget: budget)
    try? await Task.sleep(for: .milliseconds(200))
  }
}
