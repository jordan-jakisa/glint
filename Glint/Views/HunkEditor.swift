import SwiftUI

/// Edits lines of your working copy in place, with syntax colours and line
/// numbers, kept in step with the file on disk while it's open. ⌘S or ⌘↩
/// saves; Escape cancels.
struct HunkEditor: View {
  @Bindable var edit: LiveEdit
  let save: (LiveEdit) -> Void
  let cancel: () -> Void

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
