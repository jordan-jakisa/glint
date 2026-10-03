import SwiftUI

/// Edits lines of your working copy in place, with syntax colours and line
/// numbers, kept in step with the file on disk while it's open. ⌘S or ⌘↩
/// saves; Escape cancels.
struct HunkEditor: View {
  @Bindable var edit: LiveEdit
  let save: (LiveEdit) -> Void
  let cancel: () -> Void
  var failed: (Error) -> Void = { _ in }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(edit.fileName).font(.app(.headline))
        Text(
          edit.isWholeFile
            ? "\(edit.lastLineNumber) lines" : "lines \(edit.firstLineNumber)\u{2013}\(edit.lastLineNumber)"
        )
        .foregroundStyle(.secondary)
        Spacer()
        if let language = edit.language {
          Text(language.name)
            .font(.app(.caption))
            .foregroundStyle(.secondary)
        }
      }
      .padding(12)
      Hairline()
      EditConflictBar(edit: edit, failed: failed)
      CodeEditor(text: $edit.text, language: edit.language, firstLine: edit.firstLineNumber)
        .frame(
          minWidth: 720, idealWidth: edit.isWholeFile ? 960 : 720,
          minHeight: 360, idealHeight: edit.isWholeFile ? 640 : 360)
      Hairline()
      HStack {
        Text(edit.note ?? "Stays in step with the file on disk.")
          .font(.app(.caption))
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer()
        Button("Cancel", action: cancel)
          .keyboardShortcut(.cancelAction)
        Button("Save") { save(edit) }
          .keyboardShortcut("s")
        // ⌘↩ too, since Return belongs to the text.
        Button("") { save(edit) }
          .keyboardShortcut(.return, modifiers: .command)
          .hidden()
      }
      .padding(12)
    }
  }
}

/// Shown when the file changed on disk in lines you'd also changed:
/// nothing saves on its own until you pick a side.
struct EditConflictBar: View {
  @Bindable var edit: LiveEdit
  let failed: (Error) -> Void

  var body: some View {
    if edit.hasConflict {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(Color(nsColor: Theme.shared.conflicted))
        Text("\(edit.fileName) changed on disk in lines you also changed. Autosave is paused.")
          .lineLimit(2)
        Spacer()
        Button("Use Theirs") { edit.useTheirs() }
          .help("Drop your changes to those lines and take the file as it is on disk")
        Button("Keep Mine") {
          do { try edit.keepMine() } catch { failed(error) }
        }
        .help("Save your version over the one on disk")
      }
      .font(.app(.callout))
      .controlSize(.small)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Color(nsColor: Theme.shared.conflicted).opacity(0.12))
    }
  }
}
