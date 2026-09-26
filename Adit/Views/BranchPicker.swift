import SwiftUI

/// Type to filter; Return switches to the top match, or creates a branch when
/// nothing matches.
struct BranchPicker: View {
  @Bindable var session: RepositorySession
  @State private var query = ""
  @FocusState private var searchFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      TextField("Switch to or create a branch", text: $query)
        .textFieldStyle(.plain)
        .focused($searchFocused)
        .padding(10)
        .onSubmit(submit)
      Divider()
      List {
        if canCreate {
          Button {
            session.createBranch(named: query)
          } label: {
            Label("Create branch \u{201C}\(trimmedQuery)\u{201D}", systemImage: "plus")
          }
          .buttonStyle(.plain)
        }
        if matches.isEmpty, !canCreate, !trimmedQuery.isEmpty {
          Text(
            trimmedQuery.contains(" ")
              ? "Branch names can't have spaces."
              : "No branch matches \u{201C}\(trimmedQuery)\u{201D}.")
            .foregroundStyle(.secondary)
        }
        ForEach(matches) { branch in
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
        }
      }
      .listStyle(.plain)
      if session.isSwitchingBranch {
        Divider()
        ProgressView().controlSize(.small).padding(6)
      }
    }
    .frame(width: 340, height: 360)
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

  private func submit() {
    if let first = matches.first {
      session.switchBranch(to: first)
    } else if canCreate {
      session.createBranch(named: trimmedQuery)
    }
  }
}
