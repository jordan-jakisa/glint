import SwiftUI

/// Edits a hunk of your working copy in place: the lines as they are now, in
/// the code font. ⌘S or ⌘↩ saves to the file; Escape cancels.
struct HunkEditor: View {
  @State var edit: HunkEdit
  let save: (HunkEdit) -> Void
  let cancel: () -> Void
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(edit.fileName).font(.app(.headline))
        Text("lines \(edit.startLine)\u{2013}\(edit.endLine)")
          .foregroundStyle(.secondary)
        Spacer()
      }
      .padding(12)
      Hairline()
      TextEditor(text: $edit.text)
        .font(.code(.body))
        .scrollContentBackground(.hidden)
        .focused($focused)
        .padding(8)
        .frame(minWidth: 640, minHeight: 320)
      Hairline()
      HStack {
        Text("Saves to the file on disk.")
          .font(.app(.caption))
          .foregroundStyle(.secondary)
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
    .onAppear { focused = true }
  }
}
