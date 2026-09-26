import Foundation
import Testing

@testable import Glint

@MainActor
@Suite struct UserAlertTests {
  @Test func rejectedPushSaysToPullFirst() {
    let stderr = """
      To github.com:me/app.git
       ! [rejected]        main -> main (fetch first)
      error: failed to push some refs to 'github.com:me/app.git'
      hint: Updates were rejected because the remote contains work that you do not
      """
    let alert = UserAlert("Couldn't push", error: SystemGit.Failure(message: stderr))
    #expect(alert.message == "The remote has commits you don't have. Pull, then push again.")
    #expect(alert.details == stderr)
  }

  @Test func failedLoginPointsToTheTerminal() {
    let text = "fatal: could not read Username for 'https://github.com': terminal prompts disabled"
    #expect(UserAlert.advice(forGit: text).hasPrefix("Git couldn't sign in to the remote."))
  }

  @Test func unknownFailuresShowGitsFirstRealLine() {
    let text = "hint: something\nerror: pathspec 'x' did not match any file(s) known to git\n"
    #expect(UserAlert.advice(forGit: text) == "Git said: Pathspec 'x' did not match any file(s) known to git")
  }

  @Test func offlineIsSaidPlainly() {
    let alert = UserAlert("Couldn't write the message", error: URLError(.notConnectedToInternet))
    #expect(alert.message == "You look offline. Connect and try again.")
    #expect(alert.details != nil)
  }

  @Test func libgit2TextGoesInTheDetails() {
    let error = GitError(code: -1, message: "Couldn't stage Cart.swift.", detail: "failed to stat 'Cart.swift'")
    let alert = UserAlert("Couldn't update what's staged", error: error)
    #expect(alert.message == "Couldn't stage Cart.swift.")
    #expect(alert.details?.contains("failed to stat") == true)
  }
}
