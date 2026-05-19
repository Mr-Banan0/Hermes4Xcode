import SwiftUI
import Combine

// MARK: - Agent Manager

final class AgentManager: ObservableObject {
    @Published var tabs: [AgentTab] = []
    @Published var activeTabId: UUID = UUID()
    @Published var isStreaming = false
    @Published var currentAssistantText = ""
    @Published var pendingAgentName: String?

    // Streaming flag per tab (not persisted)
    var streamingTabs: Set<UUID> = []
    var streamingTexts: [UUID: String] = [:]

    private let storageKey = "Hermes4Xcode_agentTabs"
    private let client = HermesAPIClient()

    // Welcome message (reconstructed from stored plain text)
    private let welcomeText =
        "██╗  ██╗███████╗██████╗ ███╗   ███╗███████╗███████╗██╗  ██╗ ██████╗ ██████╗ ██████╗ ███████╗\n" +
        "██║  ██║██╔════╝██╔══██╗████╗ ████║██╔════╝██╔════╝╚██╗██╔╝██╔════╝██╔═══██╗██╔══██╗██╔════╝\n" +
        "███████║█████╗  ██████╔╝██╔████╔██║█████╗  ███████╗ ╚███╔╝ ██║     ██║   ██║██║  ██║█████╗\n" +
        "██╔══██║██╔══╝  ██╔══██╗██║╚██╔╝██║██╔══╝  ╚════██║ ██╔██╗ ██║     ██║   ██║██║  ██║██╔══╝\n" +
        "██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗███████║██╔╝ ██╗╚██████╗╚██████╔╝██████╔╝███████╗\n" +
        "╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝"

    init() {
        load()
        if tabs.isEmpty {
            let welcome = StoredMessage(role: "assistant", text: welcomeText + "\n\nSelect code in Xcode, then chat with me below.")
            var defaultTab = AgentTab(id: UUID(), name: "supervisor")
            defaultTab.messages = [welcome]
            tabs.append(defaultTab)
            activeTabId = tabs[0].id
            save()
        }
    }

    // MARK: - Tab Management

    var activeTab: AgentTab {
        tabs.first(where: { $0.id == activeTabId }) ?? tabs[0]
    }

    var activeIndex: Int {
        tabs.firstIndex(where: { $0.id == activeTabId }) ?? 0
    }

    func createTab(name: String) -> UUID {
        let tab = AgentTab(id: UUID(), name: name)
        tabs.append(tab)
        activeTabId = tab.id
        save()
        return tab.id
    }

    func removeTab(id: UUID) {
        guard tabs.count > 1 else { return }
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            let wasActive = id == activeTabId
            tabs.remove(at: idx)
            if wasActive {
                activeTabId = tabs[max(0, min(idx, tabs.count - 1))].id
            }
            save()
        }
    }

    func renameTab(id: UUID, name: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        var tab = tabs[idx]
        tab.name = name
        tabs[idx] = tab
        save()
    }

    func switchToTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }

    // MARK: - Messages

    func appendMessage(_ msg: StoredMessage, to tabId: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[idx].messages.append(msg)
        save()
    }

    func clearMessages(for tabId: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[idx].messages.removeAll()
        save()
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

        let history = tabs[idx].messages.map { ["role": $0.role, "content": $0.text] }

        Task {
            await client.sendMessage(
                text, contextCode: nil, history: history,
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
        // Pattern: "create an agent called X" / "create a X agent"
        let patterns = [
            "create an agent called ",
            "create a new agent called ",
            "create an agent named ",
            "create a ",
        ]
        for pattern in patterns {
            if lower.contains(pattern) {
                // Extract the name after the pattern
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
        _ = createTab(name: name)
        let welcome = StoredMessage(role: "assistant", text: "I'm **\(name)**, a dedicated agent for this task. How can I help?")
        appendMessage(welcome, to: tabs.last?.id ?? activeTabId)
        pendingAgentName = nil
    }

    func cancelCreateAgent() {
        pendingAgentName = nil
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(tabs) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AgentTab].self, from: data) else { return }
        tabs = decoded
        if !tabs.isEmpty { activeTabId = tabs[0].id }
    }
}
