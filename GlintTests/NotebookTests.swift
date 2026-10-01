import Foundation
import Testing

@testable import Glint

/// A notebook as Jupyter writes it: sorted keys, one-space indent, sources
/// as lists of lines, a float that must stay `1.0`, non-ASCII text, and an
/// image output.
private let sample = """
  {
   "cells": [
    {
     "cell_type": "markdown",
     "id": "intro",
     "metadata": {},
     "source": [
      "# Résumé\\n",
      "Some *text* \\"quoted\\"."
     ]
    },
    {
     "cell_type": "code",
     "execution_count": 3,
     "id": "calc",
     "metadata": {
      "scrolled": true
     },
     "outputs": [
      {
       "name": "stdout",
       "output_type": "stream",
       "text": [
        "2\\n"
       ]
      },
      {
       "data": {
        "image/png": "iVBORw0KGgo=",
        "text/plain": [
         "<Figure>"
        ]
       },
       "metadata": {},
       "output_type": "display_data"
      }
     ],
     "source": [
      "x = 1.0\\n",
      "print(1 + 1)"
     ]
    }
   ],
   "metadata": {
    "kernelspec": {
     "display_name": "Python 3",
     "language": "python",
     "name": "python3"
    },
    "language_info": {
     "name": "python",
     "version": "3.12.1"
    },
    "ratio": 1.0
   },
   "nbformat": 4,
   "nbformat_minor": 5
  }

  """

@Suite struct NotebookModelTests {
  @Test func readingAndWritingChangesNoBytes() throws {
    let notebook = try Notebook(data: Data(sample.utf8))
    #expect(String(decoding: notebook.data(), as: UTF8.self) == sample)
  }

  @Test func readsCellsAndOutputs() throws {
    let notebook = try Notebook(data: Data(sample.utf8))
    #expect(notebook.cells.map(\.kind) == [.markdown, .code])
    #expect(notebook.cells[0].source == "# Résumé\nSome *text* \"quoted\".")
    #expect(notebook.cells[1].executionCount == 3)
    #expect(notebook.cells[1].outputs[0].text == "2\n")
    #expect(notebook.cells[1].outputs[1].image != nil)
    #expect(notebook.kernelName == "python3")
  }

  @Test func editingACellChangesOnlyItsSource() throws {
    var notebook = try Notebook(data: Data(sample.utf8))
    notebook.cells[1].source = "x = 2.0\nprint(1 + 1)"
    let written = String(decoding: notebook.data(), as: UTF8.self)
    let before = sample.components(separatedBy: "\n")
    let after = written.components(separatedBy: "\n")
    #expect(before.count == after.count)
    let changed = zip(before, after).filter { $0 != $1 }
    #expect(changed.map(\.1) == ["    \"x = 2.0\\n\","])
  }

  @Test func readableTextForDiffs() throws {
    let text = try Notebook(data: Data(sample.utf8)).readableText()
    #expect(text.contains("# %% [markdown] cell 1\n# Résumé\nSome *text*"))
    #expect(text.contains("# %% [code] [3] cell 2\nx = 1.0\nprint(1 + 1)"))
    #expect(text.contains("# >> stdout: 2"))
    #expect(text.contains("# >> image"))
    #expect(!text.contains("iVBORw0KGgo"))
  }

  @Test func jsonEscapesLikePython() {
    let value = JSONValue.object(["a": .string("tab\there \u{01} é / \\"), "b": .array([]), "c": .object([:])])
    #expect(JSONValue.write(value, indent: 1) == "{\n \"a\": \"tab\\there \\u0001 é / \\\\\",\n \"b\": [],\n \"c\": {}\n}")
  }

  /// A notebook another tool wrote in its own layout isn't rewritten just
  /// by being opened and closed.
  @MainActor @Test func openingANotebookNeverRewritesIt() throws {
    let compact = #"{"nbformat": 4, "nbformat_minor": 5, "metadata": {}, "cells": [{"cell_type": "code", "id": "a", "metadata": {}, "source": "1+1", "outputs": [], "execution_count": null}]}"#
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipynb")
    try compact.write(to: url, atomically: true, encoding: .utf8)
    let document = try NotebookDocument(url: url)
    #expect(!document.hasUnsavedChanges)
    try document.save()
    document.stopWatching()
    #expect(try String(contentsOf: url, encoding: .utf8) == compact)
  }

