import AppKit
import SwiftUI

/// The window title: the open project's name, which opens your recent
/// projects.
struct ProjectTitle: View {
  @Bindable var session: RepositorySession

  var body: some View {
    Button {
      session.isProjectSwitcherShown.toggle()
    } label: {
      HStack(spacing: 4) {
        Text(session.projectURL?.lastPathComponent ?? "Glint")
          .font(.app(.headline))
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.app(.caption2).weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .foregroundStyle(.primary)
    .help(AppCommand.switchProject.hint("Switch project"))
    .popover(isPresented: $session.isProjectSwitcherShown, arrowEdge: .bottom) {
      ProjectSwitcher(session: session)
    }
  }
}

/// Recent projects, newest first. Type to filter, ↑ and ↓ to move, Return to
/// open.
struct ProjectSwitcher: View {
  @Bindable var session: RepositorySession
  @State private var projects: [URL] = []
  @State private var query = ""
  @State private var highlighted = 0
  @State private var listHeight: CGFloat = 0
  @FocusState private var searchFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      TextField("Switch to a recent project", text: $query)
        .textFieldStyle(.plain)
        .focused($searchFocused)
        .padding(10)
        .onSubmit(openHighlighted)
        .onChange(of: query) { highlighted = 0 }
      Hairline()
      if matches.isEmpty {
        Text(emptyMessage)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .padding(24)
      } else {
        // Sized to its rows, so a few recent projects don't leave a tall
        // empty popover. Scrolls past the cap.
        ScrollViewReader { proxy in
          ScrollView {
            VStack(spacing: 0) {
              ForEach(Array(matches.enumerated()), id: \.element) { index, url in
                row(url, highlighted: index == highlighted)
                  .id(index)
                  .onTapGesture { session.openProject(url) }
              }
            }
            .padding(6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
          }
          .frame(height: min(listHeight, 300))
          .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
        }
      }
      Hairline()
      Button {
        session.isProjectSwitcherShown = false
        session.chooseRepository()
      } label: {
        HStack {
          Text("Open Repository…")
          Spacer()
          Text(AppCommand.openRepository.keys).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.primary)
      .padding(10)
    }
    .frame(width: 380)
    .onAppear {
      // The open project is already the window title, so it isn't offered
      // here. The first row is the one you had open before, so Return flips
      // back to it.
      let open = session.projectURL?.standardizedFileURL.path
      projects = session.recentProjects().filter { $0.standardizedFileURL.path != open }
      highlighted = 0
      searchFocused = true
    }
    .arrowKeys(move: move)
  }

  private var emptyMessage: String {
    if !projects.isEmpty { return "No recent project matches \u{201C}\(query)\u{201D}." }
    if session.projectURL != nil {
      return "This is the only project you've opened. Open another and you can switch between them here."
    }
    return "Projects you open show up here."
  }

  private var matches: [URL] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return projects }
    return projects.filter { $0.path.localizedCaseInsensitiveContains(trimmed) }
  }

  private func move(_ step: Int) {
    guard !matches.isEmpty else { return }
    highlighted = (highlighted + step + matches.count) % matches.count
  }

  private func openHighlighted() {
    guard matches.indices.contains(highlighted) else { return }
    session.openProject(matches[highlighted])
  }

  private func row(_ url: URL, highlighted: Bool) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "folder")
        .foregroundStyle(.secondary)
        .frame(width: 16)
      VStack(alignment: .leading, spacing: 2) {
        Text(url.lastPathComponent)
          .lineLimit(1)
        Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
          .font(.app(.caption))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.head)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 5)
    .padding(.horizontal, 8)
    .background(
      RoundedRectangle(cornerRadius: 5).fill(highlighted ? Color.themeAccent.opacity(0.2) : .clear))
    .contentShape(Rectangle())
    .help(url.path)
  }
}
