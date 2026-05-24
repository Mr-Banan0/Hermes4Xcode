import Foundation

actor HermesAPIClient {
    let baseURL = "http://127.0.0.1:8642"

    func sendMessage(
        _ text: String,
        contextCode: String? = nil,
        history: [[String: String]] = [],
        model: String = "hermes-agent",
        onDelta: @escaping @Sendable (String) -> Void,
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
        req.httpBody = jsonData

        let delegate = SSEStreamDelegate(
            onDelta: onDelta,
            onComplete: onComplete
        )
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        session.dataTask(with: req).resume()
    }
}

// MARK: - SSE Stream Parser

final class SSEStreamDelegate: NSObject, URLSessionDataDelegate {
    private var buffer = ""
    private var accumulatedText = ""
    private let onDelta: (String) -> Void
    private let onComplete: (Result<String, Error>) -> Void
    private var didComplete = false

    init(onDelta: @escaping (String) -> Void,
         onComplete: @escaping (Result<String, Error>) -> Void) {
        self.onDelta = onDelta
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

            if let choice = (json["choices"] as? [[String: Any]])?.first,
               let delta = choice["delta"] as? [String: Any],
               let content = delta["content"] as? String {
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
