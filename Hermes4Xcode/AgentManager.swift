import Combine
import SwiftUI

// MARK: - Build Result Model

/// Captures the outcome of an async xcodebuild run for LLM context injection.
struct BuildResult: Codable {
    let exitCode: Int32
    let output: String
    let timestamp: Date
    let duration: TimeInterval

    var isSuccess: Bool { exitCode == 0 }

    var summary: String {
        let status = isSuccess ? "✅ Succeeded" : "❌ Failed (exit code \(exitCode))"
        return "Build \(status) in \(String(format: "%.1f", duration))s"
    }

    var contextBlock: String {
        """
        [Build Result — \(summary)]
        ```
        \(output.isEmpty ? "(no output)" : String(output.suffix(2000)))
        ```
        """
    }
}

/// Tracks multi-agent workflow progression.
enum WorkflowPhase: String, Codable {
    case idle
    case planning         // Supervisor analyzing request
    case delegated        // Supervisor → Developer
    case implementing     // Developer working
    case reviewing        // Developer → Reviewer
    case documenting      // Reviewer → Documenter
    case verifying        // Developer re-checking after review
    case complete
}

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
    /// Reasoning/thinking content streamed from the model (e.g. DeepSeek reasoning)
    var streamingReasoningTexts: [UUID: String] = [:]

    // Tool call tracking for LiveToolCallBar
    @Published var activeToolCalls: [ToolCallInfo] = []
    /// Persisted tool calls from the current message session (kept after streaming ends)
    @Published var toolCallHistory: [ToolCallInfo] = []
    @Published var streamingPhase: StreamingPhase = .idle
    @Published var phaseResults: [PhaseResult] = []

    /// Gateway connection status for status bar
    @Published var isGatewayOnline = false
    /// Summary counts for status bar
    @Published var totalToolCallsThisSession = 0
    @Published var successfulToolCalls = 0
    @Published var failedToolCalls = 0

    /// LSP diagnostics summary for status bar
    @Published var lspErrorCount = 0
    @Published var lspWarningCount = 0
    @Published var lspDiagnostics: [LSPDiagnosticItem] = []

    /// Per-tab build result cache — injected into next message history
    var lastBuildResults: [UUID: BuildResult] = [:]
    /// Per-tab workflow phase tracking for auto-progression
    var workflowPhases: [UUID: WorkflowPhase] = [:]

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

    private var healthPollTimer: Timer?

    init() {
        let defaultTabs = Self.makeDefaultTabs()
        tabs = defaultTabs
        activeTabId = defaultTabs[0].id
        startHealthPolling()
        // Wire up LSP diagnostic updates to @Published properties
        SourceKitLSPClient.shared.onDiagnosticsChanged = { [weak self] items in
            DispatchQueue.main.async {
                self?.lspDiagnostics = items
                self?.lspErrorCount = items.filter { $0.severity == .error }.count
                self?.lspWarningCount = items.filter { $0.severity == .warning }.count
            }
        }

        // Wire up build result tracking from XcodeContextProvider
        XcodeContextProvider.shared.onBuildComplete = { [weak self] exitCode, output in
            guard let self else { return }
            // Store the result for the active tab so it's injected into next history
            let result = BuildResult(
                exitCode: exitCode,
                output: output,
                timestamp: Date(),
                duration: 0  // exact duration tracked inside provider
            )
            self.lastBuildResults[self.activeTabId] = result
            if result.isSuccess {
                self.addPhaseResult(icon: "🛠", title: "Build", detail: "Succeeded", status: .success)
            } else {
                self.addPhaseResult(icon: "🛠", title: "Build", detail: "Failed (exit \(exitCode))", status: .failure)
            }
        }
    }

    deinit {
        healthPollTimer?.invalidate()
    }

    /// Create the default team of agent tabs (Supervisor + Dev Team).
    static func makeDefaultTabs() -> [AgentTab] {
        let welcome = StoredMessage(role: "assistant", text: "👋 Welcome to **Hermes4Xcode**! I coordinate the team.\n\n**Your Team:**\n👓 Reviewer — review, design, QA, specs & architecture\n🔨 Developer — implementation\n📄 Documenter — docs & notes\n\n**Agent Protocol:**\n- `[delegate to developer]` or `@developer:` — route a task\n- `[report back]` or `[report to supervisor]` — return results\n- `[report to reviewer]` — send for review\n\nWhat are we building today?")

        // Supervisor (default active tab)
        var supervisor = AgentTab(id: UUID(), name: "supervisor", template: .supervisor)
        supervisor.roleDescription = AgentTemplate.supervisor.defaultRole
        supervisor.systemPrompt = AgentTemplate.supervisor.defaultPrompt
        supervisor.permissions = AgentTemplate.supervisor.defaultPermissions
        supervisor.messages = [welcome]

        var tabs = [supervisor]

        // Dev Team
        let team: [(String, AgentTemplate)] = [
            ("reviewer", .reviewer),
            ("developer", .developer),
            ("documenter", .documenter),
        ]
        for (name, template) in team {
            let profile = AgentProfile(name: name, template: template)
            var tab = AgentTab(name: name, template: template)
            tab.applyProfile(profile)
            tabs.append(tab)
        }

        return tabs
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
        streamingReasoningTexts[tabId] = ""
        isStreaming = true
        // Reset tool call tracking for new message
        activeToolCalls = []
        toolCallHistory = []
        phaseResults = []

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

        // Inject last build result if available and relevant
        if let buildResult = lastBuildResults[tabId], !buildResult.output.isEmpty {
            history.append(["role": "system", "content": buildResult.contextBlock])
        }

        // Inject current workflow phase as system context
        if let phase = workflowPhases[tabId], phase != .idle {
            history.append(["role": "system", "content": "[Current Workflow Phase: \(phase.rawValue)]"])
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
                onReasoningDelta: { reasoning in
                    Task { @MainActor in
                        self.streamingReasoningTexts[tabId] = (self.streamingReasoningTexts[tabId] ?? "") + reasoning
                        // Show reasoning content by making it the "visible" text during thinking
                        if (self.streamingTexts[tabId] ?? "").isEmpty {
                            self.currentAssistantText = self.streamingReasoningTexts[tabId] ?? ""
                        }
                        self.streamingPhase = .thinking
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
                            self.checkForReportBack(full, from: tabId)
                            self.detectAndNameConversation(from: full, userText: text)
                        case .failure(let err):
                            self.appendMessage(StoredMessage(role: "assistant", text: "Error: \(err.localizedDescription)"), to: tabId)
                        }
                        self.currentAssistantText = ""
                        // Auto-save after each message completes
                        self.autoSave()
                    }
                },
            )
        }
    }

    // MARK: - Phase Tracking

    /// Update streaming phase based on accumulated streaming text.
    /// Uses word-boundary regex on the last non-empty line to avoid false matches
    /// on adjacent words (e.g. "understand buildings" should not trigger "build" phase).
    func updatePhase(from text: String) {
        guard !text.isEmpty else {
            streamingPhase = .thinking
            return
        }

        // Get the last non-empty line — phase is driven by what the LLM is saying right now
        let lines = text.components(separatedBy: .newlines)
        let lastLine = lines.reversed().first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let lower = lastLine.lowercased()

        if lower.range(of: #"\b(build(ing|s)?|compil(e|ing|ation)|xcodebuild)\b"#, options: .regularExpression) != nil {
            streamingPhase = .building
        } else if lower.range(of: #"\b(read(ing)?|check(ing|ed)?|look(ing|ed)?|open(ing|ed)?)\b"#, options: .regularExpression) != nil {
            streamingPhase = .reading
        } else if lower.range(of: #"\b(plan(ning|s)?|first|step(s)?|will do)\b"#, options: .regularExpression) != nil {
            streamingPhase = .planning
        } else if lower.range(of: #"\b(creat(e|ing)|writ(e|ing|es?)|implement(ing|ation)?|add(ing|ed)?)\b"#, options: .regularExpression) != nil {
            streamingPhase = .writing
        } else if lower.range(of: #"\b(analyz(e|ing)|structur(e|ing)|architectur(e|ing)|understand(ing)?)\b"#, options: .regularExpression) != nil {
            streamingPhase = .analyzing
        } else if lower.range(of: #"\b(test(ing|s)?|run(ning)?)\b"#, options: .regularExpression) != nil {
            streamingPhase = .testing
        } else if lower.range(of: #"\b(search(ing|ed)?|find(ing)?|locat(e|ing))\b"#, options: .regularExpression) != nil {
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
                    workflowPhases[existing.id] = .implementing
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
                workflowPhases[tab.id] = tab.name == "developer" ? .implementing :
                                        tab.name == "reviewer" ? .reviewing : .idle
                autoSave()
                return
            }
        }
    }

    // MARK: - Report Back Protocol

    /// Detect `[Report to supervisor]` or `[Report back]` in the response
    /// and route the message back to the original delegator (or supervisor as default).
    func checkForReportBack(_ response: String, from tabId: UUID) {
        let lower = response.lowercased()
        let reportPatterns = ["[report to ", "[report back"]

        // Determine target: `[report to reviewer]` or just `[report back]` → supervisor
        var targetName = "supervisor"
        for pattern in ["[report to ", "[report back to " ] {
            if let range = lower.range(of: pattern) {
                let rest = lower[range.upperBound...].trimmingCharacters(in: .whitespaces)
                let name = rest.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "]" }).first.map(String.init) ?? ""
                if !name.isEmpty {
                    targetName = name
                }
                break
            }
        }

        // Only proceed if `[report` pattern is actually present
        let isReport = reportPatterns.contains { lower.contains($0) }
        guard isReport else { return }

        guard let sourceTab = tabs.first(where: { $0.id == tabId }),
              let targetTab = tabs.first(where: { $0.name.lowercased() == targetName }),
              targetTab.id != tabId else { return }

        // Wrap the response as a report message to the target
        let reportHeader = "[Report from \(sourceTab.name)] "
        let msg = StoredMessage(
            role: "user",
            text: reportHeader + response,
            sourceTabId: tabId,
            forwardedFromName: sourceTab.name
        )
        if let idx = tabs.firstIndex(where: { $0.id == targetTab.id }) {
            tabs[idx].messages.append(msg)
        }
        activeTabId = targetTab.id

        // Auto-advance workflow phase
        switch sourceTab.name {
        case "developer":
            workflowPhases[targetTab.id] = .reviewing
        case "reviewer":
            workflowPhases[targetTab.id] = .verifying
        case "documenter":
            workflowPhases[targetTab.id] = .complete
        default:
            workflowPhases[targetTab.id] = .idle
        }

        autoSave()
    }

    // MARK: - Tool Call Tracking

    /// Parse streaming text for tool call patterns and update activeToolCalls.
    /// Preserves startedAt timestamps from previous iterations.
    func updateToolCalls(from text: String) {
        var seenNames = Set<String>()
        var updated: [ToolCallInfo] = []
        let lines = text.components(separatedBy: .newlines)

        // Build a lookup of existing calls by name for timestamp preservation
        let existingByName = activeToolCalls.reduce(into: [String: ToolCallInfo]()) { result, call in
            result[call.name] = call
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            for (emoji, name, icon) in toolCallPatterns {
                guard trimmed.hasPrefix(emoji) || trimmed.lowercased().contains(name.lowercased()) else { continue }

                let isCompleted = trimmed.contains("✅") || trimmed.contains("✓") || trimmed.contains("succeeded") || trimmed.contains("done")
                let isFailed = trimmed.contains("❌") || trimmed.contains("failed") || trimmed.contains("error")

                let status: ToolCallStatus2
                if isFailed { status = .failed }
                else if isCompleted { status = .success }
                else { status = .running }

                // Preserve startedAt from previous iteration; set completedAt on completion
                let startedAt = existingByName[name]?.startedAt ?? Date()
                let completedAt = existingByName[name]?.completedAt ?? (status != .running ? Date() : nil)

                seenNames.insert(name)
                updated.append(ToolCallInfo(
                    name: name,
                    icon: icon,
                    status: status,
                    detail: trimmed,
                    startedAt: startedAt,
                    completedAt: completedAt
                ))
                break
            }
        }

        // Preserve completed/failed calls that are already in the list but no longer in latest text
        for existing in activeToolCalls {
            if existing.status == .success || existing.status == .failed {
                if !seenNames.contains(existing.name) {
                    updated.append(existing)
                }
            }
        }

        // Detect newly completed calls and append to history
        let oldStatuses = activeToolCalls.reduce(into: [String: ToolCallStatus2]()) { result, call in
            result[call.name] = call.status
        }
        for call in updated {
            let oldStatus = oldStatuses[call.name]
            if oldStatus == .running && (call.status == .success || call.status == .failed) {
                toolCallHistory.append(call)
                if toolCallHistory.count > 50 {
                    toolCallHistory.removeFirst()
                }
            }
        }

        // Update summary counts for status bar
        totalToolCallsThisSession = updated.count
        successfulToolCalls = updated.filter { $0.status == .success }.count
        failedToolCalls = updated.filter { $0.status == .failed }.count

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

    // MARK: - Gateway Health

    /// Start polling the Gateway every 30s for connectivity status.
    private func startHealthPolling() {
        // Immediate first check
        Task { await checkGatewayHealth() }

        healthPollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.checkGatewayHealth() }
        }
    }

    /// Check if the Hermes Gateway is reachable and update isGatewayOnline.
    @MainActor
    func checkGatewayHealth() async {
        isGatewayOnline = await client.checkHealth()
    }
}
