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
    var status: ToolCallStatus2
    var detail: String
    let startedAt: Date
    var completedAt: Date?

    /// Duration in seconds if completed, or elapsed time if still running
    var duration: TimeInterval? {
        if let completed = completedAt {
            return completed.timeIntervalSince(startedAt)
        }
        return Date().timeIntervalSince(startedAt)
    }

    static func == (lhs: ToolCallInfo, rhs: ToolCallInfo) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }
}

// MARK: - Live Tool Call Bar

/// Real-time tool call visualization bar shown during agent streaming.
struct LiveToolCallBar: View {
    let toolCalls: [ToolCallInfo]
    let isStreaming: Bool

    @State private var showTimeline = false
    @State private var now = Date()

    /// Timer to refresh elapsed time display every second
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var runningCount: Int { toolCalls.filter { $0.status == .running }.count }
    var successCount: Int { toolCalls.filter { $0.status == .success }.count }
    var failedCount: Int { toolCalls.filter { $0.status == .failed }.count }

    var body: some View {
        VStack(spacing: 0) {
            if !toolCalls.isEmpty {
                Divider().background(Color.hermes.opacity(0.2))

                // Compact bar
                HStack(spacing: 6) {
                    // Session badge
                    Text("\(runningCount > 0 ? "▶\(runningCount) " : "")✅\(successCount)❌\(failedCount)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)

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
                                    .lineLimit(2)
                                    .frame(maxWidth: 160, alignment: .leading)
                                Spacer()
                                // Duration badge
                                if let d = call.duration, call.status != .running {
                                    Text(String(format: "%.1fs", d))
                                        .font(.system(size: 7, design: .monospaced))
                                        .foregroundColor(.green)
                                }
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
        .onReceive(timer) { _ in
            // Tick to refresh elapsed time display
            now = Date()
            _ = now  // silence warning — triggers view refresh via @State
        }
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
            if let d = call.duration, call.status == .running {
                Text(String(format: "%.0fs", d))
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.hermes.opacity(0.7))
            }
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
