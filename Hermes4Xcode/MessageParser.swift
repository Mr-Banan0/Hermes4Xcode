import SwiftUI

// MARK: - Structured Message Model

enum MessageSegment: Identifiable {
    case text(String)
    case toolCall(icon: String, name: String, status: ToolCallStatus, detail: String)
    case diff(file: String, code: String)

    var id: String {
        switch self {
        case .text(let t): return "t-\(t.prefix(20))"
        case .toolCall(_, let n, let s, _): return "tc-\(n)-\(s.rawValue)"
        case .diff(let f, _): return "d-\(f)"
        }
    }
}

enum ToolCallStatus: String {
    case pending = "⏳"
    case running = "🔄"
    case success = "✅"
    case failed  = "❌"
}

struct StructuredMessage: Identifiable {
    let id = UUID()
    let role: String
    let segments: [MessageSegment]
    let rawText: String
}

// MARK: - Parser

/// Parser for agent response text, extracting tool calls, code diffs, and segments.
enum MessageParser {
    static func parse(_ text: String) -> [MessageSegment] {
        var segments: [MessageSegment] = []
        let lines = text.components(separatedBy: .newlines)
        var currentText: [String] = []
        var inCodeBlock = false
        var codeLines: [String] = []
        var codeFile = ""

        func flushText() {
            let combined = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !combined.isEmpty {
                segments.append(.text(combined))
            }
            currentText = []
        }

        for line in lines {
            // Code block detection
            if line.hasPrefix("```") && !inCodeBlock {
                flushText()
                inCodeBlock = true
                // Extract filename if present: ```swift:File.swift
                let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if rest.contains(":") {
                    codeFile = String(rest.split(separator: ":").last ?? "")
                } else {
                    codeFile = ""
                }
                continue
            }

            if line.hasPrefix("```") && inCodeBlock {
                inCodeBlock = false
                let code = codeLines.joined(separator: "\n")
                if !code.isEmpty {
                    segments.append(.diff(file: codeFile, code: code))
                }
                codeLines = []
                codeFile = ""
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            // Tool call detection (emojis + keywords at line start)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let tool = parseToolCall(trimmed) {
                flushText()
                segments.append(tool)
                continue
            }

            currentText.append(line)
        }

        flushText()
        return segments
    }

    private static func parseToolCall(_ line: String) -> MessageSegment? {
        // Pattern: emoji + action word + detail
        // Must stay in sync with AgentManager.toolCallPatterns
        let patterns: [(String, String, String)] = [
            ("🛠", "Build", "hammer"),
            ("📖", "Read", "doc.text"),
            ("✏️", "Edit", "pencil"),
            ("📝", "Write", "doc.badge.plus"),
            ("🧪", "Test", "checkmark.circle"),
            ("🔍", "Search", "magnifyingglass"),
            ("📂", "Open", "folder"),
            ("🚀", "Run", "play"),
            ("🗑", "Delete", "trash"),
            ("🔧", "Configure", "wrench"),
            ("📄", "Create", "doc.badge.plus"),
            ("♻️", "Refactor", "arrow.triangle.2.circlepath"),
            ("📋", "Plan", "list.clipboard"),
        ]

        for (emoji, action, icon) in patterns {
            if line.hasPrefix(emoji) || line.lowercased().contains(action.lowercased()) {
                let detail = line
                let status: ToolCallStatus = {
                    if line.contains("✅") || line.contains("✓") || line.contains("done") || line.contains("succeeded") { return .success }
                    if line.contains("❌") || line.contains("failed") || line.contains("error") { return .failed }
                    if line.contains("⏳") || line.contains("...") || line.contains("running") { return .running }
                    return .success
                }()
                return .toolCall(icon: icon, name: action, status: status, detail: detail)
            }
        }
        return nil
    }
}
