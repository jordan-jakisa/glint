internal import Clibgit2

/// A libgit2 failure, carrying libgit2's own message.
struct GitError: Error, Sendable, CustomStringConvertible {
  let code: Int32
  let message: String

  var description: String { message }

  /// Turns a libgit2 return code into a thrown error. Anything below zero is a
  /// failure.
  static func check(_ code: Int32, _ context: @autoclosure () -> String) throws {
    guard code < 0 else { return }
    throw GitError(code: code, message: lastMessage(or: context()))
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
