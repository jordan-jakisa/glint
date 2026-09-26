import Foundation

/// Walks the open repository the way a reader would and logs every speed
/// budget, so step timing doesn't need anyone driving the UI. Start the app with
///
///     open Adit.app --args -AditBenchmark YES
///
/// and read the results with the `log stream` command in `Timing`. Add
/// `-AditRepository <path>` to benchmark a specific repository.
extension RepositorySession {
  static var isBenchmarking: Bool {
    UserDefaults.standard.bool(forKey: "AditBenchmark")
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
      await measure("next commit, main thread", budget: 50) { selectNextItem() }
      try? await Task.sleep(for: .milliseconds(100))
    }
    // Back up through commits that are now cached.
    for _ in 0..<5 {
      await measure("previous commit, main thread", budget: 50) { selectPreviousItem() }
      try? await Task.sleep(for: .milliseconds(100))
    }
    // Back to the newest commit, which is the large one in the bench repo.
    selectedCommitID = commits.first?.id
    try? await Task.sleep(for: .milliseconds(600))

    await measure("toggle layout") { toggleLayout() }
    await measure("toggle layout back") { toggleLayout() }
    for _ in 0..<3 { await measure("next hunk") { nextHunk() } }
    for _ in 0..<3 { await measure("next file") { nextFile() } }
    await measure("previous hunk") { previousHunk() }
    await measure("collapse file") { toggleCurrentFileCollapsed() }
    await measure("expand file") { toggleCurrentFileCollapsed() }

    Timing.log.info("benchmark: done")
  }

  /// Time from the action until the main thread is free again, which is when
  /// the result has been laid out. Default budget: one frame.
  private func measure(_ what: StaticString, budget: Double = 16, _ action: () -> Void) async {
    let start = ContinuousClock.now
    action()
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { DispatchQueue.main.async { continuation.resume() } }
    }
    Timing.report(what, since: start, budget: budget)
    try? await Task.sleep(for: .milliseconds(200))
  }
}
