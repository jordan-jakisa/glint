import Foundation

/// Some lines of a file in your working copy, open for editing and kept in
/// step with the file on disk. Anything that writes the file while you
/// type, an agent or another editor, is merged into what you have: its
/// changes appear in place, yours stay, and where you both changed the same
/// lines yours win and the footer says so. Saving merges once more first.
@MainActor @Observable
final class LiveEdit: Identifiable {
  let id = UUID()
  let url: URL
  let fileName: String
  let language: SyntaxLanguage?
  /// The whole file, opened from the list or Open File, not a hunk.
  let isWholeFile: Bool
  /// What's in the editor.
  var text: String {
    didSet { if !isApplyingDisk, text != oldValue { scheduleAutosave() } }
  }
  /// Saves on its own once you pause typing, like Zed's `after_delay`. The
  /// Files tab's editor does; the hunk editor keeps Save and Cancel.
  @ObservationIgnored var autosaveDelay: Duration?
  /// The first line shown, 0-based, in the file as it is on disk.
  private(set) var startLine: Int
  /// Said once something changed on disk, until you save.
  private(set) var note: String?
  /// Set when the file changed on disk in lines you'd also changed. Until
  /// you pick Keep Mine or Use Theirs nothing is saved on its own, so
  /// neither version is lost without you deciding.
  private(set) var hasConflict = false

  /// The file as last read, and the region's length in it.
  @ObservationIgnored private var disk: [String]
  @ObservationIgnored private var regionCount: Int
  @ObservationIgnored private var diskText: String?
  @ObservationIgnored private var diskStamp: FileStamp?
  @ObservationIgnored private var lineEnding = "\n"
  @ObservationIgnored private var endsWithNewline = true
  @ObservationIgnored private var watch: Task<Void, Never>?
  @ObservationIgnored private var autosave: Task<Void, Never>?
  @ObservationIgnored private var isApplyingDisk = false

  /// Opens lines `start..<start + count` (0-based) of `content`, the file
  /// at `url` as just read.
  init(url: URL, content: String, start: Int, count: Int, wholeFile: Bool = false) {
    self.url = url
    isWholeFile = wholeFile
    fileName = url.lastPathComponent
    language = SyntaxLanguage.forPath(url.path)
    let file = Self.split(content)
    disk = file.lines
    lineEnding = file.lineEnding
    endsWithNewline = file.endsWithNewline
    diskText = content
    diskStamp = FileStamp(url)
    let first = min(max(0, start), file.lines.count)
    let length = min(max(0, count), file.lines.count - first)
    startLine = first
    regionCount = length
    text = file.lines[first..<(first + length)].joined(separator: "\n")
  }

  /// Whether the editor differs from the file on disk.
  var hasUnsavedChanges: Bool {
    _ = text
    return edited != disk
  }

  var firstLineNumber: Int { startLine + 1 }
  var lastLineNumber: Int { startLine + max(editedLines.count, 1) }

