import SwiftUI

/// Type to filter, ↑ and ↓ to pick, Return to switch; creates a branch when
/// nothing matches.
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
      Divider()
      List {
        if canCreate {
          Button {
            session.createBranch(named: query)
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
          Button {
            session.switchBranch(to: branch)
          } label: {
            HStack {
              Image(systemName: branch.isCurrent ? "checkmark" : (branch.isRemote ? "cloud" : "arrow.triangle.branch"))
                .foregroundStyle(branch.isCurrent ? Color.accentColor : .secondary)
                .frame(width: 16)
              Text(branch.name)
                .lineLimit(1)
              Spacer()
              Text(branch.date, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .highlighted(highlighted == index + (canCreate ? 1 : 0))
        }
      }
      .listStyle(.plain)
      if session.isSwitchingBranch {
        Divider()
        ProgressView().controlSize(.small).padding(6)
      }
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
      session.createBranch(named: trimmedQuery)
    } else {
      let index = highlighted - (canCreate ? 1 : 0)
      if matches.indices.contains(index) { session.switchBranch(to: matches[index]) }
    }
  }
}
