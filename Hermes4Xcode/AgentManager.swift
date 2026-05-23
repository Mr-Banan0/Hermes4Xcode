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

    private let client = HermesAPIClient()

    // Welcome message (reconstructed from stored plain text)
    private let welcomeText =
        "██╗  ██╗███████╗██████╗ ███╗   ███╗███████╗███████╗██╗  ██╗ ██████╗ ██████╗ ██████╗ ███████╗\n" +
        "██║  ██║██╔════╝██╔══██╗████╗ ████║██╔════╝██╔════╝╚██╗██╔╝██╔════╝██╔═══██╗██╔══██╗██╔════╝\n" +
        "███████║█████╗  ██████╔╝██╔████╔██║█████╗  ███████╗ ╚███╔╝ ██║     ██║   ██║██║  ██║█████╗\n" +
        "██╔══██║██╔══╝  ██╔══██╗██║╚██╝██║██╔══╝  ╚════██║ ██╔██╗ ██║     ██║   ██║██║  ██║██╔══╝\n" +
        "██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗███████║██╔╝ ██╗╚██████╗╚██████╔╝██████╔╝███████╗\n" +
        "╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝"

    init() {
        let welcome = StoredMessage(role: "assistant", text: welcomeText + "\n\nLet's create our app！")
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
                        case .failure(let err):
                            self.appendMessage(StoredMessage(role: "assistant", text: "Error: \(err.localizedDescription)"), to: tabId)
                        }
                        self.currentAssistantText = ""
                    }
                }
            )
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
