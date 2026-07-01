import SwiftUI

// MARK: - Agent Status Bar

/// Bottom status bar showing Gateway connectivity, active agent, phase, and tool call counts.
///
/// Layout:
/// ```
/// ● Gateway Online  会话名  │  agent-name · phase  ✓3 ✕1
/// ```
struct AgentStatusBar: View {
    @ObservedObject var manager: AgentManager
    @State private var showDiagnostics = false

    var body: some View {
        HStack(spacing: 6) {
            // Gateway status dot
            HStack(spacing: 4) {
                Circle()
                    .fill(manager.isGatewayOnline ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(manager.isGatewayOnline ? "Gateway Online" : "Gateway Offline")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(manager.isGatewayOnline ? .green : .red)
            }
            .help(manager.isGatewayOnline ? "Hermes Gateway connected" : "Hermes Gateway unreachable on port 8642")

            Divider()
                .frame(height: 12)
                .background(Color.hermes.opacity(0.2))

            // Conversation name
            if let convId = ConversationStore.shared.currentConversationId {
                let title = ConversationStore.shared.summaries
                    .first(where: { $0.id == convId })?.title ?? "Chat"
                Text(title)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 100, alignment: .leading)
            }

            Spacer()

            // LSP diagnostics (errors/warnings from sourcekit-lsp)
            if manager.lspErrorCount > 0 || manager.lspWarningCount > 0 {
                Button(action: { showDiagnostics.toggle() }) {
                    HStack(spacing: 3) {
                        if manager.lspErrorCount > 0 {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 7))
                                .foregroundColor(.red)
                            Text("\(manager.lspErrorCount)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.red)
                        }
                        if manager.lspWarningCount > 0 {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 7))
                                .foregroundColor(.yellow)
                            Text("\(manager.lspWarningCount)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.yellow)
                        }
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDiagnostics, arrowEdge: .bottom) {
                    DiagnosticDetailPanel(diagnostics: manager.lspDiagnostics)
                }
                .help(manager.lspDiagnostics.map { "\($0.lineDisplay): \($0.message)" }.joined(separator: "\n"))
                .padding(.trailing, 4)

                Divider()
                    .frame(height: 12)
                    .background(Color.hermes.opacity(0.2))
            }

            // Active agent name
            if manager.activeTab.name != "supervisor" {
                Text(manager.activeTab.name)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.hermes)
            }

            // Phase indicator (if streaming)
            if manager.streamingPhase != .idle {
                Text("·")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(manager.streamingPhase.label)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(manager.streamingPhase.color)
            }

            // Tool call counts
            if manager.totalToolCallsThisSession > 0 {
                Divider()
                    .frame(height: 12)
                    .background(Color.hermes.opacity(0.2))

                HStack(spacing: 3) {
                    if manager.successfulToolCalls > 0 {
                        Text("✓\(manager.successfulToolCalls)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    if manager.failedToolCalls > 0 {
                        Text("✕\(manager.failedToolCalls)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.red)
                    }
                    if manager.isStreaming {
                        Text("⋯")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.hermes)
                    }
                }
            }

            // Running tool call count badge
            let runningCount = manager.activeToolCalls.filter { $0.status == .running }.count
            if runningCount > 0 {
                Text("running \(runningCount)")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.hermes)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.hermes.opacity(0.12))
                    .cornerRadius(3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .frame(height: 24)
        .background(Color(white: 0.06))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.hermes.opacity(0.15)),
            alignment: .top
        )
    }
}