  /// Looks at the file a few times a second while the editor is open: one
  /// `stat`, and a read only when it changed.
  func startWatching() {
    guard watch == nil else { return }
    watch = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(250))
        self?.syncFromDisk()
      }
    }
  }

  private func scheduleAutosave() {
    // Settings, General, Autosave: read each time, so switching it takes
    // effect on the file already open.
    guard let autosaveDelay, UserDefaults.standard.object(forKey: "autosave") as? Bool ?? true else { return }
    autosave?.cancel()
    autosave = Task { [weak self] in
      try? await Task.sleep(for: autosaveDelay)
      guard !Task.isCancelled, let self, self.hasUnsavedChanges, !self.hasConflict else { return }
      do {
        try self.save()
      } catch {
        self.note = "Couldn't save: \(error.localizedDescription)"
      }
    }
  }

  func stopWatching() {
    autosave?.cancel()
    watch?.cancel()
    watch = nil
  }

  /// Folds in whatever changed on disk since the last look.
  func syncFromDisk() {
    let stamp = FileStamp(url)
    guard stamp != diskStamp else { return }
    diskStamp = stamp
    let current = try? String(contentsOf: url, encoding: .utf8)
    guard current != diskText else { return }
    diskText = current
    guard let current else {
      note = "\(fileName) was deleted on disk. Saving puts it back."
      return
    }
    let theirs = Self.split(current)
    let ours = edited
    let merged = LineMerge.merge(base: disk, ours: ours, theirs: theirs.lines)
    let regionEnd = startLine + editedLines.count
    let start = merged.lower[startLine]
    let end = max(start, merged.upper[regionEnd])
    let suffix = merged.lines.count - end
    let region = merged.lines[start..<end].joined(separator: "\n")

    disk = theirs.lines
    lineEnding = theirs.lineEnding
    endsWithNewline = theirs.endsWithNewline
    startLine = start
    regionCount = max(0, theirs.lines.count - suffix - start)
    if merged.conflicted {
      hasConflict = true
      note = "\(fileName) changed on disk in lines you also changed."
    } else if region != text {
      note = "Picked up changes made on disk."
    }
    if region != text {
      // Their change, not yours: nothing to autosave.
      isApplyingDisk = true
      text = region
      isApplyingDisk = false
    }
  }

  /// Resolves a conflict with your version: saved as it is, over theirs.
  func keepMine() throws {
    hasConflict = false
    try save()
  }

  /// Resolves a conflict with the file as it is on disk: your changes to
  /// those lines are dropped.
  func useTheirs() {
    let theirs = disk[startLine..<(startLine + regionCount)].joined(separator: "\n")
    isApplyingDisk = true
    text = theirs
    isApplyingDisk = false
    hasConflict = false
    note = nil
  }

  /// Writes the file: what's on disk now, with your lines in place. Saving
  /// by hand (⌘S) during a conflict keeps yours.
  func save() throws {
    syncFromDisk()
    let lines = edited
    let output = lines.joined(separator: lineEnding) + (endsWithNewline ? lineEnding : "")
    try output.write(to: url, atomically: true, encoding: .utf8)
    disk = lines
    regionCount = editedLines.count
    diskText = output
    diskStamp = FileStamp(url)
    note = nil
    hasConflict = false
  }

  /// The editor's lines. A newline typed at the very end ends the last
  /// line rather than starting a new one.
  private var editedLines: [String] {
    var lines = text.components(separatedBy: "\n").map(Self.withoutCR)
    if lines.count > 1, lines.last == "" { lines.removeLast() }
    return lines
  }

  /// The whole file as you have it.
  private var edited: [String] {
    Array(disk[..<startLine]) + editedLines + Array(disk[(startLine + regionCount)...])
  }

  nonisolated static func split(_ content: String) -> (lines: [String], lineEnding: String, endsWithNewline: Bool) {
    let lineEnding = content.contains("\r\n") ? "\r\n" : "\n"
    var lines = content.components(separatedBy: "\n").map(withoutCR)
    let endsWithNewline = content.hasSuffix("\n")
    if endsWithNewline || lines == [""] { lines.removeLast() }
    return (lines, lineEnding, endsWithNewline || content.isEmpty)
  }

  nonisolated static func withoutCR(_ line: String) -> String {
    line.hasSuffix("\r") ? String(line.dropLast()) : line
  }
}

/// A file's modification date and size: enough to skip reading it when
/// nothing changed.
private struct FileStamp: Equatable {
  let date: Date?
  let size: Int?

  init?(_ url: URL) {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
    date = attributes[.modificationDate] as? Date
    size = (attributes[.size] as? NSNumber)?.intValue
  }
}

/// Editing in the diff: a hunk's current lines open in an editor and save
/// straight back to the file, which the watcher then shows as a new diff.
extension RepositorySession {
  /// Whether the diff on screen is your working copy, the only one edits
  /// can go to.
  var canEditDiff: Bool {
    if case .workingTree(false, _) = diff?.source { return true }
    return false
  }

  func beginEdit(_ row: DiffRowID) {
    guard canEditDiff, let repository, let files = diff?.files, files.indices.contains(row.file) else { return }
    let file = files[row.file]
    guard let path = file.newPath, !file.isBinary, file.hunks.indices.contains(row.hunk) else { return }
    let hunk = file.hunks[row.hunk]
    // The file as it is now: context and added lines, not the removed ones.
    let count = hunk.lines.filter { $0.kind == .context || $0.kind == .addition }.count
    guard count > 0 else { return }
    let url = repository.url.appendingPathComponent(path)
    do {
      let content = try String(contentsOf: url, encoding: .utf8)
      let edit = LiveEdit(url: url, content: content, start: hunk.newStart - 1, count: count)
      edit.startWatching()
      editingHunk = edit
    } catch {
      alert = UserAlert("Couldn't open \((path as NSString).lastPathComponent)", error: error)
    }
  }

  func saveEdit(_ edit: LiveEdit) {
    do {
      try edit.save()
      Timing.writes.notice("edit in diff")
      endEdit()
      refresh()
    } catch {
      alert = UserAlert("Couldn't save your edit", error: error)
    }
  }

  func endEdit() {
    editingHunk?.stopWatching()
    editingHunk = nil
  }
}
