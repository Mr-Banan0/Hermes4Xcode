import SwiftUI

// MARK: - Agent Forward Picker

/// Sheet UI to pick a target agent tab for message forwarding.
struct AgentForwardPicker: View {
    let manager: AgentManager?
    let message: StoredMessage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.turn.up.forward")
                    .font(.caption).foregroundColor(.hermes)
                Text("Forward to Agent")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding()

            Divider().background(Color.hermes.opacity(0.2))

            if let mgr = manager {
                let targets = mgr.eligibleForwardTargets
                if targets.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.bubble").font(.title2).foregroundColor(.secondary)
                        Text("No other agents available")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("Create a new agent tab first")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 40)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(targets) { tab in
                                AgentTargetRow(tab: tab) {
                                    mgr.forwardMessage(message, to: tab.id)
                                    dismiss()
                                }
                            }
                        }
                        .padding(8)
                    }
                }
            } else {
                Text("Manager not available")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 40)
            }

            Divider().background(Color.hermes.opacity(0.2))

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                    .font(.system(size: 10, design: .monospaced))
                Spacer()
            }
            .padding()
        }
        .frame(width: 300, height: 350)
        .background(Color(white: 0.08))
    }
}

// MARK: - Agent Target Row

struct AgentTargetRow: View {
    let tab: AgentTab
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Template icon
                Image(systemName: tab.template.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.hermes)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.name)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                    Text(tab.template.label)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.caption2).foregroundColor(.hermes.opacity(0.6))
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.hermes.opacity(0.04))
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