  @MainActor @Test func newCellsGetIDsOnlyInNewerNotebooks() throws {
    let old = sample.replacingOccurrences(of: "\"nbformat_minor\": 5", with: "\"nbformat_minor\": 4")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipynb")
    try old.write(to: url, atomically: true, encoding: .utf8)
    let document = try NotebookDocument(url: url)
    document.autosaveDelay = nil
    _ = document.insertCell(.code, after: nil)
    #expect(document.notebook.cells.last?.raw["id"] == nil)
  }
}

/// Notebooks in the diff read as cells.
@Suite struct NotebookDiffTests {
  @Test func aChangedNotebookDiffsAsCells() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("base", files: ["analysis.ipynb": sample])
    let changed = sample.replacingOccurrences(of: "print(1 + 1)", with: "print(2 + 2)")
    try changed.write(to: fixture.url.appendingPathComponent("analysis.ipynb"), atomically: true, encoding: .utf8)
    let repository = try await GitRepository.open(at: fixture.url)
    let diff = try await repository.workingTreeDiff(staged: false, path: nil)
    let file = try #require(diff.files.first)
    #expect(file.isRendered)
    let lines = file.hunks.flatMap(\.lines)
    #expect(lines.contains { $0.kind == .deletion && $0.text == "print(1 + 1)" })
    #expect(lines.contains { $0.kind == .addition && $0.text == "print(2 + 2)" })
    #expect(!lines.contains { $0.text.contains("\"source\"") })
    #expect(file.additions == 1 && file.deletions == 1)
  }

  @Test func aNewNotebookDiffsAsCells() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("base", files: ["README.md": "x\n"])
    try sample.write(to: fixture.url.appendingPathComponent("new.ipynb"), atomically: true, encoding: .utf8)
    let repository = try await GitRepository.open(at: fixture.url)
    let file = try #require(try await repository.workingTreeDiff(staged: false, path: nil).files.first)
    #expect(file.isRendered)
    #expect(file.hunks.flatMap(\.lines).contains { $0.text == "# %% [markdown] cell 1" })
  }
}

/// A real kernel, when the test Mac has a Python with Jupyter (set
/// GLINT_TEST_PYTHON, or Glint's own environment).
@MainActor @Suite(.serialized) struct NotebookKernelTests {
  private var python: URL? {
    if let path = ProcessInfo.processInfo.environment["GLINT_TEST_PYTHON"] { return URL(fileURLWithPath: path) }
    let own = NotebookKernel.ownEnvironment.appendingPathComponent("bin/python")
    return FileManager.default.isExecutableFile(atPath: own.path) ? own : nil
  }

  @Test func runsCellsAndSavesOutputs() async throws {
    guard let python else { return }
    UserDefaults.standard.set(python.path, forKey: "notebookPython")
    defer { UserDefaults.standard.removeObject(forKey: "notebookPython") }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("run.ipynb")
    try sample.write(to: url, atomically: true, encoding: .utf8)
    let document = try NotebookDocument(url: url)
    document.autosaveDelay = nil
    defer { document.stopWatching() }

    let code = document.notebook.cells[1].id
    document.setSource("print('hi')\n6 * 7", of: code)
    document.run(code, project: folder)
    let error = document.insertCell(.code, after: code)
    document.setSource("1/0", of: error)
    document.run(error, project: folder)
    for _ in 0..<600 where !document.running.isEmpty { try await Task.sleep(for: .milliseconds(100)) }

    let ran = try #require(document.notebook.cells.first { $0.id == code })
    #expect(ran.outputs.compactMap(\.text) == ["hi\n", "42"])
    #expect(ran.executionCount == 1)
    let failed = try #require(document.notebook.cells.first { $0.id == error })
    #expect(failed.outputs.first?.kind == .error)
    #expect(failed.outputs.first?.text?.contains("ZeroDivisionError") == true)
    // Saved the way Jupyter would read it back.
    try document.save()
    let reread = try Notebook(data: Data(contentsOf: url))
    #expect(reread.cells.first { $0.id == code }?.outputs.count == 2)
  }
}
