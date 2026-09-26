internal import Clibgit2

/// A libgit2 failure, carrying libgit2's own message.
struct GitError: Error, Sendable, CustomStringConvertible {
  let code: Int32
  /// Adit's own words for what failed.
  let message: String
  /// libgit2's text, for the details and the log.
  var detail: String?

  var description: String { message }

  /// The folder isn't inside a git repository at all.
  var isNotARepository: Bool { code == GIT_ENOTFOUND.rawValue }

  /// Turns a libgit2 return code into a thrown error. Anything below zero is a
  /// failure.
  static func check(_ code: Int32, _ context: @autoclosure () -> String) throws {
    guard code < 0 else { return }
    let libgit2 = lastMessage(or: "")
    throw GitError(code: code, message: context(), detail: libgit2.isEmpty ? nil : libgit2)
  }

  static func lastMessage(or fallback: String) -> String {
    guard let error = git_error_last(), let message = error.pointee.message else {
      return fallback
    }
    let text = String(cString: message)
    return text.isEmpty ? fallback : text
  }
}

/// libgit2 needs one global init before any other call. It is reference
/// counted and safe to call from any thread; Adit never shuts it down.
enum LibGit2 {
  static let initialized: Void = {
    git_libgit2_init()
  }()
}
