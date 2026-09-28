import Foundation
import Testing

@testable import Glint

@Suite struct PermalinkTests {
  private let sha = "0123456789abcdef0123456789abcdef01234567"

  @Test(arguments: [
    "https://github.com/owner/repo.git",
    "https://github.com/owner/repo",
    "https://user@github.com/owner/repo.git/",
    "git@github.com:owner/repo.git",
    "ssh://git@github.com/owner/repo.git",
    "ssh://git@github.com:22/owner/repo",
    "git://github.com/owner/repo.git",
  ])
  func readsEveryRemoteForm(_ remote: String) {
    #expect(Permalink.repository(fromRemote: remote) == .init(host: .github, base: "https://github.com/owner/repo"))
  }

  @Test func linksALineOnEachHost() {
    func link(_ remote: String, line: Int? = 12) -> String? {
      Permalink.url(forRemote: remote, sha: sha, path: "Sources/App/main file.swift", line: line)?.absoluteString
    }
    let path = "Sources/App/main%20file.swift"
    #expect(link("git@github.com:owner/repo.git") == "https://github.com/owner/repo/blob/\(sha)/\(path)#L12")
    #expect(
      link("https://gitlab.com/group/sub/repo.git") == "https://gitlab.com/group/sub/repo/-/blob/\(sha)/\(path)#L12")
    #expect(
      link("git@bitbucket.org:team/repo.git") == "https://bitbucket.org/team/repo/src/\(sha)/\(path)#lines-12")
    #expect(
      link("https://codeberg.org/owner/repo.git") == "https://codeberg.org/owner/repo/src/commit/\(sha)/\(path)#L12")
    #expect(
      link("git@gitea.example.com:owner/repo.git")
        == "https://gitea.example.com/owner/repo/src/commit/\(sha)/\(path)#L12")
    #expect(link("git@git.sr.ht:~user/repo") == "https://git.sr.ht/~user/repo/tree/\(sha)/item/\(path)#L12")
    #expect(link("https://github.com/owner/repo", line: nil) == "https://github.com/owner/repo/blob/\(sha)/\(path)")
  }

  @Test func keepsTheWebPortAndDropsTheSSHOne() {
    #expect(
      Permalink.repository(fromRemote: "https://gitlab.example.com:8443/team/app.git")?.base
        == "https://gitlab.example.com:8443/team/app")
    #expect(
      Permalink.repository(fromRemote: "ssh://git@gitlab.example.com:2222/team/app.git")?.base
        == "https://gitlab.example.com/team/app")
  }

  @Test func hasNoLinkForUnknownHostsOrLocalPaths() {
    #expect(Permalink.repository(fromRemote: "git@example.com:owner/repo.git") == nil)
    #expect(Permalink.repository(fromRemote: "/Users/me/repos/app.git") == nil)
    #expect(Permalink.repository(fromRemote: "file:///Users/me/repos/app.git") == nil)
    #expect(Permalink.repository(fromRemote: "") == nil)
  }
}
