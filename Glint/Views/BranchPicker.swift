import SwiftUI

/// Type to filter, ↑ and ↓ to pick, Return to switch; creates a branch when
/// nothing matches. A branch checked out in another worktree opens that
/// worktree; ⌥↩ or Option-click opens any branch in a new worktree.
struct BranchPicker: View {
  @Bindable var session: RepositorySession
  @State private var query = ""
  /// The row Return picks: the create row when shown, then the matches.
  @State private var highlighted = 0
  @FocusState private var searchFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      TextField("Switch to or create a branch", text: $query)
        .textFieldStyle(.plain)
        .focused($searchFocused)
        .padding(10)
        .onSubmit(submit)
        .onChange(of: query) { highlighted = 0 }
      Hairline()
      List {
        if canCreate {
          Button {
            if optionHeld {
              session.createWorktree(branch: trimmedQuery, isNew: true)
            } else {
              session.createBranch(named: query)
            }
          } label: {
            Label("Create branch \u{201C}\(trimmedQuery)\u{201D}", systemImage: "plus")
          }
          .buttonStyle(.plain)
          .highlighted(highlighted == 0)
        }
        if matches.isEmpty, !canCreate, !trimmedQuery.isEmpty {
          Text(
            trimmedQuery.contains(" ")
              ? "Branch names can't have spaces."
              : "No branch matches \u{201C}\(trimmedQuery)\u{201D}.")
            .foregroundStyle(.secondary)
        }
        ForEach(Array(matches.enumerated()), id: \.element.id) { index, branch in
          let worktree = session.worktree(for: branch)
          Button {
            pick(branch)
          } label: {
            HStack {
              Image(systemName: icon(for: branch, worktree: worktree))
                .foregroundStyle(branch.isCurrent ? Color.themeAccent : .secondary)
                .frame(width: 16)
              Text(branch.name)
                .lineLimit(1)
              Spacer()
              // Where it's checked out, in place of its age: that's the
              // folder picking it opens.
              if let worktree {
                Text(worktree.name)
                  .font(.app(.caption))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                  .truncationMode(.head)
              } else {
                Text(branch.date, format: .relative(presentation: .named))
                  .font(.app(.caption))
                  .foregroundStyle(.secondary)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .highlighted(highlighted == index + (canCreate ? 1 : 0))
          .help(worktree.map { "Checked out in \($0.url.path). Opens that worktree." } ?? "")
          .contextMenu {
            if let worktree {
              Button("Open Worktree") { session.openWorktree(worktree) }
              Button("Remove Worktree") { session.removeWorktree(worktree) }
            } else if !branch.isCurrent {
              Button("Open in New Worktree") { session.createWorktree(branch: branch.switchName, isNew: false) }
            }
          }
        }
      }
      .listStyle(.plain)
      // Lists set their own font; the app's goes on the rows.
      .font(.app(.body))
      Hairline()
      HStack {
        Text("\u{2325}\u{21A9} opens it in a new worktree")
          .font(.app(.caption))
          .foregroundStyle(.secondary)
        Spacer()
        if session.isSwitchingBranch {
          ProgressView().controlSize(.small)
        }
      }
      .padding(.horizontal, 10)
      .frame(height: 28)
    }
    .frame(width: 340, height: 360)
    .arrowKeys(move: move)
    .onAppear { searchFocused = true }
  }

  private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

  private var matches: [Branch] {
    guard !trimmedQuery.isEmpty else { return session.branches }
    return session.branches.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
  }

  private var canCreate: Bool {
    !trimmedQuery.isEmpty && !trimmedQuery.contains(" ")
      && !session.branches.contains { $0.name == trimmedQuery || $0.switchName == trimmedQuery }
  }

  private var rowCount: Int { matches.count + (canCreate ? 1 : 0) }

  private func move(_ step: Int) {
    guard rowCount > 0 else { return }
    highlighted = (highlighted + step + rowCount) % rowCount
  }

  private func submit() {
    if canCreate, highlighted == 0 {
      if optionHeld {
        session.createWorktree(branch: trimmedQuery, isNew: true)
      } else {
        session.createBranch(named: trimmedQuery)
      }
    } else {
      let index = highlighted - (canCreate ? 1 : 0)
      if matches.indices.contains(index) { pick(matches[index]) }
    }
  }

  private var optionHeld: Bool { NSEvent.modifierFlags.contains(.option) }

  /// Opens the branch's worktree if it has one, makes one with Option, and
  /// otherwise switches to it here.
  private func pick(_ branch: Branch) {
    if let worktree = session.worktree(for: branch) {
      session.openWorktree(worktree)
    } else if optionHeld, !branch.isCurrent {
      session.createWorktree(branch: branch.switchName, isNew: false)
    } else {
      session.switchBranch(to: branch)
    }
  }

  private func icon(for branch: Branch, worktree: Worktree?) -> String {
    if branch.isCurrent { return "checkmark" }
    if worktree != nil { return "folder" }
    return branch.isRemote ? "cloud" : "arrow.triangle.branch"
  }
}
