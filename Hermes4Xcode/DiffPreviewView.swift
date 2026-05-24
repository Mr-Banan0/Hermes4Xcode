import SwiftUI

// MARK: - Diff Line Model

struct DiffLine: Identifiable, Equatable {
    let id = UUID()
    let type: DiffLineType
    let content: String
    let lineNumberOld: Int?
    let lineNumberNew: Int?
}

enum DiffLineType: Equatable {
    case addition      // + new line
    case deletion      // - old line
    case context       // unchanged context
    case header        // @@ ... @@
    case fileHeader    // ---/+++
}

// MARK: - Diff Parser

/// Parse a unified diff or plain code block into `[DiffLine]`.
enum DiffParser {
    static func parse(_ text: String) -> [DiffLine] {
        let lines = text.components(separatedBy: .newlines)
        var result: [DiffLine] = []
        var oldLine = 0
        var newLine = 0
        var inDiff = false

        for line in lines {
            if line.hasPrefix("--- ") || line.hasPrefix("+++ ") {
                inDiff = true
                result.append(DiffLine(type: .fileHeader, content: line, lineNumberOld: nil, lineNumberNew: nil))
                continue
            }

            if line.hasPrefix("@@") {
                inDiff = true
                // Parse @@ -oldStart,count +newStart,count @@
                if let match = try? NSRegularExpression(pattern: #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#)
                    .firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    if match.range(at: 1).location != NSNotFound {
                        oldLine = Int(line[Range(match.range(at: 1), in: line)!]) ?? 0
                    }
                    if match.range(at: 2).location != NSNotFound {
                        newLine = Int(line[Range(match.range(at: 2), in: line)!]) ?? 0
                    }
                }
                result.append(DiffLine(type: .header, content: line, lineNumberOld: nil, lineNumberNew: nil))
                continue
            }

            if inDiff {
                if line.hasPrefix("+") {
                    let content = String(line.dropFirst())
                    result.append(DiffLine(type: .addition, content: content, lineNumberOld: nil, lineNumberNew: newLine > 0 ? newLine : nil))
                    if newLine > 0 { newLine += 1 }
                    continue
                } else if line.hasPrefix("-") {
                    let content = String(line.dropFirst())
                    result.append(DiffLine(type: .deletion, content: content, lineNumberOld: oldLine > 0 ? oldLine : nil, lineNumberNew: nil))
                    if oldLine > 0 { oldLine += 1 }
                    continue
                } else if line.hasPrefix(" ") {
                    let content = String(line.dropFirst())
                    result.append(DiffLine(type: .context, content: content, lineNumberOld: oldLine > 0 ? oldLine : nil, lineNumberNew: newLine > 0 ? newLine : nil))
                    if oldLine > 0 { oldLine += 1 }
                    if newLine > 0 { newLine += 1 }
                    continue
                }
            }

            // Plain code (no diff markers)
            result.append(DiffLine(type: .context, content: line, lineNumberOld: nil, lineNumberNew: nil))
        }

        return result
    }
}

// MARK: - Diff Preview View

/// Native diff preview with Apply/Reject controls.
///
/// Supports:
/// - Unified diff format (---/+++/@@ lines)
/// - Plain code blocks (show as-is with monospace styling)
/// - Per-diff Apply/Reject buttons
/// - Apply All / Reject All for batch mode
/// - Accept animation on apply
///
struct DiffPreviewView: View {
    let file: String
    let code: String
    let onApply: (() -> Void)?

    @State private var isApplied = false
    @State private var isRejected = false
    @State private var showFullScreen = false

    private let diffLines: [DiffLine]

    init(file: String, code: String, onApply: (() -> Void)? = nil) {
        self.file = file
        self.code = code
        self.onApply = onApply
        self.diffLines = DiffParser.parse(code)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Image(systemName: isApplied ? "checkmark.circle.fill" : "doc.badge.plus")
                    .font(.caption)
                    .foregroundColor(isApplied ? .green : (isRejected ? .secondary : .hermes))
                Text(file.isEmpty ? "Code Changes" : file)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(isRejected ? .secondary : .white)
                Spacer()

                // Actions
                HStack(spacing: 4) {
                    if !isApplied, !isRejected {
                        Button(action: { showFullScreen = true }) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 8))
                        }
                        .buttonStyle(.plain).foregroundColor(.secondary)
                        .help("Preview full screen")

