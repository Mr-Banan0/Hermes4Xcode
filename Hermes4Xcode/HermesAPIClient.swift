import Foundation

actor HermesAPIClient {
    let baseURL = "http://127.0.0.1:8642"
    let apiKey: String = {
        ProcessInfo.processInfo.environment["API_SERVER_KEY"]
            ?? "hermes4xcode-local-dev-key"
    }()

    func sendMessage(
        _ text: String,
        contextCode: String? = nil,
        history: [[String: String]] = [],
        model: String = "hermes-agent",
        onDelta: @escaping @Sendable (String) -> Void,
        onReasoningDelta: @escaping @Sendable (String) -> Void = { _ in },
        onComplete: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        var messages = history

        if let code = contextCode, !code.isEmpty {
            messages.append([
                "role": "system",
                "content": "The user has the following code context in Xcode:\n\n```swift\n\(code)\n```\n\nUse this context to inform your response. You have access to xcodebuild and AppleScript tools via the Hermes Gateway backend."
            ])
        }

        messages.append(["role": "user", "content": text])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            onComplete(.failure(NSError(domain: "Hermes", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create request"])))
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = jsonData

        let delegate = SSEStreamDelegate(
            onDelta: onDelta,
            onReasoningDelta: onReasoningDelta,
            onComplete: onComplete
        )
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        session.dataTask(with: req).resume()
    }

    /// Check if the Hermes Gateway is reachable on port 8642.
    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(baseURL)/v1/models") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - SSE Stream Parser

final class SSEStreamDelegate: NSObject, URLSessionDataDelegate {
    private var buffer = ""
    private var accumulatedText = ""
    private var accumulatedReasoning = ""
    private let onDelta: (String) -> Void
    private let onReasoningDelta: ((String) -> Void)?
    private let onComplete: (Result<String, Error>) -> Void
    private var didComplete = false

    init(onDelta: @escaping (String) -> Void,
         onReasoningDelta: ((String) -> Void)? = nil,
         onComplete: @escaping (Result<String, Error>) -> Void) {
        self.onDelta = onDelta
        self.onReasoningDelta = onReasoningDelta
        self.onComplete = onComplete
    }

    private func finish(_ result: Result<String, Error>) {
        guard !didComplete else { return }
        didComplete = true
        onComplete(result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        buffer += String(data: data, encoding: .utf8) ?? ""
        while let endIdx = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<endIdx])
            buffer = String(buffer[buffer.index(after: endIdx)...])
            guard line.hasPrefix("data: ") else { continue }

            let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" {
                finish(.success(accumulatedText))
                return
            }

            guard let d = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            else { continue }

            // Format 1: Standard OpenAI chat completions: choices[0].delta.content
            if let choice = (json["choices"] as? [[String: Any]])?.first,
               let delta = choice["delta"] as? [String: Any] {
                // Normal content text
                if let content = delta["content"] as? String {
                    accumulatedText += content
                    onDelta(content)
                }
                // Reasoning from model (DeepSeek, Qwen, etc.)
                if let reasoning = delta["reasoning"] as? String {
                    accumulatedReasoning += reasoning
                    onReasoningDelta?(reasoning)
                } else if let reasoning = delta["reasoning_content"] as? String {
                    accumulatedReasoning += reasoning
                    onReasoningDelta?(reasoning)
                }
            // Format 2: Hermes Gateway thinking/status (top-level "content" field)
            } else if let content = json["content"] as? String, !content.isEmpty {
                accumulatedText += content
                onDelta(content)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            finish(.failure(error))
        } else {
            finish(.success(accumulatedText))
        }
    }
}
