import Foundation

/// Links to a file, or a line in it, on the site a remote lives on.
enum Permalink {
  enum Host: String, Sendable, CaseIterable {
    case github, gitlab, bitbucket, gitea, sourcehut

    /// Recognized from the remote's host name, so self-hosted GitLab and
    /// Gitea instances with the name in their domain work too.
    static func recognizing(_ hostName: String) -> Host? {
      let name = hostName.lowercased()
      if name.contains("github") { return .github }
      if name.contains("gitlab") { return .gitlab }
      if name.contains("bitbucket") { return .bitbucket }
      if name.contains("codeberg") || name.contains("gitea") || name.contains("forgejo") { return .gitea }
      if name.hasSuffix("sr.ht") { return .sourcehut }
      return nil
    }
  }

  /// A remote's web home: the host kind and `https://host/owner/repo`.
  struct Repository: Equatable, Sendable {
    let host: Host
    let base: String
  }

  /// Reads a remote URL in any form git accepts: `https://host/owner/repo.git`,
  /// `ssh://git@host:22/owner/repo.git`, `git@host:owner/repo.git`, or
  /// `git://host/owner/repo`. Nil for a local path or an unknown host.
  static func repository(fromRemote remote: String) -> Repository? {
    let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
    var hostName: String
    var path: String
    if let schemeEnd = trimmed.range(of: "://") {
      // https, http, ssh, git: the user is dropped, and the port unless the
      // remote is already the web server.
      let isWeb = trimmed.lowercased().hasPrefix("http")
      var rest = trimmed[schemeEnd.upperBound...]
      guard let slash = rest.firstIndex(of: "/") else { return nil }
      var authority = rest[..<slash]
      rest = rest[rest.index(after: slash)...]
      if let at = authority.lastIndex(of: "@") { authority = authority[authority.index(after: at)...] }
      if !isWeb, let colon = authority.firstIndex(of: ":") { authority = authority[..<colon] }
      hostName = String(authority)
      path = String(rest)
    } else if let colon = trimmed.firstIndex(of: ":"), !trimmed.hasPrefix("/") {
      // scp-like: [user@]host:owner/repo.git
      var authority = trimmed[..<colon]
      if let at = authority.lastIndex(of: "@") { authority = authority[authority.index(after: at)...] }
      hostName = String(authority)
      path = String(trimmed[trimmed.index(after: colon)...])
    } else {
      return nil
    }
    while path.hasPrefix("/") { path.removeFirst() }
    while path.hasSuffix("/") { path.removeLast() }
    if path.hasSuffix(".git") { path.removeLast(4) }
    let bareHost = hostName.split(separator: ":").first.map(String.init) ?? hostName
    guard !bareHost.isEmpty, !path.isEmpty, let host = Host.recognizing(bareHost) else { return nil }
    return Repository(host: host, base: "https://\(hostName)/\(path)")
  }

  /// The page for `path` at commit `sha`, scrolled to `line` when given.
  static func url(for repository: Repository, sha: String, path: String, line: Int? = nil) -> URL? {
    let encoded = path.addingPercentEncoding(withAllowedCharacters: pathAllowed) ?? path
    let page: String
    var anchor = line.map { "#L\($0)" } ?? ""
    switch repository.host {
    case .github: page = "/blob/\(sha)/\(encoded)"
    case .gitlab: page = "/-/blob/\(sha)/\(encoded)"
    case .bitbucket:
      page = "/src/\(sha)/\(encoded)"
      anchor = line.map { "#lines-\($0)" } ?? ""
    case .gitea: page = "/src/commit/\(sha)/\(encoded)"
    case .sourcehut: page = "/tree/\(sha)/item/\(encoded)"
    }
    return URL(string: repository.base + page + anchor)
  }

  static func url(forRemote remote: String, sha: String, path: String, line: Int? = nil) -> URL? {
    repository(fromRemote: remote).flatMap { url(for: $0, sha: sha, path: path, line: line) }
  }

  private static let pathAllowed: CharacterSet = {
    var set = CharacterSet.urlPathAllowed
    set.remove(charactersIn: "#?;")
    return set
  }()
}