                        Button(action: reject) {
                            HStack(spacing: 2) {
                                Image(systemName: "xmark").font(.system(size: 8))
                                Text("Reject").font(.system(size: 8, design: .monospaced))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.1)).cornerRadius(3)
                        }
                        .buttonStyle(.plain).foregroundColor(.red.opacity(0.8))

                        if let apply = onApply {
                            Button(action: { applyAction(apply) }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "checkmark").font(.system(size: 8))
                                    Text("Apply").font(.system(size: 8, design: .monospaced))
                                }
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.hermes.opacity(0.15)).cornerRadius(3)
                            }
                            .buttonStyle(.plain).foregroundColor(.hermes)
                        }
                    } else if isApplied {
                        Text("Applied ✓")
                            .font(.system(size: 8, design: .monospaced)).foregroundColor(.green)
                    } else if isRejected {
                        Text("Rejected")
                            .font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary)
                    }
                }
            }

            // Diff content
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(diffLines) { line in
                        DiffLineView(line: line)
                    }
                }
                .padding(8)
                .background(Color(white: 0.06))
                .cornerRadius(6)
            }
        }
        .opacity(isRejected ? 0.5 : 1)
        .sheet(isPresented: $showFullScreen) {
            FullScreenDiffView(
                file: file,
                diffLines: diffLines,
                onApply: onApply.map { apply in { applyAction(apply) } },
                onReject: reject
            )
        }
    }

    private func applyAction(_ apply: @escaping () -> Void) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isApplied = true
        }
        apply()
    }

    private func reject() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isRejected = true
        }
    }
}

// MARK: - Diff Line View

struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            // Line numbers
            if line.lineNumberOld != nil || line.lineNumberNew != nil {
                HStack(spacing: 0) {
                    Text(line.lineNumberOld.map { "\($0)" } ?? " ")
                        .frame(width: 24, alignment: .trailing)
                    Text(" ")
                    Text(line.lineNumberNew.map { "\($0)" } ?? " ")
                        .frame(width: 24, alignment: .trailing)
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(Color(white: 0.35))
                .padding(.trailing, 4)
            }

            // Line marker and content
            HStack(spacing: 0) {
                Text(marker)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(markerColor)
                    .frame(width: 12)
                Text(line.content)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(textColor)
            }
        }
        .padding(.vertical, 1).padding(.horizontal, 2)
        .background(backgroundColor)
    }

    private var marker: String {
        switch line.type {
        case .addition:   return "+"
        case .deletion:   return "-"
        case .header:     return "@"
        case .fileHeader: return " "
        case .context:    return " "
        }
    }

    private var markerColor: Color {
        switch line.type {
        case .addition:   return .green
        case .deletion:   return .red
        case .header:     return Color.hermes
        case .fileHeader: return .blue
        case .context:    return .clear
        }
    }

    private var textColor: Color {
        switch line.type {
        case .addition:   return Color.green.opacity(0.9)
        case .deletion:   return Color.red.opacity(0.9)
        case .header:     return Color.hermes.opacity(0.7)
        case .fileHeader: return Color.blue.opacity(0.7)
        case .context:    return Color(white: 0.75)
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .addition:   return Color.green.opacity(0.06)
        case .deletion:   return Color.red.opacity(0.06)
        case .header:     return Color.hermes.opacity(0.04)
        case .fileHeader: return Color.blue.opacity(0.03)
        case .context:    return .clear
        }
    }
}

// MARK: - Full Screen Diff Preview

struct FullScreenDiffView: View {
    let file: String
    let diffLines: [DiffLine]
    let onApply: (() -> Void)?
    let onReject: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(file.isEmpty ? "Diff Preview" : file)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Spacer()
                if let apply = onApply {
                    Button("Apply") { apply(); onReject?() }
                        .buttonStyle(.plain).foregroundColor(.hermes)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.hermes.opacity(0.15)).cornerRadius(4)
                }
                if let reject = onReject {
                    Button("Reject") { reject() }
                        .buttonStyle(.plain).foregroundColor(.red)
                        .font(.system(size: 10, design: .monospaced))
                }
            }
            .padding()

            Divider()

            // Diff content
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(diffLines) { line in
                        DiffLineView(line: line)
                    }
                }
                .padding()
            }
            .background(Color(white: 0.04))
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(white: 0.08))
    }
}
