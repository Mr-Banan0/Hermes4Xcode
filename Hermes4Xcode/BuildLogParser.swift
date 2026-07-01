import Foundation
import SwiftUI

// MARK: - Build Log Entry

struct BuildLogEntry: Identifiable, Equatable {
    let id = UUID()
    let type: BuildLogEntryType
    let file: String?
    let line: Int?
    let column: Int?
    let message: String
}

enum BuildLogEntryType: Equatable {
    case error
    case warning
    case note
    case success
    case failure
    case info
}

// MARK: - Build Summary

struct BuildSummary: Equatable {
    let succeeded: Bool
    let errorCount: Int
    let warningCount: Int
    let noteCount: Int
    let duration: TimeInterval?
}

// MARK: - Parser

/// Parses xcodebuild raw output into structured entries.
///
/// Handles three parsing modes:
/// 1. **Standard xcodebuild** — `path:line:col: error/warning: message`
/// 2. **Swift compiler notes** — `path:line:col: note: message`
/// 3. **Status lines** — `BUILD SUCCEEDED`, `BUILD FAILED`, `Testing started`
///
enum BuildLogParser {

    /// Regex: /path/file.swift:LINE:COL: error/warning/note: message
    private static let linePattern: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"^(.+?):(\d+):(?::(\d+):)?\s*(error|warning|note):\s*(.+)"#,
            options: []
        )
    }()

    /// Regex: BUILD SUCCEEDED or BUILD FAILED
    private static let statusPattern: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"(BUILD|TEST)\s+(SUCCEEDED|FAILED)"#,
            options: []
        )
    }()

    // Regex: Testing started / passed / failed
    private static let testPattern: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"(Test\s+(passed|failed)|Testing\s+started|\d+ tests?)"#,
            options: [.caseInsensitive]
        )
    }()

    static func parse(_ text: String) -> [BuildLogEntry] {
        var entries: [BuildLogEntry] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Try standard xcodebuild error/warning/note format first
            if let entry = parseLineEntry(trimmed) {
                entries.append(entry)
                continue
            }

            // Try status line
            if let entry = parseStatusEntry(trimmed) {
                entries.append(entry)
                continue
            }

            // Try test line
            if let entry = parseTestEntry(trimmed) {
                entries.append(entry)
                continue
            }

            // Everything else is info
            entries.append(BuildLogEntry(
                type: .info,
                file: nil, line: nil, column: nil,
                message: trimmed
            ))
        }

        return entries
    }

    /// Compute a summary from a list of entries.
    static func summary(from entries: [BuildLogEntry]) -> BuildSummary {
        var errs = 0, warns = 0, notes = 0
        var succeeded = false

        for e in entries {
            switch e.type {
            case .error:    errs += 1
            case .warning:  warns += 1
            case .note:     notes += 1
            case .success:  succeeded = true
            case .failure:  succeeded = false
            case .info:     break
            }
        }

        return BuildSummary(
            succeeded: succeeded,
            errorCount: errs,
            warningCount: warns,
            noteCount: notes,
            duration: nil
        )
    }

    // MARK: - Private Parsers

    private static func parseLineEntry(_ line: String) -> BuildLogEntry? {
        guard let linePattern else { return nil }
        guard let match = linePattern.firstMatch(
            in: line, range: NSRange(line.startIndex..., in: line)
        ) else { return nil }

        let file = match.range(at: 1).location != NSNotFound
            ? String(line[Range(match.range(at: 1), in: line)!]) : nil
        let lineNum = match.range(at: 2).location != NSNotFound
            ? Int(line[Range(match.range(at: 2), in: line)!]) : nil
        let col = match.range(at: 3).location != NSNotFound
            ? Int(line[Range(match.range(at: 3), in: line)!]) : nil
        let rawType = match.range(at: 4).location != NSNotFound
            ? String(line[Range(match.range(at: 4), in: line)!]) : ""
        let msg = match.range(at: 5).location != NSNotFound
            ? String(line[Range(match.range(at: 5), in: line)!]) : line

        let type: BuildLogEntryType = switch rawType {
        case "error":   .error
        case "warning": .warning
        case "note":    .note
        default:        .info
        }

        return BuildLogEntry(type: type, file: file, line: lineNum, column: col, message: msg)
    }

    private static func parseStatusEntry(_ line: String) -> BuildLogEntry? {
        guard let statusPattern else { return nil }
        guard statusPattern.firstMatch(
            in: line, range: NSRange(line.startIndex..., in: line)
        ) != nil else { return nil }

        if line.contains("SUCCEEDED") {
            return BuildLogEntry(type: .success, file: nil, line: nil, column: nil, message: line)
        }
        return BuildLogEntry(type: .failure, file: nil, line: nil, column: nil, message: line)
    }

    private static func parseTestEntry(_ line: String) -> BuildLogEntry? {
        guard let testPattern else { return nil }
        guard testPattern.firstMatch(
            in: line, range: NSRange(line.startIndex..., in: line)
        ) != nil else { return nil }

        // Detect test success vs failure
        let isSuccess = line.contains("passed") || line.contains("succeeded")
        return BuildLogEntry(
            type: isSuccess ? .success : (line.contains("failed") ? .failure : .info),
            file: nil, line: nil, column: nil,
            message: line
        )
    }
}

// MARK: - Color Helper

extension BuildLogEntryType {
    var color: Color {
        switch self {
        case .error:   return .red
        case .warning: return .yellow
        case .note:    return .blue
        case .success: return .green
        case .failure: return .red
        case .info:    return Color(white: 0.5)
        }
    }

    var icon: String {
        switch self {
        case .error:   return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .note:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .info:    return "bubble.left"
        }
    }
}
