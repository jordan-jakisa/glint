import CoreServices
import Foundation

/// Watches a repository's folder with FSEvents and reports what kind of thing
/// changed: working-tree files, or HEAD and branches. Events arrive in bursts
/// (a save is often several writes), so they're coalesced before reporting.
@MainActor
final class RepositoryWatcher {
  struct Change {
    /// Files, or the index. Status needs rereading.
    var workingTree = false
    /// HEAD or a branch moved. History needs rereading.
    var head = false
    /// When the first event of this burst arrived.
    var firstEventAt = ContinuousClock.now
  }

  /// FSEvents' own coalescing window. Together with `debounce` this is most of
  /// the 200 ms edit-to-list budget.
  private static let latency: CFTimeInterval = 0.05
  private static let debounce: Duration = .milliseconds(30)

  private let root: String
  private let onChange: (Change) -> Void
  // Touched from deinit, which only runs once nothing else holds the watcher.
  nonisolated(unsafe) private var stream: FSEventStreamRef?
  private var pending: Change?
  private var flushTask: Task<Void, Never>?

  init(url: URL, onChange: @escaping (Change) -> Void) {
    root = url.standardizedFileURL.path
    self.onChange = onChange
    start()
  }

  deinit {
    guard let stream else { return }
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
  }

  private func start() {
    var context = FSEventStreamContext(
      version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil, release: nil, copyDescription: nil)
    let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
      guard let info else { return }
      let watcher = Unmanaged<RepositoryWatcher>.fromOpaque(info).takeUnretainedValue()
      let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
      // The stream is scheduled on the main queue.
      MainActor.assumeIsolated { watcher.received(list) }
    }
    let flags = UInt32(
      kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
        | kFSEventStreamCreateFlagNoDefer)
    guard
      let stream = FSEventStreamCreate(
        nil, callback, &context, [root] as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Self.latency, flags)
    else { return }
    self.stream = stream
    FSEventStreamSetDispatchQueue(stream, .main)
    FSEventStreamStart(stream)
  }

  private func received(_ paths: [String]) {
    var change = pending ?? Change()
    for path in paths {
      switch Self.classify(path, root: root) {
      case .workingTree: change.workingTree = true
      case .head:
        change.head = true
        change.workingTree = true
      case .ignored: break
      }
    }
    guard change.workingTree || change.head else { return }
    pending = change
    flushTask?.cancel()
    flushTask = Task {
      try? await Task.sleep(for: Self.debounce)
      guard !Task.isCancelled, let pending else { return }
      self.pending = nil
      onChange(pending)
    }
  }

  nonisolated enum Kind { case workingTree, head, ignored }

  /// Inside `.git`, only the index, HEAD, and refs matter; object writes,
  /// logs, and lock files are noise.
  nonisolated static func classify(_ path: String, root: String) -> Kind {
    guard let range = path.range(of: "/.git/") ?? (path.hasSuffix("/.git") ? path.range(of: "/.git") : nil)
    else { return .workingTree }
    let inside = path[range.upperBound...]
    if inside == "index" { return .workingTree }
    if inside == "HEAD" || inside.hasPrefix("refs/") || inside == "packed-refs" { return .head }
    return .ignored
  }
}
