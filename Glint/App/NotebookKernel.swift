import Foundation

/// Runs a notebook's cells in a real Jupyter kernel, through the bundled
/// `glint_kernel.py` driver (jupyter_client), so outputs, rich display,
/// errors and interrupts are Jupyter's own.
///
/// The Python it uses, first found: Settings' choice, the project's
/// `.venv` or `venv`, Glint's own environment, then `python3` on your
/// shell's PATH. It needs jupyter_client and ipykernel; without them,
/// `setUp` makes Glint's own environment (with uv if you have it).
@MainActor @Observable
final class NotebookKernel {
  enum State: Equatable {
    case stopped
    case starting
    case ready
    case busy
    /// No Python with Jupyter: Set Up offers to make one.
    case needsSetup
    case settingUp
    case failed(String)
  }

  private(set) var state: State = .stopped
  /// The Python in use, for the toolbar.
  private(set) var python: URL?

  /// A Python to use before any other (tests; otherwise Settings' choice).
  @ObservationIgnored var pythonOverride: URL?
  @ObservationIgnored private var process: Process?
  @ObservationIgnored private var input: FileHandle?
  @ObservationIgnored private var reading: Task<Void, Never>?
  @ObservationIgnored private var handlers: [String: (Event) -> Void] = [:]
  @ObservationIgnored private var queue: [(id: String, code: String)] = []
  @ObservationIgnored private var running: String?

  enum Event {
    case output(JSONValue)
    case clear
    case done(executionCount: Int?, ok: Bool)
  }

