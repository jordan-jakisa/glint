import Foundation

/// The branch picker: listing, switching, and creating branches. Switching
/// and creating run system git, which refuses to overwrite local changes and
/// runs post-checkout hooks.
extension RepositorySession {
  func loadBranches() {
    guard let repository else { return }
    loadWorktrees()
    loadRemotes()
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

  /// Zed's delete branch, from the picker. `-d` refuses a branch that isn't
  /// merged, so no work is lost; the alert says how to force it.
  func deleteBranch(_ branch: Branch) {
    guard let repository, !branch.isCurrent, !branch.isRemote else { return }
    Timing.writes.notice("delete branch")
    let git = SystemGit(directory: repository.url)
    Task {
      do {
        _ = try await git.run(["branch", "-d", branch.name])
      } catch {
        alert = UserAlert("Couldn't delete \(branch.name)", error: error)
      }
      loadBranches()
    }
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
