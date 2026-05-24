import Combine
import SwiftUI

// MARK: - Agent Manager

final class AgentManager: ObservableObject {
    @Published var tabs: [AgentTab] = []
    @Published var activeTabId = UUID()
    @Published var isStreaming = false
    @Published var currentAssistantText = ""
    @Published var mode: ExecutionMode = .chat
    @Published var pendingAgentName: String?
    @Published var editingProfileTabId: UUID?         // which tab's profile is being edited
    @Published var showProfileEditor = false

    // Streaming flag per tab (not persisted)
    var streamingTabs: Set<UUID> = []
    var streamingTexts: [UUID: String] = [:]

    // Tool call tracking for LiveToolCallBar
    @Published var activeToolCalls: [ToolCallInfo] = []
    private let toolCallPatterns: [(emoji: String, name: String, icon: String)] = [
        ("🛠", "Build", "hammer.fill"),
        ("📖", "Read", "doc.text.magnifyingglass"),
        ("✏️", "Edit", "pencil"),
        ("📝", "Write", "doc.badge.plus"),
        ("🧪", "Test", "checkmark.circle"),
        ("🔍", "Search", "magnifyingglass"),
        ("📂", "Open", "folder"),
        ("🚀", "Run", "play.fill"),
        ("🗑", "Delete", "trash"),
        ("🔧", "Configure", "wrench.fill"),
        ("📄", "Create", "doc.badge.plus"),
        ("♻️", "Refactor", "arrow.triangle.2.circlepath"),
        ("📋", "Plan", "list.clipboard"),
    ]

    private let client = HermesAPIClient()

    init() {
        let welcome = StoredMessage(role: "assistant", text: AgentManager.welcomeText + "\n\nLet's create our app！")
        var defaultTab = AgentTab(id: UUID(), name: "supervisor", template: .supervisor)
        defaultTab.roleDescription = AgentTemplate.supervisor.defaultRole
        defaultTab.systemPrompt = AgentTemplate.supervisor.defaultPrompt
        defaultTab.permissions = AgentTemplate.supervisor.defaultPermissions
        defaultTab.messages = [welcome]
        tabs.append(defaultTab)
        activeTabId = tabs[0].id
    }

    // MARK: - Tab Management

    var activeTab: AgentTab {
        tabs.first(where: { $0.id == activeTabId }) ?? tabs[0]
    }

    var activeIndex: Int {
        tabs.firstIndex(where: { $0.id == activeTabId }) ?? 0
    }

    /// Create a new agent tab from a profile
    @discardableResult
    func createTab(from profile: AgentProfile) -> UUID {
        var tab = AgentTab(id: profile.id, name: profile.name)
        tab.applyProfile(profile)
        tabs.append(tab)
        activeTabId = tab.id
        return tab.id
    }

    /// Create a tab from template (convenience)
    @discardableResult
    func createTab(name: String, template: AgentTemplate = .custom, role: String? = nil, prompt: String? = nil) -> UUID {
        let profile = AgentProfile(
            name: name,
            template: template,
            role: role,
            systemPrompt: prompt
        )
        return createTab(from: profile)
    }

    // Keep the old API for backward compatibility with TabBarView
    @discardableResult
    func createTab(name: String) -> UUID {
        createTab(name: name, template: .custom)
    }

    func removeTab(id: UUID) {
        guard tabs.count > 1 else { return }
        guard let idx = tabs.firstIndex(where: { $0.id == id }),
              tabs[idx].name != "supervisor" else { return }
        let wasActive = id == activeTabId
        tabs.remove(at: idx)
        if wasActive {
            activeTabId = tabs[max(0, min(idx, tabs.count - 1))].id
        }
    }

