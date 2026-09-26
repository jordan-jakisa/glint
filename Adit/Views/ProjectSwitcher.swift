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
        Text(session.projectURL?.lastPathComponent ?? "Adit")
          .font(.headline)
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.caption2.weight(.semibold))
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
  @State private var keys: Any?
  @FocusState private var searchFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      TextField("Switch to a recent project", text: $query)
        .textFieldStyle(.plain)
        .focused($searchFocused)
        .padding(10)
        .onSubmit(openHighlighted)
        .onChange(of: query) { highlighted = matches.isEmpty ? 0 : min(1, matches.count - 1) }
      Divider()
      if matches.isEmpty {
        Text(projects.isEmpty ? "Projects you open show up here." : "No recent project matches \u{201C}\(query)\u{201D}.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollViewReader { proxy in
          List {
            ForEach(Array(matches.enumerated()), id: \.element) { index, url in
              row(url, highlighted: index == highlighted)
                .id(index)
                .onTapGesture { session.openProject(url) }
            }
          }
          .listStyle(.plain)
          .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
        }
      }
      Divider()
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
    .frame(width: 380, height: 340)
    .onAppear {
      projects = session.recentProjects()
      // The open project is first; Return goes to the one before it.
      highlighted = projects.count > 1 ? 1 : 0
      searchFocused = true
      keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        switch event.keyCode {
        case 125: move(1)
        case 126: move(-1)
        default: return event
        }
        return nil
      }
    }
    .onDisappear {
      if let keys { NSEvent.removeMonitor(keys) }
      keys = nil
    }
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
    let isOpen = session.projectURL.map { $0.standardizedFileURL.path == url.standardizedFileURL.path } ?? false
    return HStack(spacing: 8) {
      Image(systemName: isOpen ? "checkmark" : "folder")
        .foregroundStyle(isOpen ? Color.accentColor : .secondary)
        .frame(width: 16)
      VStack(alignment: .leading, spacing: 2) {
        Text(url.lastPathComponent)
          .lineLimit(1)
        Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.head)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 2)
    .padding(.horizontal, 4)
    .contentShape(Rectangle())
    .listRowBackground(
      highlighted ? RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.2)).padding(.horizontal, 6) : nil
    )
    .help(url.path)
  }
}
