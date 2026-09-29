import SwiftUI

extension View {
  /// The stash sheets: the name prompt and the stash list. One line in the
  /// window's root view.
  func stashSheets(_ session: RepositorySession) -> some View {
    sheet(item: Binding(get: { session.stashSheet }, set: { session.stashSheet = $0 })) { sheet in
      Group {
        switch sheet {
        case .name(let kind): StashNamePrompt(session: session, kind: kind)
        case .picker: StashPicker(session: session)
        }
      }
      .font(.app(.body))
      .tint(.themeAccent)
      .themedTextLevels()
    }
  }
}

/// Asks for an optional name before making a stash. Return stashes; an
/// empty name keeps git's own "WIP on <branch>".
struct StashNamePrompt: View {
  let session: RepositorySession
  let kind: StashKind
  @State private var name = ""
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 6) {
        Text(kind.title).font(.app(.headline))
        Text(kind.explanation)
          .font(.app(.caption))
          .foregroundStyle(.secondary)
      }
      .padding(12)
      Hairline()
      TextField("Name it, or leave it empty", text: $name)
        .textFieldStyle(.plain)
        .focused($focused)
        .onSubmit(stash)
        .padding(12)
      Hairline()
      HStack {
        Spacer()
        Button("Cancel") { session.stashSheet = nil }
          .keyboardShortcut(.cancelAction)
        Button("Stash", action: stash)
          .keyboardShortcut(.defaultAction)
      }
      .padding(12)
    }
    .frame(width: 380)
    .onAppear { focused = true }
  }

  private func stash() {
    session.stash(kind, named: name)
  }
}

/// Your stashes, newest first, with the highlighted one's changes beside
/// them. Type to filter, ↑ and ↓ to pick, Return applies, ⌘↩ pops, ⌘⌫
/// drops (after asking).
struct StashPicker: View {
  @Bindable var session: RepositorySession
  @State private var query = ""
  @State private var highlighted = 0
  @State private var pendingDrop: Stash?
  @FocusState private var searchFocused: Bool

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        TextField("Search stashes", text: $query)
          .textFieldStyle(.plain)
          .focused($searchFocused)
          .padding(10)
          .onSubmit { if let current { session.applyStash(current) } }
          .onChange(of: query) { highlighted = 0 }
        Hairline()
        list
        Hairline()
        footer
      }
      .frame(width: 320)
      Hairline(axis: .vertical)
      VStack(spacing: 0) {
        actions
        Hairline()
        StashPreview(session: session, stash: current)
      }
    }
    .frame(width: 900, height: 520)
    .arrowKeys(move: move)
    .onAppear {
      searchFocused = true
      session.loadStashes()
    }
    .onChange(of: session.stashes) {
      highlighted = min(highlighted, max(matches.count - 1, 0))
    }
    .confirmationDialog(
      "Drop \u{201C}\(pendingDrop?.title ?? "")\u{201D}?",
      isPresented: Binding(get: { pendingDrop != nil }, set: { if !$0 { pendingDrop = nil } }),
      titleVisibility: .visible
    ) {
      Button("Drop", role: .destructive) {
        if let pendingDrop { session.dropStash(pendingDrop) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Its changes will be gone. You can't undo this.")
    }
  }

  @ViewBuilder private var list: some View {
    if session.stashes.isEmpty {
      EmptyState(
        "No stashes", systemImage: "tray",
        description: Text("Stash your changes to set them aside, then get them back here."))
    } else {
      ScrollViewReader { proxy in
        List {
          if matches.isEmpty {
            Text("No stash matches \u{201C}\(trimmedQuery)\u{201D}.")
              .foregroundStyle(.secondary)
          }
          ForEach(Array(matches.enumerated()), id: \.element.id) { index, stash in
            Button {
              highlighted = index
            } label: {
              row(stash)
            }
            .buttonStyle(.plain)
            .highlighted(highlighted == index)
            .id(index)
            .contextMenu {
              Button("Apply") { session.applyStash(stash) }
              Button("Pop") { session.popStash(stash) }
              Divider()
              Button("Drop\u{2026}") { pendingDrop = stash }
            }
          }
        }
        .listStyle(.plain)
        .font(.app(.body))
        .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
      }
    }
  }

  private func row(_ stash: Stash) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(stash.title)
        .foregroundStyle(stash.isNamed ? .primary : .secondary)
        .lineLimit(1)
      HStack(spacing: 4) {
        if let branch = stash.branch {
          Image(systemName: "arrow.triangle.branch")
          Text(branch).lineLimit(1).truncationMode(.middle)
          Text("\u{00B7}")
        }
        Text(stash.date, format: .relative(presentation: .named))
          .lineLimit(1)
      }
      .font(.app(.caption))
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .help(stash.reference)
  }

  /// The highlighted stash's name and what you can do with it.
  private var actions: some View {
    HStack(spacing: 8) {
      Text(current?.title ?? "")
        .font(.app(.headline))
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer()
      Button("Drop\u{2026}") { pendingDrop = current }
      Button("Pop") { if let current { session.popStash(current) } }
      Button("Apply") { if let current { session.applyStash(current) } }
    }
    .disabled(current == nil || session.isStashing)
    .padding(.horizontal, 10)
    .frame(height: 40)
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Text("\u{21A9} apply  \u{2318}\u{21A9} pop  \u{2318}\u{232B} drop")
        .font(.app(.caption))
        .foregroundStyle(.secondary)
      Spacer()
      if session.isStashing {
        ProgressView().controlSize(.small)
      }
      Button("Done") { session.isStashPickerShown = false }
        .keyboardShortcut(.cancelAction)
      // Keys for the highlighted stash, while the search field has focus.
      Group {
        Button("") { if let current { session.popStash(current) } }
          .keyboardShortcut(.return, modifiers: .command)
        Button("") { pendingDrop = current }
          .keyboardShortcut(.delete, modifiers: .command)
      }
      .frame(width: 0, height: 0)
      .hidden()
    }
    .padding(.horizontal, 10)
    .frame(height: 32)
  }

  private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

  private var matches: [Stash] {
    guard !trimmedQuery.isEmpty else { return session.stashes }
    return session.stashes.filter {
      $0.message.localizedCaseInsensitiveContains(trimmedQuery)
        || ($0.branch?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
    }
  }

  /// The highlighted stash: what Return, ⌘↩, ⌘⌫ and the preview act on.
  private var current: Stash? {
    matches.indices.contains(highlighted) ? matches[highlighted] : nil
  }

  private func move(_ step: Int) {
    guard !matches.isEmpty else { return }
    highlighted = (highlighted + step + matches.count) % matches.count
  }
}