    func renameTab(id: UUID, name: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].name = name
    }

    func switchToTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }

    // MARK: - Profile Management

    func updateProfile(for tabId: UUID, _ profile: AgentProfile) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[idx].applyProfile(profile)
    }

    func resetProfileToTemplate(for tabId: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        var p = tabs[idx].profile
        p.resetToTemplate()
        tabs[idx].applyProfile(p)
    }

    func openProfileEditor(for tabId: UUID) {
        editingProfileTabId = tabId
        showProfileEditor = true
    }

    // MARK: - Messages

    func appendMessage(_ msg: StoredMessage, to tabId: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[idx].messages.append(msg)
    }

    func clearMessages(for tabId: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[idx].messages.removeAll()
    }

    func updateInput(_ text: String, for tabId: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[idx].inputText = text
    }

    // MARK: - Send Message

    func sendMessage(from tabId: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let text = tabs[idx].inputText
        guard !text.isEmpty else { return }

        tabs[idx].inputText = ""
        let userMsg = StoredMessage(role: "user", text: text)
        tabs[idx].messages.append(userMsg)

        streamingTabs.insert(tabId)
        streamingTexts[tabId] = ""
        isStreaming = true

        // Build history with system prompt prefix
        let tab = tabs[idx]
        var history = [[String: String]]()

        // Inject mode system instruction first (if in plan mode), then agent system prompt
        let modeInstruction = mode.systemInstruction
        let agentPrompt = tab.effectiveSystemMessage
        let combinedPrompt = [modeInstruction, agentPrompt]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if !combinedPrompt.isEmpty {
            history.append(["role": "system", "content": combinedPrompt])
        }

        // Append conversation history
        history += tab.messages.map { ["role": $0.role, "content": $0.text] }

        Task {
            await client.sendMessage(
                text,
                contextCode: nil,
                history: history,
                onDelta: { delta in
                    Task { @MainActor in
                        self.streamingTexts[tabId] = (self.streamingTexts[tabId] ?? "") + delta
                        self.currentAssistantText = self.streamingTexts[tabId] ?? ""
                        self.updateToolCalls(from: self.streamingTexts[tabId] ?? "")
                    }
                },
                onComplete: { result in
                    Task { @MainActor in
                        self.streamingTabs.remove(tabId)
                        self.streamingTexts.removeValue(forKey: tabId)
                        self.isStreaming = !self.streamingTabs.isEmpty
                        switch result {
                        case .success(let full):
                            self.appendMessage(StoredMessage(role: "assistant", text: full), to: tabId)
                            self.checkForAgentCreation(full)
                            self.checkForDelegation(full)
                        case .failure(let err):
                            self.appendMessage(StoredMessage(role: "assistant", text: "Error: \(err.localizedDescription)"), to: tabId)
                        }
                        self.currentAssistantText = ""
                        // Auto-save after each message completes
                        self.autoSave()
                        // Clear tool calls after streaming completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                self.activeToolCalls = []
                            }
                        }
                    }
                },
            )
        }
    }

    // MARK: - Tool Call Tracking

    /// Tabs eligible for forwarding (excludes current tab)
    var eligibleForwardTargets: [AgentTab] {
        tabs.filter { $0.id != activeTabId }
    }

    /// Forward a message from the current tab to another tab
    func forwardMessage(_ message: StoredMessage, to targetTabId: UUID) {
        guard let sourceIdx = tabs.firstIndex(where: { $0.id == activeTabId }),
              let targetIdx = tabs.firstIndex(where: { $0.id == targetTabId })
        else { return }

        let forwarded = StoredMessage(
            role: message.role,
            text: message.text,
            sourceTabId: activeTabId,
            forwardedFromName: tabs[sourceIdx].name
        )
        tabs[targetIdx].messages.append(forwarded)
        activeTabId = targetTabId
        autoSave()
    }

    /// Check if the assistant response contains delegation patterns and auto-route
    func checkForDelegation(_ response: String) {
        let patterns = [
            ("@", ":"),
            ("[delegate to ", "]"),
            ("[route to ", "]"),
            ("[send to ", "]"),
            ("pass this to ", " "),
        ]
        let lower = response.lowercased()
        for (prefix, suffix) in patterns {
            if lower.contains(prefix) {
                // Extract agent name
                if let range = lower.range(of: prefix) {
                    let rest = lower[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    let name = rest.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "," || $0 == "\n" || $0 == ":" || $0 == "]" }).first.map(String.init) ?? ""
                    if !name.isEmpty, name != "supervisor" {
                        // Find or create tab
                        if let existing = tabs.first(where: { $0.name.lowercased() == name }) {
                            let msg = StoredMessage(role: "user", text: "[Delegated from \(tabs.first(where: { $0.id == activeTabId })?.name ?? "unknown")] \(response)")
                            tabs[tabs.firstIndex(where: { $0.id == existing.id })!].messages.append(msg)
                            activeTabId = existing.id
                        } else {
                            // Auto-create the tab
                            let newId = createTab(name: name)
                            let msg = StoredMessage(role: "user", text: "[Delegated from \(tabs.first(where: { $0.id == activeTabId })?.name ?? "unknown")] \(response)")
                            if let idx = tabs.firstIndex(where: { $0.id == newId }) {
                                tabs[idx].messages.append(msg)
                            }
                        }
                        return
                    }
                }
            }
        }
    }

    // MARK: - Tool Call Tracking

    /// Parse streaming text for tool call patterns and update activeToolCalls
    func updateToolCalls(from text: String) {
        var seenNames = Set<String>()
        var updated: [ToolCallInfo] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            for (emoji, name, icon) in toolCallPatterns {
                guard trimmed.hasPrefix(emoji) || trimmed.lowercased().contains(name.lowercased()) else { continue }

                let status: ToolCallStatus2
                if trimmed.contains("✅") || trimmed.contains("✓") || trimmed.contains("succeeded") || trimmed.contains("done") {
                    status = .success
                } else if trimmed.contains("❌") || trimmed.contains("failed") || trimmed.contains("error") {
                    status = .failed
                } else {
                    status = .running
                }

                seenNames.insert(name)
                updated.append(ToolCallInfo(
                    name: name,
                    icon: icon,
                    status: status,
                    detail: String(trimmed.prefix(60))
                ))
                break
            }
        }

        // Preserve completed tool calls that are already in the list
        // but no longer in the latest text (they finished in previous deltas)
        for existing in activeToolCalls {
            if existing.status == .success || existing.status == .failed {
                if !seenNames.contains(existing.name) {
                    updated.append(existing)
                }
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            activeToolCalls = updated
        }
    }

    // MARK: - Agent Self-Creation

    func checkForAgentCreation(_ response: String) {
        let lower = response.lowercased()
        let patterns = [
            "create an agent called ",
            "create a new agent called ",
            "create an agent named ",
            "create a "
        ]
        for pattern in patterns {
            if lower.contains(pattern) {
                if let range = lower.range(of: pattern) {
                    let rest = lower[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    let name = rest.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "," || $0 == "\n" }).first.map(String.init) ?? "stranger"
                    if name != "supervisor" && !tabs.contains(where: { $0.name == name }) {
                        pendingAgentName = name
                        return
                    }
                }
            }
        }
    }

    func confirmCreateAgent() {
        guard let name = pendingAgentName else { return }
        // Create as custom agent — user can specialize later
        createTab(name: name)
        let welcome = StoredMessage(role: "assistant", text: "I'm **\(name)**, a dedicated agent for this task. How can I help?")
        appendMessage(welcome, to: tabs.last?.id ?? activeTabId)
        pendingAgentName = nil
    }

    func cancelCreateAgent() {
        pendingAgentName = nil
    }
}
