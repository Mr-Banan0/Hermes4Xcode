import SwiftUI

// MARK: - Diagnostic Detail Panel

/// Popover content showing all LSP diagnostics grouped by severity.
struct DiagnosticDetailPanel: View {
    let diagnostics: [LSPDiagnosticItem]

    var errors: [LSPDiagnosticItem] { diagnostics.filter { $0.severity == .error } }
    var warnings: [LSPDiagnosticItem] { diagnostics.filter { $0.severity == .warning } }
    var infos: [LSPDiagnosticItem] { diagnostics.filter { $0.severity == .info || $0.severity == .hint } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with counts
            HStack(spacing: 8) {
                Text("Diagnostics")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                if !errors.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 8)).foregroundColor(.red)
                        Text("\(errors.count)").font(.system(size: 9, design: .monospaced)).foregroundColor(.red)
                    }
                }
                if !warnings.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8)).foregroundColor(.yellow)
                        Text("\(warnings.count)").font(.system(size: 9, design: .monospaced)).foregroundColor(.yellow)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider().background(Color.hermes.opacity(0.2))

            if diagnostics.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16)).foregroundColor(.green)
                    Text("No issues detected")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Errors
                        if !errors.isEmpty {
                            SectionHeader(title: "Errors", count: errors.count, color: .red)
                            ForEach(Array(errors.enumerated()), id: \.offset) { _, item in
                                DiagnosticRow(item: item)
                            }
                        }

                        // Warnings
                        if !warnings.isEmpty {
                            SectionHeader(title: "Warnings", count: warnings.count, color: .yellow)
                            ForEach(Array(warnings.enumerated()), id: \.offset) { _, item in
                                DiagnosticRow(item: item)
                            }
                        }

                        // Infos
                        if !infos.isEmpty {
                            SectionHeader(title: "Info", count: infos.count, color: .blue)
                            ForEach(Array(infos.enumerated()), id: \.offset) { _, item in
                                DiagnosticRow(item: item)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: min(320, CGFloat(diagnostics.count * 36 + 60)))
        .background(Color(white: 0.08))
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text("(\(count))")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(color.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(color.opacity(0.06))
    }
}

// MARK: - Diagnostic Row

private struct DiagnosticRow: View {
    let item: LSPDiagnosticItem

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: item.severity.icon)
                .font(.system(size: 8))
                .foregroundColor(item.severity.color)
                .frame(width: 12, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 1) {
                // Location
                HStack(spacing: 4) {
                    Text(fileName(from: item.file))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(":\(item.lineDisplay)")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                // Message
                Text(item.message)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(white: 0.85))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private func fileName(from uri: String) -> String {
        // file:///path/to/file.swift → file.swift
        if let url = URL(string: uri) {
            return url.lastPathComponent
        }
        return (uri as NSString).lastPathComponent
    }
}
