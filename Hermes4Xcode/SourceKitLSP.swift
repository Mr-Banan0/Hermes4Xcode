import Foundation
import SwiftUI

// MARK: - LSP Diagnostic Model

/// A single diagnostic from sourcekit-lsp (error, warning, info).
struct LSPDiagnosticItem: Identifiable, Equatable {
    let id = UUID()
    let file: String      /// URI like file:///path/to/file.swift
    let line: Int         /// 0-based line from LSP
    let column: Int       /// 0-based column from LSP
    let severity: DiagnosticSeverity
    let message: String

    var lineDisplay: Int { line + 1 }  /// 1-based for display

    static func == (lhs: LSPDiagnosticItem, rhs: LSPDiagnosticItem) -> Bool {
        lhs.file == rhs.file && lhs.line == rhs.line &&
        lhs.column == rhs.column && lhs.severity == rhs.severity &&
        lhs.message == rhs.message
    }
}

enum DiagnosticSeverity: Int, Equatable {
    case error = 1
    case warning = 2
    case info = 3
    case hint = 4

    var color: Color {
        switch self {
        case .error:   return .red
        case .warning: return .yellow
        case .info:    return .blue
        case .hint:    return .secondary
        }
    }

    var icon: String {
        switch self {
        case .error:   return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        case .hint:    return "lightbulb.fill"
        }
    }
}

// MARK: - SourceKit-LSP JSON-RPC Client

final class SourceKitLSPClient {
    static let shared = SourceKitLSPClient()

    private var process: Process?
    private let queue = DispatchQueue(label: "sourcekit-lsp")
    private var buffer = ""
    private var responseHandlers: [String: (Result<[String: Any], Error>) -> Void] = [:]
    private var isInitialized = false

    /// Latest diagnostics received from sourcekit-lsp, keyed by file URI.
    private(set) var currentDiagnostics: [LSPDiagnosticItem] = []

    /// Called on the main thread when new diagnostics arrive.
    var onDiagnosticsChanged: (([LSPDiagnosticItem]) -> Void)?

    private init() {}

    /// Start the sourcekit-lsp server.
    func start() -> Bool {
        guard process == nil else { return true }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["sourcekit-lsp"]

        let outPipe = Pipe()
        let inPipe = Pipe()
        p.standardOutput = outPipe
        p.standardInput = inPipe
        p.standardError = FileHandle.nullDevice

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleResponse(data)
        }

        do {
            try p.run()
            process = p

            // Send initialize request
            let initReq: [String: Any] = [
                "jsonrpc": "2.0",
                "id": "init",
                "method": "initialize",
                "params": [
                    "processId": Int(ProcessInfo.processInfo.processIdentifier),
                    "capabilities": [:]
                ]
            ]
            sendRequest(initReq)

            // Send initialized notification
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.sendNotification([
                    "jsonrpc": "2.0",
                    "method": "initialized",
                    "params": [:]
                ])
                self?.isInitialized = true
            }

