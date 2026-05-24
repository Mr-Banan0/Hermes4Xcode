import SwiftUI

// MARK: - Tool Call Model

enum ToolCallStatus2: Equatable {
    case running
    case success
    case failed
}

struct ToolCallInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let icon: String
    let status: ToolCallStatus2
    let detail: String
}

// MARK: - Live Tool Call Bar

/// Real-time tool call visualization bar shown during agent streaming.
///
/// Shows:
/// - Running tool calls with gold pulsing animation
/// - Completed tool calls with green checkmark (fade out)
/// - Failed tool calls with red indicator
/// - Expandable timeline of all tool calls in this session
///
struct LiveToolCallBar: View {
    let toolCalls: [ToolCallInfo]
    let isStreaming: Bool

    @State private var showTimeline = false

    var body: some View {
        VStack(spacing: 0) {
            if !toolCalls.isEmpty {
                Divider().background(Color.hermes.opacity(0.2))

                // Compact bar
                HStack(spacing: 6) {
                    ForEach(Array(toolCalls.prefix(4))) { call in
                        ToolCallPill(call: call)
                    }

                    if toolCalls.count > 4 {
                        Text("+\(toolCalls.count - 4)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isStreaming {
                        HStack(spacing: 2) {
                            Circle().fill(Color.hermes).frame(width: 4, height: 4)
                                .opacity(isStreaming ? 1 : 0)
                            Text("Working")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.hermes)
                        }
                    }

                    if toolCalls.count > 1 {
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showTimeline.toggle() } }) {
                            Image(systemName: showTimeline ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color(white: 0.06))

                // Timeline (expanded)
                if showTimeline {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(toolCalls) { call in
                            HStack(spacing: 6) {
                                Image(systemName: call.icon)
                                    .font(.system(size: 9))
                                    .foregroundColor(statusColor(call.status))
                                    .frame(width: 14)
                                Text(call.name)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white)
                                Text(call.detail)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                statusBadge(call.status)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 3)
                            .background(statusColor(call.status).opacity(0.04))
                        }
                    }
                    .padding(.vertical, 4)
                    .background(Color(white: 0.08))
                }
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func statusColor(_ s: ToolCallStatus2) -> Color {
        switch s {
        case .running: return Color.hermes
        case .success: return .green
        case .failed:  return .red
        }
    }

    @ViewBuilder
    private func statusBadge(_ s: ToolCallStatus2) -> some View {
        switch s {
        case .running:
            HStack(spacing: 2) {
                PulseView()
                Text("running")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.hermes)
            }
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9)).foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 9)).foregroundColor(.red)
        }
    }
}

// MARK: - Tool Call Pill

struct ToolCallPill: View {
    let call: ToolCallInfo

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: call.icon)
                .font(.system(size: 8))
            Text(call.name)
                .font(.system(size: 8, design: .monospaced))
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(backgroundColor)
        .cornerRadius(3)
        .foregroundColor(foregroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(borderColor, lineWidth: 0.5)
        )
    }

    private var backgroundColor: Color {
        switch call.status {
        case .running: return Color.hermes.opacity(0.12)
        case .success: return Color.green.opacity(0.08)
        case .failed:  return Color.red.opacity(0.08)
        }
    }

    private var foregroundColor: Color {
        switch call.status {
        case .running: return Color.hermes
        case .success: return .green
        case .failed:  return .red
        }
    }

    private var borderColor: Color {
        switch call.status {
        case .running: return Color.hermes.opacity(0.3)
        case .success: return Color.green.opacity(0.3)
        case .failed:  return Color.red.opacity(0.3)
        }
    }
}

// MARK: - Pulse Animation

struct PulseView: View {
    @State private var isPulsing = false

    var body: some View {
        Circle().fill(Color.hermes).frame(width: 4, height: 4)
            .opacity(isPulsing ? 0.3 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
