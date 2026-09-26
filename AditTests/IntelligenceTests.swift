import Foundation
import Testing

@testable import Adit

@Suite struct AIProviderTests {
  @Test func openRouterKeepsOnlyZeroPricedTextModels() throws {
    let json = """
      {"data": [
        {"id": "a/free:free", "name": "A Free", "pricing": {"prompt": "0", "completion": "0"},
         "architecture": {"output_modalities": ["text"]}},
        {"id": "b/paid", "name": "B", "pricing": {"prompt": "0.000001", "completion": "0.000002"}},
        {"id": "c/image:free", "name": "C", "pricing": {"prompt": "0", "completion": "0"},
         "architecture": {"output_modalities": ["image"]}}
      ]}
      """
    let models = try AIProvider.openRouter.freeModels(from: Data(json.utf8))
    #expect(models.map(\.id) == ["a/free:free"])
  }

  @Test func vercelKeepsFreeLanguageModels() throws {
    let json = """
      {"object": "list", "data": [
        {"id": "x/free", "name": "X", "type": "language", "pricing": {"input": "0", "output": "0"}},
        {"id": "y/paid", "name": "Y", "type": "language", "pricing": {"input": "0.1", "output": "0.2"}},
        {"id": "z/video", "name": "Z", "type": "video", "pricing": {"input": "0", "output": "0"}}
      ]}
      """
    #expect(try AIProvider.vercel.freeModels(from: Data(json.utf8)).map(\.id) == ["x/free"])
  }

  @Test func zenKeepsFreeChatCompletionModels() throws {
    let json = """
      [{"id": "big-pickle"}, {"id": "mimo-v2.5-free"}, {"id": "claude-fable-5"},
       {"id": "jev-1.13-free"}, {"id": "muse-spark-1.3-contributor-free"}]
      """
    let ids = try AIProvider.openCodeZen.freeModels(from: Data(json.utf8)).map(\.id)
    #expect(Set(ids) == ["big-pickle", "mimo-v2.5-free"])
  }
}

@Suite struct AIClientTests {
  @Test func parsesServerSentEvents() {
    #expect(AIClient.parse(#"data: {"choices":[{"delta":{"content":"Add"}}]}"#) == .text("Add"))
    #expect(AIClient.parse("data: [DONE]") == .done)
    #expect(AIClient.parse(": OPENROUTER PROCESSING") == .ignore)
    #expect(AIClient.parse("") == .ignore)
    #expect(AIClient.parse(#"data: {"choices":[{"delta":{"role":"assistant"}}]}"#) == .ignore)
    #expect(AIClient.parse(#"data: {"error":{"message":"Rate limited"}}"#) == .failure("Rate limited"))
  }

  @Test func explainsCommonHTTPErrors() {
    let unauthorized = AIClient.errorMessage(status: 401, body: #"{"error":{"message":"bad key"}}"#, provider: .openRouter)
    #expect(unauthorized.contains("API key"))
    #expect(unauthorized.contains("bad key"))
    #expect(AIClient.errorMessage(status: 429, body: "", provider: .vercel).contains("rate limiting"))
  }
}

@Suite struct CommitPromptTests {
  @Test func cleansReasoningAndFences() {
    #expect(CommitPrompt.clean("<think>hmm</think>\nAdd login") == "Add login")
    #expect(CommitPrompt.clean("```\nFix crash\n\nBody\n```") == "Fix crash\n\nBody")
    // Mid-stream, an unfinished reasoning block stays hidden.
    #expect(CommitPrompt.clean("<think>still thinking") == "")
  }

  @Test func leavesSmallDiffsAlone() {
    let diff = "diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-a\n+b\n"
    #expect(CommitPrompt.compress(diff) == diff)
  }

  @Test func compressesLargeDiffsUnderTheLimit() {
    var diff = ""
    for file in 0..<4 {
      diff += "diff --git a/f\(file) b/f\(file)\n--- a/f\(file)\n+++ b/f\(file)\n"
      for hunk in 0..<40 {
        diff += "@@ -\(hunk * 10),3 +\(hunk * 10),3 @@\n"
        diff += String(repeating: "+line of changed code in hunk \(hunk)\n", count: 6)
      }
    }
    #expect(diff.utf8.count > 20_000)
    let compressed = CommitPrompt.compress(diff, maxBytes: 20_000)
    #expect(compressed.utf8.count <= 20_000)
    // Every file keeps its header and first hunk.
    for file in 0..<4 { #expect(compressed.contains("diff --git a/f\(file) b/f\(file)")) }
    #expect(compressed.contains("left out"))
  }

  @Test func clipsVeryLongLines() {
    let long = "+" + String(repeating: "x", count: 30_000)
    let compressed = CommitPrompt.compress("diff --git a/min.js b/min.js\n@@ -1 +1 @@\n\(long)\n")
    #expect(compressed.contains("[line clipped]"))
    #expect(compressed.utf8.count < 1_000)
  }

  @Test func promptCarriesSubjectRulesAndDiff() {
    let prompt = CommitPrompt.build(diff: "DIFF", subject: "Fix login", rules: "Use emoji", userInstructions: "Be terse")
    #expect(prompt.contains("Fix login"))
    #expect(prompt.contains("<repository_rules>\nUse emoji"))
    #expect(prompt.contains("Be terse"))
    #expect(prompt.hasSuffix("DIFF"))
  }

  @Test func rendersAPatchLikeGit() {
    let hunk = Hunk(
      id: 0, header: "@@ -1,2 +1,2 @@", oldStart: 1, oldCount: 2, newStart: 1, newCount: 2,
      lines: [
        DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "a"),
        DiffLine(kind: .deletion, oldNumber: 2, newNumber: nil, text: "b"),
        DiffLine(kind: .addition, oldNumber: nil, newNumber: 2, text: "c"),
      ])
    let diff = Diff(
      source: .workingTree(staged: true, path: nil),
      files: [
        FileChange(
          id: 0, status: .modified, oldPath: "f.txt", newPath: "f.txt", isBinary: false, hunks: [hunk],
          additions: 1, deletions: 1)
      ])
    #expect(
      CommitPrompt.patchText(diff)
        == "diff --git a/f.txt b/f.txt\n--- a/f.txt\n+++ b/f.txt\n@@ -1,2 +1,2 @@\n a\n-b\n+c\n")
  }
}