  /// Glint's own environment for notebooks.
  nonisolated static var ownEnvironment: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Glint/Jupyter", isDirectory: true)
  }

  // MARK: Starting

  func start(project: URL, kernelName: String?) {
    guard state == .stopped || state == .needsSetup || isFailed else { return }
    state = .starting
    Task {
      guard let python = await Self.findPython(project: project, override: pythonOverride) else {
        state = .needsSetup
        return
      }
      launch(python: python, project: project, kernelName: kernelName)
    }
  }

  private var isFailed: Bool { if case .failed = state { return true } else { return false } }

  private func launch(python: URL, project: URL, kernelName: String?) {
    guard let driver = Bundle.main.url(forResource: "glint_kernel", withExtension: "py") else {
      state = .failed("Glint's kernel driver is missing from the app.")
      return
    }
    self.python = python
    let process = Process()
    process.executableURL = python
    process.arguments = ["-u", driver.path, kernelName ?? "python3", project.path]
    process.currentDirectoryURL = project
    let stdin = Pipe()
    let stdout = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { [weak self] process in
      let status = process.terminationStatus
      Task { @MainActor in self?.ended(status: status) }
    }
    do {
      try process.run()
    } catch {
      state = .failed("Couldn't start \(python.path): \(error.localizedDescription)")
      return
    }
    self.process = process
    input = stdin.fileHandleForWriting
    reading = Task { [weak self] in
      do {
        for try await line in stdout.fileHandleForReading.bytes.lines {
          guard let data = line.data(using: .utf8), let message = try? JSONValue.parse(data) else { continue }
          await MainActor.run { self?.receive(message) }
        }
      } catch {}
    }
  }

  private func ended(status: Int32) {
    process = nil
    input = nil
    if let running { handlers[running]?(.done(executionCount: nil, ok: false)) }
    running = nil
    handlers = [:]
    queue = []
    if case .failed = state { return }
    state = status == 0 ? .stopped : .failed("The kernel stopped (exit \(status)).")
  }

  private func receive(_ message: JSONValue) {
    switch message["type"]?.string {
    case "ready", "restarted":
      state = .ready
      runNext()
    case "fatal":
      let text = message["message"]?.string ?? "The kernel couldn't start."
      if text.contains("jupyter_client") { state = .needsSetup } else { state = .failed(text) }
    case "output":
      if let id = message["id"]?.string, let output = message["output"] { handlers[id]?(.output(output)) }
    case "clear":
      if let id = message["id"]?.string { handlers[id]?(.clear) }
    case "done":
      guard let id = message["id"]?.string else { return }
      handlers[id]?(.done(executionCount: message["execution_count"]?.int, ok: message["status"]?.string == "ok"))
      handlers[id] = nil
      running = nil
      state = .ready
      runNext()
    default:
      break
    }
  }

  // MARK: Running

  /// Queues a cell; cells run one at a time, in the order asked.
  func run(id: String, code: String, events: @escaping (Event) -> Void) {
    handlers[id] = events
    queue.append((id, code))
    if state == .ready { runNext() }
  }

  private func runNext() {
    guard running == nil, state == .ready || state == .busy, !queue.isEmpty else { return }
    let next = queue.removeFirst()
    running = next.id
    state = .busy
    send(.object(["id": .string(next.id), "code": .string(next.code)]))
  }

  func isQueued(_ id: String) -> Bool { running == id || queue.contains { $0.id == id } }

  func interrupt() {
    // Cells still waiting are dropped; the running one gets KeyboardInterrupt.
    for job in queue { handlers[job.id]?(.done(executionCount: nil, ok: false)) }
    queue = []
    send(.object(["cmd": .string("interrupt")]))
  }

  func restart() {
    interrupt()
    state = .starting
    send(.object(["cmd": .string("restart")]))
  }

  func shutdown() {
    send(.object(["cmd": .string("shutdown")]))
    let process = self.process
    Task {
      try? await Task.sleep(for: .seconds(2))
      if process?.isRunning == true { process?.terminate() }
    }
    reading?.cancel()
    self.process = nil
    input = nil
    state = .stopped
  }

  private func send(_ message: JSONValue) {
    guard let input else { return }
    let line = JSONValue.write(message, indent: 0).replacingOccurrences(of: "\n", with: "") + "\n"
    try? input.write(contentsOf: Data(line.utf8))
  }

  // MARK: Finding and setting up Python

  /// Pythons to try, best first.
  nonisolated static func candidates(project: URL, override: URL? = nil) async -> [URL] {
    var urls: [URL] = []
    if let override { urls.append(override) }
    if let chosen = UserDefaults.standard.string(forKey: "notebookPython"), !chosen.isEmpty {
      urls.append(URL(fileURLWithPath: (chosen as NSString).expandingTildeInPath))
    }
    for folder in [".venv", "venv", "env"] {
      urls.append(project.appendingPathComponent("\(folder)/bin/python"))
    }
    urls.append(ownEnvironment.appendingPathComponent("bin/python"))
    let path = await LoginEnvironment.shared.value.variables["PATH"] ?? ""
    for directory in path.split(separator: ":") {
      urls.append(URL(fileURLWithPath: String(directory)).appendingPathComponent("python3"))
    }
    return urls.filter { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  /// The first candidate that has jupyter_client and ipykernel.
  nonisolated static func findPython(project: URL, override: URL? = nil) async -> URL? {
    for python in await candidates(project: project, override: override) where await hasJupyter(python) {
      return python
    }
    return nil
  }

  nonisolated static func hasJupyter(_ python: URL) async -> Bool {
    await run(python, ["-c", "import jupyter_client, ipykernel"]) == 0
  }

  /// Makes Glint's own environment with jupyter_client and ipykernel: uv if
  /// it's on your PATH (fast, and it can fetch a Python), else `python3 -m
  /// venv` and pip. Returns its Python.
  func setUp(environment: URL = NotebookKernel.ownEnvironment, usingUV: Bool = true) async throws -> URL {
    state = .settingUp
    defer { if state == .settingUp { state = .stopped } }
    let path = await LoginEnvironment.shared.value.variables["PATH"] ?? ""
    let directories = path.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
    let find = { (name: String) in
      directories.map { $0.appendingPathComponent(name) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    let python = environment.appendingPathComponent("bin/python")
    let packages = ["jupyter_client", "ipykernel"]
    if usingUV, let uv = find("uv") ?? (FileManager.default.isExecutableFile(atPath: NSHomeDirectory() + "/.local/bin/uv") ? URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin/uv") : nil) {
      guard await Self.run(uv, ["venv", "--allow-existing", environment.path]) == 0,
        await Self.run(uv, ["pip", "install", "--python", python.path] + packages) == 0
      else { throw SetUpError.failed("uv couldn't make the environment.") }
    } else if let system = find("python3") {
      guard await Self.run(system, ["-m", "venv", environment.path]) == 0,
        await Self.run(python, ["-m", "pip", "install", "--quiet"] + packages) == 0
      else { throw SetUpError.failed("pip couldn't install Jupyter.") }
    } else {
      throw SetUpError.failed("There's no Python on your PATH. Install one (brew install python), then try again.")
    }
    state = .stopped
    return python
  }

  enum SetUpError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let text) = self { text } else { nil } }
  }

  /// Runs a program to the end and returns its exit status.
  nonisolated static func run(_ executable: URL, _ arguments: [String]) async -> Int32 {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    var environment = await LoginEnvironment.shared.value.variables
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    process.environment = environment
    return await withCheckedContinuation { continuation in
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do { try process.run() } catch { continuation.resume(returning: -1) }
    }
  }
}
