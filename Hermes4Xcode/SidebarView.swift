import SwiftUI

struct SidebarView: View {
    @Binding var selectedPage: AppPage
    @Binding var isCollapsed: Bool
    let onToggleCollapse: () -> Void
    @ObservedObject var agentManager: AgentManager
    @StateObject private var store = ConversationStore.shared

    var body: some View {
        VStack(spacing: 0) {
            // Toggle button
            Button(action: onToggleCollapse) {
                Image(systemName: isCollapsed ? "line.3.horizontal" : "sidebar.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.hermes)
            }
            .buttonStyle(.plain)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .padding(.leading, isCollapsed ? 0 : 12)

            Divider().background(Color.hermes.opacity(0.2))
                .padding(.horizontal, isCollapsed ? 0 : 8)

            if isCollapsed {
                collapsedContent
                    .transition(.opacity)
            } else {
                expandedContent
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color(white: 0.08))
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
    }

    // MARK: - Collapsed: icon only

    private var collapsedContent: some View {
        VStack(spacing: 4) {
            ForEach(AppPage.allCases) { page in
                Image(systemName: page.icon)
                    .font(.system(size: 16))
                    .foregroundColor(selectedPage == page ? .hermes : .gray)
                    .frame(width: 34, height: 34)
                    .background(selectedPage == page ? Color.hermes.opacity(0.15) : Color.clear)
                    .cornerRadius(6)
                    .onTapGesture { selectedPage = page }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Expanded: navigation + conversations

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Navigation items
            ForEach(AppPage.allCases) { page in
                HStack(spacing: 8) {
                    Image(systemName: page.icon)
                        .font(.system(size: 14))
                        .foregroundColor(selectedPage == page ? .hermes : .gray)
                        .frame(width: 20)

                    Text(page.label)
                        .font(.system(size: 11,
                                      weight: selectedPage == page ? .semibold : .regular,
                                      design: .monospaced))
                        .foregroundColor(selectedPage == page ? .hermes : .gray)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(selectedPage == page ? Color.hermes.opacity(0.12) : Color.clear)
                .cornerRadius(6)
                .onTapGesture { selectedPage = page }
                .padding(.horizontal, 6)
                .padding(.top, 2)
            }

            Divider().background(Color.hermes.opacity(0.15))
                .padding(.horizontal, 12).padding(.vertical, 6)

            // Conversations header
            HStack {
                Text("Conversations")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: newConversation) {
                    Image(systemName: "plus")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain).foregroundColor(.hermes)
                .help("New conversation")
            }
            .padding(.horizontal, 14).padding(.bottom, 4)

            // Conversation list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filteredSummaries) { summary in
                        ConversationRow(
                            summary: summary,
                            isActive: summary.id == store.currentConversationId,
                            onSelect: { loadConversation(summary.id) },
                            onDelete: { store.delete(id: summary.id) }
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            Task { @MainActor in await store.refreshSummaries() }
        }
    }

    private var filteredSummaries: [ConversationSummary] {
        store.searchQuery.isEmpty ? store.summaries : store.search(store.searchQuery)
    }

    private func loadConversation(_ id: UUID) {
        guard let conv = store.load(id: id) else { return }
        agentManager.restore(from: conv)
        agentManager.hasNamedConversation = true  // Already named, skip auto-naming
        selectedPage = .chat
    }

    private func newConversation() {
        agentManager.tabs = []
        agentManager.activeTabId = UUID()
        agentManager.hasNamedConversation = false
        // Re-init with fresh supervisor tab
        let welcome = StoredMessage(role: "assistant", text: AgentManager.welcomeText + "\n\nLet's create our app！")
        var defaultTab = AgentTab(id: UUID(), name: "supervisor", template: .supervisor)
        defaultTab.roleDescription = AgentTemplate.supervisor.defaultRole
        defaultTab.systemPrompt = AgentTemplate.supervisor.defaultPrompt
        defaultTab.permissions = AgentTemplate.supervisor.defaultPermissions
        defaultTab.messages = [welcome]
        agentManager.tabs.append(defaultTab)
        agentManager.activeTabId = agentManager.tabs[0].id
        store.currentConversationId = UUID()
        selectedPage = .chat
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let summary: ConversationSummary
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 9))
                .foregroundColor(isActive ? .hermes : .gray)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(summary.title)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(isActive ? .hermes : Color(white: 0.7))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(summary.updatedAt, style: .relative)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("· \(summary.messageCount) msgs")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(isActive ? Color.hermes.opacity(0.08) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }
}

// MARK: - Welcome Text (moved to static property)

extension AgentManager {
    static let welcomeText =
        "██╗  ██╗███████╗██████╗ ███╗   ███╗███████╗███████╗██╗  ██╗ ██████╗ ██████╗ ██████╗ ███████╗\n" +
        "██║  ██║██╔════╝██╔══██╗████╗ ████║██╔════╝██╔════╝╚██╗██╔╝██╔════╝██╔═══██╗██╔══██╗██╔════╝\n" +
        "███████║█████╗  ██████╔╝██╔████╔██║█████╗  ███████╗ ╚███╔╝ ██║     ██║   ██║██║  ██║█████╗\n" +
        "██╔══██║██╔══╝  ██╔══██╗██║╚██╝██║██╔══╝  ╚════██║ ██╔██╗ ██║     ██║   ██║██║  ██║██╔══╝\n" +
        "██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗███████║██╔╝ ██╗╚██████╗╚██████╔╝██████╔╝███████╗\n" +
        "╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝"
}
