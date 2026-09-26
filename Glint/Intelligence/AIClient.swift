import Foundation

/// Streams a chat completion from an OpenAI-compatible endpoint.
struct AIClient: Sendable {
  let provider: AIProvider
  let apiKey: String

  struct Failure: Error, CustomStringConvertible {
    let message: String
    /// Busy rather than broken: rate limited or a server error. Worth trying
    /// another free model; a bad key or bad request isn't.
    var isBusy = false
    var description: String { message }
  }

  /// The model's reply, a piece at a time.
  func stream(model: String, prompt: String) -> AsyncThrowingStream<String, Error> {
    var request = URLRequest(url: provider.chatCompletionsURL, timeoutInterval: 60)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    for (field, value) in provider.extraHeaders { request.setValue(value, forHTTPHeaderField: field) }
    let body: [String: Any] = [
      "model": model,
      "stream": true,
      "messages": [["role": "user", "content": prompt]],
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let provider = self.provider
    let finished = request

    return AsyncThrowingStream { continuation in
      let task = Task { @Sendable in
        do {
          let (bytes, response) = try await URLSession.shared.bytes(for: finished)
          let status = (response as? HTTPURLResponse)?.statusCode ?? 0
          guard status == 200 else {
            var body = ""
            for try await line in bytes.lines { body += line }
            throw Failure(
              message: Self.errorMessage(status: status, body: body, provider: provider),
              isBusy: status == 429 || status >= 500)
          }
          for try await line in bytes.lines {
            switch Self.parse(line) {
            case .text(let text): continuation.yield(text)
            case .done: continuation.finish()
              return
            case .failure(let message):
              // An error mid-stream from an upstream host is almost always it
              // being overloaded.
              throw Failure(message: message, isBusy: true)
            case .ignore: break
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  enum Event: Equatable {
    case text(String), done, failure(String), ignore
  }

  /// One line of a server-sent event stream. Comment lines (OpenRouter sends
  /// keep-alives as `: OPENROUTER PROCESSING`) and blank lines are ignored.
  static func parse(_ line: String) -> Event {
    guard line.hasPrefix("data:") else { return .ignore }
    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
    if payload == "[DONE]" { return .done }
    guard let data = payload.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return .ignore }
    if let error = json["error"] as? [String: Any] {
      return .failure(error["message"] as? String ?? "The model returned an error.")
    }
    guard let choices = json["choices"] as? [[String: Any]], let first = choices.first,
      let delta = first["delta"] as? [String: Any], let content = delta["content"] as? String,
      !content.isEmpty
    else { return .ignore }
    return .text(content)
  }

  static func errorMessage(status: Int, body: String, provider: AIProvider) -> String {
    let detail =
      (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
      .flatMap { ($0["error"] as? [String: Any])?["message"] as? String ?? $0["message"] as? String }
      ?? body.prefix(300).description
    switch status {
    case 401, 403: return "\(provider.name) didn't accept your API key. Check it in Settings.\n\n\(detail)"
    case 429: return "\(provider.name) is rate limiting free requests right now. Try again in a minute or pick another model.\n\n\(detail)"
    default: return "\(provider.name) returned an error (\(status)).\n\n\(detail)"
    }
  }

  /// Free chat models a provider currently offers. The listings are public,
  /// so this works before you've added a key.
  static func freeModels(for provider: AIProvider) async throws -> [AIModel] {
    var request = URLRequest(url: provider.modelsURL, timeoutInterval: 20)
    for (field, value) in provider.extraHeaders { request.setValue(value, forHTTPHeaderField: field) }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw Failure(message: "Couldn't load \(provider.name)'s models.")
    }
    return try provider.freeModels(from: data)
  }
}
