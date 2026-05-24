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
    @Published var streamingPhase: StreamingPhase = .idle
    @Published var phaseResults: [PhaseResult] = []

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
        let welcome = StoredMessage(role: "assistant", text: AgentManager.welcomeText + "\n\nI'm your **Supervisor**. I'll coordinate the team for you today.\n\n**Your Dev Team:**\n🎯 Product Manager — requirements & specs\n🎨 UI Designer — interface & HIG\n🔨 Developer — implementation\n🐜 QA Engineer — testing & quality\n👑 Tech Lead — architecture & review\n📄 Documenter — docs & notes\n\nWhat are we building today?")

        // Supervisor (default active tab)
        var supervisor = AgentTab(id: UUID(), name: "supervisor", template: .supervisor)
        supervisor.roleDescription = AgentTemplate.supervisor.defaultRole
        supervisor.systemPrompt = AgentTemplate.supervisor.defaultPrompt
        supervisor.permissions = AgentTemplate.supervisor.defaultPermissions
        supervisor.messages = [welcome]
        tabs.append(supervisor)

        // Dev Team
        let team: [(String, AgentTemplate)] = [
            ("product-manager", .productManager),
            ("ui-designer", .uiDesigner),
            ("developer", .developer),
            ("qa-engineer", .qaEngineer),
            ("tech-lead", .techLead),
            ("documenter", .documenter),
        ]
        for (name, template) in team {
            let profile = AgentProfile(name: name, template: template)
            var tab = AgentTab(name: name, template: template)
            tab.applyProfile(profile)
            tabs.append(tab)
        }

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

        // Ensure a fresh conversation ID for new conversations
        if ConversationStore.shared.currentConversationId == nil {
            ConversationStore.shared.currentConversationId = UUID()
        }

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
            let tabModel = tabs[idx].model.isEmpty ? "hermes-agent" : tabs[idx].model
            await client.sendMessage(
                text,
                contextCode: nil,
                history: history,
                model: tabModel,
                onDelta: { delta in
                    Task { @MainActor in
                        self.streamingTexts[tabId] = (self.streamingTexts[tabId] ?? "") + delta
                        self.currentAssistantText = self.streamingTexts[tabId] ?? ""
                        self.updateToolCalls(from: self.streamingTexts[tabId] ?? "")
                        self.updatePhase(from: self.streamingTexts[tabId] ?? "")
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
                            self.detectAndNameConversation(from: full, userText: text)
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

    // MARK: - Phase Tracking

    /// Update streaming phase based on accumulated streaming text
    func updatePhase(from text: String) {
        guard !text.isEmpty else {
            streamingPhase = .thinking
            return
        }

        let lower = text.lowercased()
        let last100 = String(lower.suffix(100))

        if last100.contains("build") || last100.contains("compil") || last100.contains("xcodebuild") {
            streamingPhase = .building
        } else if last100.contains("read") || last100.contains("check") || last100.contains("look") || last100.contains("open") {
            streamingPhase = .reading
        } else if last100.contains("plan") || last100.contains("first") || last100.contains("step") || last100.contains("will do") {
            streamingPhase = .planning
        } else if last100.contains("creat") || last100.contains("write") || last100.contains("implement") || last100.contains("add ") {
            streamingPhase = .writing
        } else if last100.contains("analyz") || last100.contains("structur") || last100.contains("architectur") || last100.contains("understand") {
            streamingPhase = .analyzing
        } else if last100.contains("test") || last100.contains("run") {
            streamingPhase = .testing
        } else if last100.contains("search") || last100.contains("find") || last100.contains("locate") {
            streamingPhase = .searching
        } else {
            streamingPhase = .responding
        }
    }

    /// Add a structured result to the phase results list
    func addPhaseResult(icon: String, title: String, detail: String, status: PhaseResultStatus) {
        let result = PhaseResult(icon: icon, title: title, detail: detail, status: status)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.phaseResults.append(result)
                if self.phaseResults.count > 5 {
                    self.phaseResults.removeFirst()
                }
            }
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

    /// Check if the assistant response contains explicit delegation patterns and auto-route.
    /// Only triggers on explicit patterns like `@existingAgent:` or `[delegate to agent]`.
    /// Does NOT auto-create tabs — only routes to existing ones.
    func checkForDelegation(_ response: String) {
        // Only match explicit bracket patterns — @ mentions must match existing tabs
        let lower = response.lowercased()

        // Pattern 1: [delegate to name] / [route to name] / [send to name]
        let bracketPatterns = ["[delegate to ", "[route to ", "[send to "]
        for prefix in bracketPatterns {
            if let range = lower.range(of: prefix) {
                let rest = lower[range.upperBound...].trimmingCharacters(in: .whitespaces)
                let name = rest.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "]" }).first.map(String.init) ?? ""
                if let existing = tabs.first(where: { $0.name.lowercased() == name }), existing.id != activeTabId {
                    let sourceName = tabs.first(where: { $0.id == activeTabId })?.name ?? "unknown"
                    let msg = StoredMessage(role: "user", text: "[Delegated from \(sourceName)] \(response)")
                    if let idx = tabs.firstIndex(where: { $0.id == existing.id }) {
                        tabs[idx].messages.append(msg)
                    }
                    activeTabId = existing.id
                    autoSave()
                    return
                }
            }
        }

        // Pattern 2: @existingAgentName: — only routes to tabs that already exist
        for tab in tabs where tab.id != activeTabId {
            let mention = "@\(tab.name.lowercased()):"
            if lower.contains(mention) {
                let sourceName = tabs.first(where: { $0.id == activeTabId })?.name ?? "unknown"
                let msg = StoredMessage(role: "user", text: "[Delegated from \(sourceName)] \(response)")
                if let idx = tabs.firstIndex(where: { $0.id == tab.id }) {
                    tabs[idx].messages.append(msg)
                }
                activeTabId = tab.id
                autoSave()
                return
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

    // MARK: - Conversation Naming

    /// Detect the app/project name from conversation and auto-name the conversation.
    /// Only runs once — skips if conversation already has a non-default title.
    var hasNamedConversation = false

    func detectAndNameConversation(from response: String, userText: String) {
        guard !hasNamedConversation else { return }
        // Check if current title is still the default date-based title
        let store = ConversationStore.shared
        let currentTitle = store.summaries.first(where: { $0.id == store.currentConversationId })?.title ?? ""

        // Patterns in user message: "build/create/develop an/the X app"
        let patterns = [
            "(?:build|create|develop|make|start|work\\s+on)\\s+(?:a|an|the|my|new)?\\s*(\\w+(?:\\s+\\w+)?)\\s*(?:app|project|application)",
            "(?:app|project)\\s+(?:called|named)\\s+(\\w+)",
        ]

        let combined = "\(userText.lowercased()) \(response.lowercased())"
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)),
               match.range(at: 1).location != NSNotFound {
                let name = String(combined[Range(match.range(at: 1), in: combined)!])
                    .trimmingCharacters(in: .whitespaces)
                    .capitalized
                if !name.isEmpty, name.count < 40 {
                    updateConversationTitle(name)
                    hasNamedConversation = true
                    return
                }
            }
        }
    }

    private func updateConversationTitle(_ title: String) {
        let store = ConversationStore.shared
        guard let convId = store.currentConversationId else { return }
        // Update the saved file
        if var conv = store.load(id: convId) {
            conv.title = title
            conv.updatedAt = Date()
            store.save(conversation: conv)
        }
        // Refresh sidebar
        Task { @MainActor in await store.refreshSummaries() }
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
