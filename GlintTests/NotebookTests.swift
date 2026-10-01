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

  @Test func kernelOutputsAreWrittenAsNbformatWritesThem() throws {
    let stream = try JSONValue.parse(Data(#"{"output_type": "stream", "name": "stdout", "text": "a\nb\n"}"#.utf8))
    #expect(Notebook.normalized(stream)["text"] == Notebook.lines("a\nb\n"))
    let display = try JSONValue.parse(Data(#"{"output_type": "display_data", "metadata": {}, "data": {"text/plain": "x\ny", "image/png": "AAAA", "application/json": {"a": 1}, "text/html": "<b>x</b>"}}"#.utf8))
    let data = try #require(Notebook.normalized(display)["data"])
    #expect(data["text/plain"] == .array([.string("x\n"), .string("y")]))
    #expect(data["text/html"] == .array([.string("<b>x</b>")]))
    #expect(data["image/png"] == .string("AAAA"))
    #expect(data["application/json"]?["a"] == .number("1"))
    // Reading it back gives the same text.
    #expect(Notebook.Output(kind: .displayData, raw: Notebook.normalized(display)).text == "x\ny")
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

@MainActor @Suite struct NotebookFilesTabTests {
  @Test func theFilesTabOpensANotebook() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("base", files: ["notebooks/a.ipynb": sample])
    let session = RepositorySession()
    session.install(try await RepositorySession.load(fixture.url))
    session.showFile("notebooks/a.ipynb")
    #expect(session.alert == nil)
    #expect(session.openedNotebook?.notebook.cells.count == 2)
    #expect(session.tab == .files)
    session.closeOpenedFile()
    // Opening and closing left the file as it was.
    #expect(try String(contentsOf: fixture.url.appendingPathComponent("notebooks/a.ipynb"), encoding: .utf8) == sample)
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
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("run.ipynb")
    try sample.write(to: url, atomically: true, encoding: .utf8)
    let document = try NotebookDocument(url: url)
    document.kernel.pythonOverride = python
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

/// Set Up Python against the network and a real toolchain (uv or pip), in a
/// temporary folder: set GLINT_TEST_SETUP=1. Takes about a minute.
@MainActor @Suite(.serialized) struct NotebookSetUpTests {
  @Test(arguments: [true, false]) func buildsAnEnvironmentThatRunsACell(usingUV: Bool) async throws {
    guard ProcessInfo.processInfo.environment["GLINT_TEST_SETUP"] != nil else { return }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("glint-setup-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let kernel = NotebookKernel()
    let python = try await kernel.setUp(environment: folder.appendingPathComponent("env"), usingUV: usingUV)
    #expect(await NotebookKernel.hasJupyter(python))
    #expect(kernel.state == .stopped)
    // And it can run a cell.
    let notebookURL = folder.appendingPathComponent("n.ipynb")
    try sample.write(to: notebookURL, atomically: true, encoding: .utf8)
    let document = try NotebookDocument(url: notebookURL)
    document.autosaveDelay = nil
    document.kernel.pythonOverride = python
    defer { document.stopWatching() }
    let cell = document.notebook.cells[1].id
    document.setSource("6 * 7", of: cell)
    document.run(cell, project: folder)
    for _ in 0..<600 where !document.running.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
    #expect(document.notebook.cells.first { $0.id == cell }?.outputs.compactMap(\.text) == ["42"])
  }
}

/// Real notebooks: set GLINT_TEST_NOTEBOOKS to a folder. Reads only.
@Suite struct NotebookCorpusTests {
  @Test func everyNotebookReadsAndMostRoundTripExactly() throws {
    guard let folder = ProcessInfo.processInfo.environment["GLINT_TEST_NOTEBOOKS"] else { return }
    let files = FileManager.default.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)!
      .compactMap { $0 as? URL }
      .filter { $0.pathExtension == "ipynb" && !$0.path.contains("/node_modules/") && !$0.path.contains("/.venv/") }
    var exact = 0
    var different: [String] = []
    for url in files {
      let data = try Data(contentsOf: url)
      let notebook = try Notebook(data: data)
      _ = notebook.readableText()
      if notebook.data() == data { exact += 1 } else { different.append(url.lastPathComponent) }
    }
    print("NOTEBOOK-CORPUS total=\(files.count) exact=\(exact) different=\(different)")
    #expect(!files.isEmpty)
    #expect(exact == files.count, "These rewrite differently: \(different)")
  }
}

/// Files written by other tools keep their own layout.
@Suite struct NotebookFormatTests {
  private func roundTrip(_ text: String) throws -> String {
    String(decoding: try Notebook(data: Data(text.utf8)).data(), as: UTF8.self)
  }

  @Test func twoSpaceIndentNoFinalNewline() throws {
    let text = "{\n  \"cells\": [],\n  \"metadata\": {},\n  \"nbformat\": 4,\n  \"nbformat_minor\": 5\n}"
    #expect(try roundTrip(text) == text)
  }

  @Test func unsortedKeysKeepTheirOrder() throws {
    let text = "{\n \"nbformat\": 4,\n \"cells\": [\n  {\n   \"source\": \"x\",\n   \"cell_type\": \"code\",\n   \"outputs\": [],\n   \"metadata\": {},\n   \"execution_count\": null\n  }\n ],\n \"metadata\": {},\n \"nbformat_minor\": 5\n}\n"
    #expect(try roundTrip(text) == text)
  }

  @Test func asciiEscapedFilesStayAsciiEscaped() throws {
    let text = "{\n \"cells\": [\n  {\n   \"cell_type\": \"markdown\",\n   \"metadata\": {},\n   \"source\": [\n    \"caf\\u00e9 \\ud83d\\ude00\"\n   ]\n  }\n ],\n \"metadata\": {},\n \"nbformat\": 4,\n \"nbformat_minor\": 4\n}\n"
    let notebook = try Notebook(data: Data(text.utf8))
    #expect(notebook.cells[0].source == "café 😀")
    #expect(try roundTrip(text) == text)
  }

  @Test func aStringSourceStaysAStringWhenEdited() throws {
    let text = "{\"cells\": [{\"cell_type\": \"code\", \"execution_count\": null, \"metadata\": {}, \"outputs\": [], \"source\": \"a = 1\"}], \"metadata\": {}, \"nbformat\": 4, \"nbformat_minor\": 4}"
    var notebook = try Notebook(data: Data(text.utf8))
    notebook.cells[0].source = "a = 2\nb = 3"
    let written = String(decoding: notebook.data(), as: UTF8.self)
    #expect(written.contains("\"source\": \"a = 2\\nb = 3\""))
  }

  @Test func editingOneCellOfAnotherToolsFileChangesOnlyThatCell() throws {
    let text = "{\n  \"cells\": [\n    {\n      \"cell_type\": \"code\",\n      \"source\": \"keep\",\n      \"metadata\": {},\n      \"outputs\": [],\n      \"execution_count\": null\n    },\n    {\n      \"cell_type\": \"code\",\n      \"source\": \"change me\",\n      \"metadata\": {},\n      \"outputs\": [],\n      \"execution_count\": null\n    }\n  ],\n  \"metadata\": {},\n  \"nbformat\": 4,\n  \"nbformat_minor\": 5\n}\n"
    var notebook = try Notebook(data: Data(text.utf8))
    notebook.cells[1].source = "changed"
    let before = text.components(separatedBy: "\n")
    let after = String(decoding: notebook.data(), as: UTF8.self).components(separatedBy: "\n")
    #expect(before.count == after.count)
    #expect(zip(before, after).filter { $0 != $1 }.map(\.1) == ["      \"source\": \"changed\","])
  }

  @Test func compactSingleLineFilesRoundTrip() throws {
    let text = #"{"cells": [], "metadata": {}, "nbformat": 4, "nbformat_minor": 5}"#
    // One line has no indent to copy; Jupyter's layout is used, which is
    // still the same document.
    let notebook = try Notebook(data: Data((try roundTrip(text)).utf8))
    #expect(notebook.cells.isEmpty)
  }
}

@MainActor @Suite(.serialized) struct NotebookInterruptTests {
  private var python: URL? {
    if let path = ProcessInfo.processInfo.environment["GLINT_TEST_PYTHON"] { return URL(fileURLWithPath: path) }
    let own = NotebookKernel.ownEnvironment.appendingPathComponent("bin/python")
    return FileManager.default.isExecutableFile(atPath: own.path) ? own : nil
  }

  /// Interrupt stops the running cell and drops the queued ones, and a cell
  /// that never ran keeps the output it had; one that ran silently loses it.
  @Test func interruptKeepsTheOutputsOfCellsThatNeverRan() async throws {
    guard let python else { return }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("i.ipynb")
    try sample.write(to: url, atomically: true, encoding: .utf8)
    let document = try NotebookDocument(url: url)
    document.kernel.pythonOverride = python
    document.autosaveDelay = nil
    defer { document.stopWatching() }

    let calc = document.notebook.cells[1].id            // has a stdout output "2\n" and an image
    let slow = document.insertCell(.code, after: calc)
    document.setSource("import time\ntime.sleep(60)", of: slow)
    document.run(slow, project: folder)
    document.run(calc, project: folder)                  // waits behind the sleep
    for _ in 0..<300 where document.kernel.state != .busy { try await Task.sleep(for: .milliseconds(100)) }
    #expect(document.kernel.state == .busy)
    #expect(document.notebook.cells.first { $0.id == calc }?.outputs.count == 2)  // not cleared by queueing

    document.kernel.interrupt()
    for _ in 0..<300 where !document.running.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
    #expect(document.running.isEmpty)
    // Never ran: the old output is still there.
    #expect(document.notebook.cells.first { $0.id == calc }?.outputs.count == 2)
    // The interrupted cell shows the KeyboardInterrupt.
    #expect(document.notebook.cells.first { $0.id == slow }?.outputs.first?.kind == .error)

    // The kernel is still usable afterwards.
    document.setSource("21 * 2", of: calc)
    document.run(calc, project: folder)
    for _ in 0..<300 where !document.running.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
    #expect(document.notebook.cells.first { $0.id == calc }?.outputs.compactMap(\.text) == ["42"])
  }
}

/// What Glint saves after real runs is what Jupyter's own library validates
/// and would write byte for byte. Needs a Python with nbformat too.
@MainActor @Suite(.serialized) struct NotebookInteropTests {
  @Test func savedNotebooksMatchNbformatByteForByte() async throws {
    guard let path = ProcessInfo.processInfo.environment["GLINT_TEST_PYTHON"] else { return }
    let python = URL(fileURLWithPath: path)
    guard await NotebookKernel.run(python, ["-c", "import nbformat"]) == 0 else { return }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("interop.ipynb")
    try JSONValue.write(try JSONValue.parse(Data(sample.utf8)), indent: 1).write(to: url, atomically: true, encoding: .utf8)
    let document = try NotebookDocument(url: url)
    document.autosaveDelay = nil
    document.kernel.pythonOverride = python
    defer { document.stopWatching() }

    let sources = [
      "print('line one')\nprint('line two')\nimport sys; print('to stderr', file=sys.stderr)\n'last expression'",
      "from IPython.display import HTML, Markdown, JSON, display\ndisplay(HTML('<b>bold</b>'))\ndisplay(Markdown('**md**'))\ndisplay(JSON({'a': [1, 2]}))",
      "import base64\nfrom IPython.display import Image\nImage(data=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAoAAAAKCAYAAACNMs+9AAAAFUlEQVR42mP8z8BQz0AEYBxVSF+FABJADveWkH6oAAAAAElFTkSuQmCC'))",
      "print('café 😀 ünïcode')",
      "1 / 0",
      "x = 5",
    ]
    var ids: [String] = []
    var after: String? = document.notebook.cells.last?.id
    for source in sources {
      let id = document.insertCell(.code, after: after)
      document.setSource(source, of: id)
      ids.append(id)
      after = id
    }
    for id in ids { document.run(id, project: folder) }
    for _ in 0..<600 where !document.running.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
    #expect(document.running.isEmpty)
    try document.save()
    if let keep = ProcessInfo.processInfo.environment["GLINT_TEST_KEEP"] { try? FileManager.default.removeItem(atPath: keep); try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: keep)) }

    let check = """
      import sys, nbformat
      raw = open(sys.argv[1], encoding='utf-8').read()
      nb = nbformat.reads(raw, as_version=4)
      nbformat.validate(nb)
      sys.exit(0 if nbformat.writes(nb) == raw else 3)
      """
    let status = await NotebookKernel.run(python, ["-c", check, url.path])
    #expect(status == 0, "Jupyter's nbformat rejected the file (1) or would write it differently (3): exit \(status)")
  }
}

@Suite struct NotebookDiffTextTests {
  /// A notebook diff once drew bars with no text: libgit2 read the lines
  /// from buffers already freed. Many diffs, with allocations between them,
  /// would have shown it.
  @Test func changedLinesAlwaysCarryTheirText() async throws {
    let fixture = try FixtureRepository()
    let big = sample.replacingOccurrences(of: "print(1 + 1)", with: String(repeating: "x = 1 + 1; ", count: 40))
    try fixture.commit("base", files: ["a.ipynb": big])
    try big.replacingOccurrences(of: "x = 1 + 1;", with: "y = 2 * 2;")
      .write(to: fixture.url.appendingPathComponent("a.ipynb"), atomically: true, encoding: .utf8)
    let repository = try await GitRepository.open(at: fixture.url)
    var churn: [[UInt8]] = []
    for round in 0..<200 {
      let diff = try await repository.workingTreeDiff(staged: false, path: nil)
      let changed = try #require(diff.files.first).hunks.flatMap(\.lines).filter { $0.kind != .context }
      #expect(changed.count == 2, "round \(round)")
      #expect(changed.allSatisfy { $0.text.contains("= ") }, "round \(round): \(changed.map(\.text))")
      churn.append([UInt8](repeating: UInt8(round % 250), count: 4096))
      if churn.count > 50 { churn.removeFirst() }
    }
  }
}

@MainActor @Suite struct NotebookConflictTests {
  private func open(_ text: String = sample) throws -> (NotebookDocument, URL) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipynb")
    try text.write(to: url, atomically: true, encoding: .utf8)
    let document = try NotebookDocument(url: url)
    document.autosaveDelay = nil
    return (document, url)
  }

  /// Another tool saves the file while you have no unsaved changes: it loads.
  @Test func anExternalChangeReloadsWhenYouHaveNone() throws {
    let (document, url) = try open()
    defer { document.stopWatching() }
    try sample.replacingOccurrences(of: "print(1 + 1)", with: "print(9)").write(to: url, atomically: true, encoding: .utf8)
    // The modification date can match within a tick; make it differ.
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
    document.syncFromDisk()
    #expect(document.notebook.cells[1].source.contains("print(9)"))
    #expect(!document.hasConflict)
    #expect(document.note?.contains("Reloaded") == true)
  }

  @Test func yourUnsavedEditsAreNeverOverwrittenBySilentReloads() throws {
    let (document, url) = try open()
    defer { document.stopWatching() }
    document.setSource("mine = 1", of: document.notebook.cells[1].id)
    try sample.replacingOccurrences(of: "print(1 + 1)", with: "print(9)").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
    document.syncFromDisk()
    #expect(document.hasConflict)
    #expect(document.notebook.cells[1].source == "mine = 1")
    // Nothing is written while it's undecided.
    #expect(try String(contentsOf: url, encoding: .utf8).contains("print(9)"))
  }

  @Test func keepMineWritesYoursUseTheirsTakesTheFile() throws {
    var (document, url) = try open()
    document.setSource("mine = 1", of: document.notebook.cells[1].id)
    try sample.replacingOccurrences(of: "print(1 + 1)", with: "print(9)").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
    document.syncFromDisk()
    try document.keepMine()
    #expect(try String(contentsOf: url, encoding: .utf8).contains("mine = 1"))
    #expect(!document.hasConflict && !document.hasUnsavedChanges)
    document.stopWatching()

    (document, url) = try open()
    document.setSource("mine = 1", of: document.notebook.cells[1].id)
    try sample.replacingOccurrences(of: "print(1 + 1)", with: "print(9)").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
    document.syncFromDisk()
    document.useTheirs()
    #expect(document.notebook.cells[1].source.contains("print(9)"))
    #expect(!document.hasConflict && !document.hasUnsavedChanges)
    document.stopWatching()
  }
}

/// The real file watcher (FSEvents), end to end: edit a file under an open
/// repository and the Changes list follows by itself.
@MainActor @Suite(.serialized) struct LiveWatcherTests {
  @Test func editsAppearInTheChangesListWithoutAReload() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("base", files: ["a.txt": "1\n", "n.ipynb": sample])
    let session = RepositorySession()
    session.install(try await RepositorySession.load(fixture.url))
    try await Task.sleep(for: .milliseconds(500))
    #expect(session.status.isClean)
    for round in 0..<3 {
      try "changed \(round)\n".write(to: fixture.url.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
      var seen = false
      for _ in 0..<60 where !seen {
        try await Task.sleep(for: .milliseconds(50))
        seen = session.status.unstaged.contains { $0.path == "a.txt" }
      }
      #expect(seen, "round \(round): the list never showed the edit")
      try await GitRepository.open(at: fixture.url).discard(["a.txt"])
      for _ in 0..<60 where session.status.unstaged.contains(where: { $0.path == "a.txt" }) {
        try await Task.sleep(for: .milliseconds(50))
      }
    }
  }
}
