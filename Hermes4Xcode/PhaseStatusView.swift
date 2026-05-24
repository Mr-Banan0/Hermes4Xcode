import SwiftUI

// MARK: - Streaming Phase

enum StreamingPhase: Equatable {
    case idle
    case thinking
    case analyzing
    case reading
    case planning
    case building
    case testing
    case writing
    case searching
    case responding

    var label: String {
        switch self {
        case .idle:       return ""
        case .thinking:   return "Thinking"
        case .analyzing:  return "Analyzing"
        case .reading:    return "Reading"
        case .planning:   return "Planning"
        case .building:   return "Building"
        case .testing:    return "Testing"
        case .writing:    return "Writing code"
        case .searching:  return "Searching"
        case .responding: return "Generating response"
        }
    }

    var icon: String {
        switch self {
        case .idle:       return ""
        case .thinking:   return "brain.head.profile"
        case .analyzing:  return "magnifyingglass.circle"
        case .reading:    return "book.fill"
        case .planning:   return "list.clipboard"
        case .building:   return "hammer.fill"
        case .testing:    return "checkmark.seal.fill"
        case .writing:    return "pencil.and.outline"
        case .searching:  return "doc.text.magnifyingglass"
        case .responding: return "bubble.left.and.bubble.right"
        }
    }

    var color: Color {
        switch self {
        case .idle:       return .clear
        case .thinking:   return .hermes
        case .analyzing:  return .blue
        case .reading:    return .cyan
        case .planning:   return .orange
        case .building:   return .purple
        case .testing:    return .green
        case .writing:    return .hermesAmber
        case .searching:  return .teal
        case .responding: return .hermes
        }
    }
}

// MARK: - Phase Result

enum PhaseResultStatus: Equatable {
    case inProgress
    case success
    case failure
}

struct PhaseResult: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let status: PhaseResultStatus
}

// MARK: - Phase Status Pill

/// Compact status indicator shown during streaming above messages.
struct PhaseStatusPill: View {
    let phase: StreamingPhase
    let isStreaming: Bool

    var body: some View {
        HStack(spacing: 5) {
            if phase != .idle, isStreaming {
                Image(systemName: phase.icon)
                    .font(.system(size: 9))
                    .foregroundColor(phase.color)
                Text(phase.label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(phase.color)
                if phase == .thinking {
                    PhaseDots()
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(phase.color.opacity(0.08))
        .cornerRadius(4)
    }
}

// MARK: - Phase Dots

struct PhaseDots: View {
    @State private var count = 0

    var body: some View {
        Text(String(repeating: ".", count: count))
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.hermes.opacity(0.6))
            .frame(width: 16, alignment: .leading)
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                    count = (count + 1) % 4
                }
            }
    }
}

// MARK: - Phase Result Box

/// Structured result box shown after a phase completes.
/// Rendered inside the chat stream between phase transitions.
struct PhaseResultBox: View {
    let result: PhaseResult

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: result.icon)
                .font(.system(size: 10))
                .foregroundColor(statusColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(statusColor)
                Text(result.detail)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(Color(white: 0.6))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(statusColor.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(statusColor.opacity(0.2), lineWidth: 0.5)
        )
        .cornerRadius(6)
        .padding(.leading, 14)
    }

    private var statusColor: Color {
        switch result.status {
        case .inProgress: return .hermes
        case .success:    return .green
        case .failure:    return .red
        }
    }
}
