import Foundation

/// The branch picker: listing, switching, and creating branches. Switching
/// and creating run system git, which refuses to overwrite local changes and
/// runs post-checkout hooks.
extension RepositorySession {
  func loadBranches() {
    guard let repository else { return }
    Task {
      do {
        branches = try await repository.branches()
      } catch {
        alert = UserAlert("Couldn't list the branches", error: error)
      }
    }
  }

  func switchBranch(to branch: Branch) {
    guard !branch.isCurrent else {
      isBranchPickerShown = false
      return
    }
    runSwitch(["switch", branch.switchName], describing: "switch to \(branch.switchName)")
  }

  func createBranch(named name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    runSwitch(["switch", "-c", trimmed], describing: "create branch \(trimmed)")
  }

  private func runSwitch(_ arguments: [String], describing action: String) {
    guard let repository, !isSwitchingBranch else { return }
    Timing.writes.notice("\(action, privacy: .public)")
    let git = SystemGit(directory: repository.url)
    isSwitchingBranch = true
    Task {
      defer { isSwitchingBranch = false }
      do {
        _ = try await git.run(arguments)
        isBranchPickerShown = false
      } catch {
        alert = UserAlert("Couldn't \(action)", error: error)
      }
      refresh()
    }
  }
}
