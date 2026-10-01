import Foundation

/// A notebook open in the Files tab: cells you can edit and run, saved on
/// their own a second after a change, and kept in step with the file on
/// disk the way `LiveEdit` is (another editor or an agent saving it reloads
/// it; if you'd changed it too, it asks).
@MainActor @Observable
final class NotebookDocument: Identifiable {
  let id = UUID()
  let url: URL
  private(set) var notebook: Notebook
  /// Cells running or waiting to.
  private(set) var running: Set<String> = []
  /// Set when the file changed on disk while you had unsaved changes.
  private(set) var hasConflict = false
  private(set) var note: String?
  let kernel = NotebookKernel()

  @ObservationIgnored private var saved: Data
  @ObservationIgnored private var diskStamp: Date?
  @ObservationIgnored private var watch: Task<Void, Never>?
  @ObservationIgnored private var autosave: Task<Void, Never>?
  @ObservationIgnored var autosaveDelay: Duration? = .seconds(1)

  init(url: URL) throws {
    self.url = url
    let data = try Data(contentsOf: url)
    notebook = try Notebook(data: data)
    saved = data
    diskStamp = Self.stamp(url)
  }

  var fileName: String { url.lastPathComponent }
  /// Set by an edit or a run, cleared by saving or reloading. Not a byte
  /// comparison: a notebook another tool wrote in its own JSON layout would
  /// look changed on open, and closing it would rewrite the whole file.
  private(set) var hasUnsavedChanges = false

  // MARK: Editing

  func setSource(_ source: String, of cellID: String) {
    guard let index = index(of: cellID), notebook.cells[index].source != source else { return }
    notebook.cells[index].source = source
    changed()
  }

  func insertCell(_ kind: Notebook.CellKind, after cellID: String?) -> String {
    let id = UUID().uuidString.lowercased().prefix(8).description
    var raw = JSONValue.object(["metadata": .object([:])])
    // Cell ids came in nbformat 4.5; older notebooks would fail validation.
    if (notebook.raw["nbformat_minor"]?.int ?? 5) >= 5 { raw["id"] = .string(id) }
    let cell = Notebook.Cell(id: id, kind: kind, source: "", outputs: [], executionCount: nil, raw: raw)
    let position = cellID.flatMap(index(of:)).map { $0 + 1 } ?? notebook.cells.count
    notebook.cells.insert(cell, at: position)
    changed()
    return id
  }

  func deleteCell(_ cellID: String) {
    guard let index = index(of: cellID) else { return }
    notebook.cells.remove(at: index)
    changed()
  }

  func moveCell(_ cellID: String, by offset: Int) {
    guard let index = index(of: cellID) else { return }
    let target = index + offset
    guard notebook.cells.indices.contains(target) else { return }
    notebook.cells.swapAt(index, target)
    changed()
  }

  func setKind(_ kind: Notebook.CellKind, of cellID: String) {
    guard let index = index(of: cellID), notebook.cells[index].kind != kind else { return }
    notebook.cells[index].kind = kind
    if kind != .code {
      notebook.cells[index].outputs = []
      notebook.cells[index].executionCount = nil
    }
    changed()
  }

  func clearOutputs() {
    for index in notebook.cells.indices where notebook.cells[index].kind == .code {
      notebook.cells[index].outputs = []
      notebook.cells[index].executionCount = nil
    }
    changed()
  }

  private func index(of cellID: String) -> Int? { notebook.cells.firstIndex { $0.id == cellID } }

  // MARK: Running

  /// Runs a code cell in the kernel, starting it first if it's stopped.
  func run(_ cellID: String, project: URL) {
    guard let index = index(of: cellID), notebook.cells[index].kind == .code else { return }
    if kernel.state == .stopped || isKernelFailed { kernel.start(project: project, kernelName: notebook.kernelName) }
    notebook.cells[index].outputs = []
    running.insert(cellID)
    let code = notebook.cells[index].source
    kernel.run(id: cellID, code: code) { [weak self] event in
      self?.apply(event, to: cellID)
    }
  }

  func runAll(project: URL) {
    for cell in notebook.cells where cell.kind == .code { run(cell.id, project: project) }
  }

  private var isKernelFailed: Bool { if case .failed = kernel.state { return true } else { return false } }

  private func apply(_ event: NotebookKernel.Event, to cellID: String) {
    guard let index = index(of: cellID) else { return }
    switch event {
    case .output(let raw):
      let kind = Notebook.Output.Kind(rawValue: raw["output_type"]?.string ?? "") ?? .displayData
      // Consecutive stream text of the same name joins, as Jupyter does.
      if kind == .stream, var last = notebook.cells[index].outputs.last, last.kind == .stream,
        last.raw["name"] == raw["name"]
      {
        last.raw["text"] = .string((Notebook.joined(last.raw["text"]) ?? "") + (raw["text"]?.string ?? ""))
        notebook.cells[index].outputs[notebook.cells[index].outputs.count - 1] = last
      } else {
        notebook.cells[index].outputs.append(Notebook.Output(kind: kind, raw: raw))
      }
    case .clear:
      notebook.cells[index].outputs = []
    case .done(let count, _):
      if let count { notebook.cells[index].executionCount = count }
      running.remove(cellID)
      changed()
    }
  }

  /// Glint's environment for notebooks, made on request.
  func setUpKernel(project: URL) async throws {
    _ = try await kernel.setUp()
    kernel.start(project: project, kernelName: notebook.kernelName)
  }

  // MARK: Saving and the file on disk

  private func changed() {
    note = nil
    hasUnsavedChanges = true
    guard let autosaveDelay, !hasConflict else { return }
    autosave?.cancel()
    autosave = Task { [weak self] in
      try? await Task.sleep(for: autosaveDelay)
      guard !Task.isCancelled else { return }
      try? self?.save()
    }
  }

  func save() throws {
    guard hasUnsavedChanges else { return }
    let data = notebook.data()
    try data.write(to: url, options: .atomic)
    saved = data
    diskStamp = Self.stamp(url)
    hasConflict = false
    hasUnsavedChanges = false
  }

  func startWatching() {
    guard watch == nil else { return }
    watch = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(400))
        self?.syncFromDisk()
      }
    }
  }

  func stopWatching() {
    watch?.cancel()
    watch = nil
    autosave?.cancel()
    kernel.shutdown()
  }

  /// Reloads a notebook changed on disk; with your own unsaved changes, asks.
  func syncFromDisk() {
    let stamp = Self.stamp(url)
    guard stamp != diskStamp else { return }
    diskStamp = stamp
    guard let data = try? Data(contentsOf: url), data != saved, let fresh = try? Notebook(data: data) else { return }
    if hasUnsavedChanges {
      hasConflict = true
      note = "\(fileName) changed on disk while you were editing it."
    } else {
      notebook = fresh
      saved = data
      note = "Reloaded: \(fileName) changed on disk."
    }
  }

  func keepMine() throws {
    hasConflict = false
    let data = notebook.data()
    try data.write(to: url, options: .atomic)
    saved = data
    diskStamp = Self.stamp(url)
    note = nil
    hasUnsavedChanges = false
  }

  func useTheirs() {
    guard let data = try? Data(contentsOf: url), let fresh = try? Notebook(data: data) else { return }
    notebook = fresh
    saved = data
    hasConflict = false
    note = nil
    hasUnsavedChanges = false
  }

  private static func stamp(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
  }
}
