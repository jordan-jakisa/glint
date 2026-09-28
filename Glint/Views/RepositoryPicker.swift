import SwiftUI

/// The workspace's repositories, each with its branch and how many changes
/// it has, so you can see which ones need attention.
struct RepositoryPicker: View {
  @Bindable var session: RepositorySession

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(session.workspace?.name ?? "")
        .font(.app(.headline))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
      Toggle("Show every repository's changes", isOn: $session.showsAllRepositories)
        .toggleStyle(.checkbox)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
      Hairline()
      ForEach(Array((session.workspace?.repositories ?? []).enumerated()), id: \.element.id) { index, repository in
        Button {
          session.isRepositoryPickerShown = false
          session.switchRepository(to: repository)
        } label: {
          row(repository, index: index)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.bottom, 6)
    .frame(width: 320)
  }

  private func row(_ repository: WorkspaceRepository, index: Int) -> some View {
    let summary = session.repositorySummaries[repository.relativePath]
    let isActive = repository.id == session.activeWorkspaceRepository?.id
    return HStack(spacing: 8) {
      Image(systemName: isActive ? "checkmark" : "folder")
        .foregroundStyle(isActive ? Color.themeAccent : .secondary)
        .frame(width: 16)
      VStack(alignment: .leading, spacing: 2) {
        Text(repository.relativePath)
          .lineLimit(1)
        Text(summary?.branch ?? "detached HEAD")
          .font(.app(.caption))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      if let count = summary?.changeCount, count > 0 {
        Text("\(count)")
          .font(.app(.caption).monospacedDigit())
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.modified.opacity(0.2), in: Capsule())
      }
      if index < 9 {
        Text("\u{2318}\(index + 1)")
          .font(.app(.caption))
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .contentShape(Rectangle())
  }
}