/// A stash's changes as a read-only unified diff, in the code font.
private struct StashPreview: View {
  let session: RepositorySession
  let stash: Stash?
  @State private var lines: [Substring] = []
  @State private var isTruncated = false
  @State private var error: String?
  @State private var loadedID: String?

  var body: some View {
    Group {
      if stash == nil {
        EmptyState("Nothing selected", systemImage: "tray", description: Text("Pick a stash to see its changes."))
      } else if let error {
        EmptyState("Couldn't show this stash", systemImage: "exclamationmark.triangle", description: Text(error))
      } else if loadedID != stash?.id {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if lines.isEmpty {
        EmptyState("No changes", systemImage: "tray", description: Text("This stash doesn't change any files."))
      } else {
        diff
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task(id: stash?.id) { await load() }
  }

  private var diff: some View {
    ScrollView([.vertical, .horizontal]) {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
          Text(line.isEmpty ? " " : String(line))
            .foregroundStyle(color(for: line))
            .fixedSize()
        }
        if isTruncated {
          Text("This stash is long; showing the start. Apply it to see the rest.")
            .font(.app(.caption))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
      }
      .font(.code(.body))
      .textSelection(.enabled)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func color(for line: Substring) -> Color {
    if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
      return .secondary
    }
    if line.hasPrefix("@@") { return .themeAccent }
    if line.hasPrefix("+") { return .added }
    if line.hasPrefix("-") { return .removed }
    return .primary
  }

  private func load() async {
    guard let stash else { return }
    error = nil
    do {
      let (text, truncated) = try await session.stashDiff(stash)
      guard !Task.isCancelled else { return }
      lines = text.isEmpty ? [] : text.split(separator: "\n", omittingEmptySubsequences: false)
      isTruncated = truncated
      loadedID = stash.id
    } catch {
      guard !Task.isCancelled else { return }
      self.error = UserAlert("Couldn't show this stash", error: error).message
    }
  }
}