            return true
        } catch {
            NSLog("[Hermes4Xcode] Failed to start sourcekit-lsp: \(error)")
            return false
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        isInitialized = false
    }

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    // MARK: - Document Management

    /// Open a file in the LSP server to trigger analysis and diagnostics.
    func openDocument(file path: String) {
        guard isInitialized else { return }
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let uri = URL(fileURLWithPath: path).absoluteString
            let openReq: [String: Any] = [
                "jsonrpc": "2.0",
                "id": UUID().uuidString,
                "method": "textDocument/didOpen",
                "params": [
                    "textDocument": [
                        "uri": uri,
                        "languageId": "swift",
                        "version": 1,
                        "text": content
                    ]
                ]
            ]
            sendNotification(openReq)
        } catch {
            NSLog("[Hermes4Xcode] Failed to read file for LSP: \(error)")
        }
    }

    /// Request document symbols for a file.
    func getDocumentSymbols(file path: String) async -> String? {
        guard isInitialized else { return nil }

        let uri = URL(fileURLWithPath: path).absoluteString

        let symbolReq: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "diag",
            "method": "textDocument/documentSymbol",
            "params": [
                "textDocument": ["uri": uri]
            ]
        ]

        return try? await withCheckedThrowingContinuation { continuation in
            let key = "diag"
            responseHandlers[key] = { result in
                defer { self.responseHandlers.removeValue(forKey: key) }
                switch result {
                case .success(let resp):
                    if let symbols = resp["result"] as? [[String: Any]] {
                        let kindCounts = symbols.reduce(into: [String: Int]()) { counts, sym in
                            let kind = (sym["kind"] as? Int).map { Self.symbolKindLabel($0) } ?? "symbol"
                            counts[kind, default: 0] += 1
                        }
                        let summary = kindCounts
                            .sorted { $0.value > $1.value }
                            .map { "\($0.key) ×\($0.value)" }
                            .joined(separator: ", ")
                        let fileName = (path as NSString).lastPathComponent
                        continuation.resume(returning: summary.isEmpty
                            ? "✅ \(fileName) — \(symbols.count) symbols"
                            : "✅ \(fileName)\n  \(summary)")
                    } else if let error = resp["error"] as? [String: Any] {
                        continuation.resume(returning: "⚠️ LSP: \(error["message"] ?? "unknown error")")
                    } else {
                        continuation.resume(returning: "✅ \((path as NSString).lastPathComponent)")
                    }
                case .failure:
                    continuation.resume(throwing: NSError(domain: "LSP", code: -1))
                }
            }
            sendRequest(symbolReq)

            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if self.responseHandlers[key] != nil {
                    self.responseHandlers.removeValue(forKey: key)
                    continuation.resume(returning: "✅ \((path as NSString).lastPathComponent)")
                }
            }
        }
    }

    /// Get hover info for a symbol at a position.
    func getHover(file path: String, line: Int, column: Int) async -> String? {
        guard isInitialized else { return nil }
        let uri = URL(fileURLWithPath: path).absoluteString

        let hoverReq: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "hover",
            "method": "textDocument/hover",
            "params": [
                "textDocument": ["uri": uri],
                "position": ["line": line - 1, "character": column]
            ]
        ]

        return await withCheckedContinuation { continuation in
            let key = "hover"
            responseHandlers[key] = { result in
                switch result {
                case .success(let resp):
                    if let result = resp["result"] as? [String: Any],
                       let contents = result["contents"] as? [String: Any],
                       let value = contents["value"] as? String {
                        continuation.resume(returning: value)
                    } else {
                        continuation.resume(returning: nil)
                    }
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
            sendRequest(hoverReq)

            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if self.responseHandlers[key] != nil {
                    self.responseHandlers.removeValue(forKey: key)
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Private

    private func sendRequest(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let process = process,
              let inPipe = process.standardInput as? Pipe
        else { return }
        let headerData = Data("Content-Length: \(data.count)\r\n\r\n".utf8)
        inPipe.fileHandleForWriting.write(headerData)
        inPipe.fileHandleForWriting.write(data)
    }

    private func sendNotification(_ dict: [String: Any]) {
        sendRequest(dict)
    }

    private func handleResponse(_ data: Data) {
        buffer += String(data: data, encoding: .utf8) ?? ""

        while let headerEnd = buffer.range(of: "\r\n\r\n") {
            let header = buffer[buffer.startIndex..<headerEnd.lowerBound]
            buffer = String(buffer[headerEnd.upperBound...])

            guard let lengthStr = header.split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
                  let length = Int(lengthStr),
                  buffer.count >= length else { continue }

            let payload = String(buffer.prefix(length))
            buffer = String(buffer.dropFirst(length))

            guard let payloadData = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
            else { continue }

            // JSON-RPC 2.0: id may be String or Number
            let rawId = json["id"]
            let id: String?
            if let strId = rawId as? String { id = strId }
            else if let numId = rawId as? Int { id = String(numId) }
            else if let numId = rawId as? Int64 { id = String(numId) }
            else { id = nil }

            if let id {
                // This is a response to a prior request
                if let handler = responseHandlers.removeValue(forKey: id) {
                    handler(.success(json))
                }
            } else if let method = json["method"] as? String {
                // This is a server notification (no id)
                handleNotification(method: method, params: json["params"] as? [String: Any] ?? [:])
            }
        }
    }

    /// Handle incoming LSP notifications (e.g. textDocument/publishDiagnostics).
    private func handleNotification(method: String, params: [String: Any]) {
        switch method {
        case "textDocument/publishDiagnostics":
            guard let uri = params["uri"] as? String,
                  let diagnostics = params["diagnostics"] as? [[String: Any]]
            else { return }

            let items: [LSPDiagnosticItem] = diagnostics.compactMap { diag in
                guard let range = diag["range"] as? [String: Any],
                      let start = range["start"] as? [String: Any],
                      let line = start["line"] as? Int,
                      let character = start["character"] as? Int,
                      let message = diag["message"] as? String
                else { return nil }

                let severity = DiagnosticSeverity(rawValue: diag["severity"] as? Int ?? 0) ?? .info
                return LSPDiagnosticItem(
                    file: uri, line: line, column: character,
                    severity: severity, message: message
                )
            }

            // Update stored diagnostics
            currentDiagnostics = items

            // Notify on main thread
            DispatchQueue.main.async { [weak self] in
                self?.onDiagnosticsChanged?(items)
            }

        default:
            break // Unknown notification, ignore
        }
    }

    /// Map LSP SymbolKind integer to a human-readable label.
    private static func symbolKindLabel(_ kind: Int) -> String {
        switch kind {
        case 1:  return "File"
        case 2:  return "Module"
        case 3:  return "Namespace"
        case 4:  return "Package"
        case 5:  return "Class"
        case 6:  return "Method"
        case 7:  return "Property"
        case 8:  return "Field"
        case 9:  return "Constructor"
        case 10: return "Enum"
        case 11: return "Interface"
        case 12: return "Function"
        case 13: return "Variable"
        case 14: return "Constant"
        case 15: return "String"
        case 16: return "Number"
        case 17: return "Boolean"
        case 18: return "Array"
        case 19: return "Object"
        case 20: return "Key"
        case 21: return "Null"
        case 22: return "EnumMember"
        case 23: return "Struct"
        case 24: return "Event"
        case 25: return "Operator"
        case 26: return "TypeParameter"
        default: return "Symbol"
        }
    }
}
