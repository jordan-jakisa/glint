import Foundation

/// Runs the user's own `git` for the operations that must behave exactly like
/// the terminal: commit, branch switching, fetch, pull, push. Hooks, signing,
/// credential helpers, SSH keys and agent, and config all apply. Reads stay on
/// libgit2, where there is no process to spawn.
struct SystemGit: Sendable {
  let directory: URL

  struct Failure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
  }

  /// Runs `git <arguments>` in the repository and returns its standard
  /// output. A non-zero exit throws with git's own error text, which is
  /// usually the most useful thing to show (a failing hook's output, a
  /// rejected push).
  @concurrent
  func run(_ arguments: [String], input: String? = nil) async throws -> String {
    let environment = await LoginEnvironment.shared.value
    let process = Process()
    process.executableURL = environment.git
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = environment.variables

    let output = Pipe()
    let errors = Pipe()
    let stdin = Pipe()
    process.standardOutput = output
    process.standardError = errors
    process.standardInput = stdin

    try process.run()
    if let input { stdin.fileHandleForWriting.write(Data(input.utf8)) }
    try? stdin.fileHandleForWriting.close()

    // Drain both pipes at once: a process that fills one while we wait on the
    // other would never exit.
    async let out = Self.readAll(output)
    async let err = Self.readAll(errors)
    let (stdout, stderr) = await (out, err)
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let text = [stderr, stdout].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
      throw Failure(message: text ?? "git \(arguments.first ?? "") failed (exit \(process.terminationStatus)).")
    }
    return stdout
  }

  @concurrent
  private static func readAll(_ pipe: Pipe) async -> String {
    let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
    return String(decoding: data, as: UTF8.self)
  }
}

/// The environment a terminal would give git. Apps launched from the Dock get
/// a bare PATH, so hooks that call `npx`, `bundle`, or anything from Homebrew
/// would fail. Asks the login shell once, in the background, at first use.
struct LoginEnvironment: Sendable {
  let variables: [String: String]
  let git: URL

  static let shared = Task { await resolve() }

  @concurrent
  private static func resolve() async -> LoginEnvironment {
    var variables = ProcessInfo.processInfo.environment
    if let path = await loginShellPath() {
      variables["PATH"] = path
    } else {
      let fallback = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
      variables["PATH"] = fallback.joined(separator: ":")
    }
    // Never block on a password prompt nobody can see.
    variables["GIT_TERMINAL_PROMPT"] = "0"
    variables["GIT_EDITOR"] = "true"

    let directories = (variables["PATH"] ?? "").split(separator: ":").map(String.init)
    let git =
      directories.map { URL(fileURLWithPath: $0).appendingPathComponent("git") }
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
      ?? URL(fileURLWithPath: "/usr/bin/git")
    return LoginEnvironment(variables: variables, git: git)
  }

  /// PATH as an interactive login shell sets it, so both `.zprofile` and
  /// `.zshrc` (where nvm and friends live) are applied. Markers fence the
  /// value off from anything the shell's startup files print.
  private static func loginShellPath() async -> String? {
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = ["-ilc", "printf '__ADIT_PATH__%s__ADIT_PATH__' \"$PATH\""]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }

    // A shell config that hangs shouldn't hang Adit.
    let timeout = Task {
      try await Task.sleep(for: .seconds(3))
      if process.isRunning { process.terminate() }
    }
    let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
    process.waitUntilExit()
    timeout.cancel()

    let text = String(decoding: data, as: UTF8.self)
    let parts = text.components(separatedBy: "__ADIT_PATH__")
    guard parts.count >= 3, !parts[1].isEmpty else { return nil }
    return parts[1]
  }
}
