import AppKit
import SwiftUI

/// Render markdown text with fallback to plain text.
/// Skips markdown parsing for ASCII art (contains box-drawing chars).
func md(_ text: String) -> Text {
    if text.contains("\u{2554}") || text.contains("\u{2557}") || text.contains("\u{2588}") || text.contains("╔") || text.contains("██") {
        return Text(text)
    }
    if let attr = try? AttributedString(markdown: text) {
        return Text(attr)
    }
    return Text(text)
}


struct HermesChatView: View {
    @ObservedObject var manager: AgentManager
    @FocusState private var isInputFocused: Bool
    @State private var selectionCtx: XcodeSelectionContext?
    @State private var buildLog: [String] = []
    @State private var isBuilding = false
    @State private var showBuildLog = false
    @State private var currentFileName: String?
    @State private var showTestOptions = false

    let initialCode: String?

    var activeTab: AgentTab { manager.activeTab }
    var permissions: AgentPermissions { activeTab.permissions }
    var messages: [StoredMessage] { activeTab.messages }
    var inputText: Binding<String> {
        Binding(
            get: { self.activeTab.inputText },
            set: { self.manager.updateInput($0, for: self.activeTab.id) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            TabBarView(manager: manager)
            Divider().background(Color.hermes.opacity(0.3))

            // Toolbar (permission-aware + mode-aware)
            XcodeToolbarView(
                currentFile: currentFileName,
                isBuilding: isBuilding,
                permissions: permissions,
                mode: $manager.mode,
                onReadFile: permissions.readFile ? readCurrentFile : nil,
                onBuild: permissions.build ? startBuild : nil,
                onTest: permissions.test ? startTest : nil,
                onProjectInfo: permissions.structure ? showProjectInfo : nil,
                onCancel: cancelBuild,
                onQuickAction: handleQuickAction
            )
            .padding(.horizontal, 10).padding(.vertical, 4)

            Divider().background(Color.hermes.opacity(0.3))

            // Tool Call Visualizer
            LiveToolCallBar(
                toolCalls: manager.activeToolCalls,
                isStreaming: manager.isStreaming
            )

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { msg in
                            TerminalMessageView(msg: msg.asStructured, manager: manager)
                        }
                        if manager.streamingTabs.contains(activeTab.id) {
                            let streamText = manager.streamingTexts[activeTab.id] ?? ""
                            if streamText.isEmpty {
                                // Backend is processing — show Thinking indicator
                                ThinkingIndicator().id("cursor")
                            } else {
                                let streamMsg = StructuredMessage(
                                    role: "assistant",
                                    segments: MessageParser.parse(streamText + "\u{258C}"),
                                    rawText: streamText + "\u{258C}"
                                )
                                TerminalMessageView(msg: streamMsg).id("cursor")
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 8).id("bottom")
                }
                .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
                .onChange(of: manager.currentAssistantText) { _, _ in
                    if manager.streamingTabs.contains(activeTab.id) {
                        proxy.scrollTo("cursor", anchor: .bottom)
                    }
                }
            }

            // Build Log
            if showBuildLog {
                Divider().background(Color.hermes.opacity(0.3))
                BuildLogView(log: buildLog, isBuilding: isBuilding) { showBuildLog = false }
                    .frame(maxHeight: 160)
            }

            Divider().background(Color.hermes.opacity(0.3))

            // Selection + Input
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    if let ctx = selectionCtx {
                        SelectionPill(context: ctx) { selectionCtx = nil }
                    }
                    Spacer()
                    Button { checkContext() } label: {
                        Image(systemName: "arrow.clockwise").font(.caption2)
                    }.buttonStyle(.plain).foregroundColor(.hermes.opacity(0.6))
                        .help("Refresh Xcode selection").disabled(manager.isStreaming)
                }

                HStack(spacing: 6) {
                    TextField("Ask Hermes...", text: inputText)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .onSubmit(send)
                        .disabled(manager.isStreaming)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(white: 0.12))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.hermes.opacity(0.4), lineWidth: 1))

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title3)
                            .foregroundColor(inputText.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty || manager.isStreaming ? .gray : .hermes)
                    }.buttonStyle(.plain)
                        .disabled(inputText.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty || manager.isStreaming)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .background(Color.black)
        .frame(minWidth: 420, minHeight: 540)
        .onAppear { checkContext() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in checkContext() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in checkContext() }
        .onChange(of: isInputFocused) { _, _ in checkContext() }
        .onAppear { XcodeContextProvider.shared.buildDelegate = self }
        .confirmationDialog("No test targets found", isPresented: $showTestOptions, titleVisibility: .visible) {
            Button("Build only") { startBuild() }
            Button("Create test target") { createAndRunTests() }
            Button("How to add tests") {
                manager.appendMessage(StoredMessage(role: "assistant", text: "To add a test target: File > New > Target > Unit Testing Bundle"), to: activeTab.id)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Create new agent?", isPresented: Binding(
            get: { manager.pendingAgentName != nil },
            set: { if !$0 { manager.cancelCreateAgent() } }
        ), titleVisibility: .visible) {
            if let name = manager.pendingAgentName {
                Text("Create agent \"\(name)\"?")
                Button("Create") { manager.confirmCreateAgent() }
                Button("Cancel", role: .cancel) { manager.cancelCreateAgent() }
            }
        }
        // Profile editor sheet
        .sheet(isPresented: $manager.showProfileEditor) {
            if let tabId = manager.editingProfileTabId {
                AgentProfileEditor(manager: manager, tabId: tabId)
            }
        }
    }

    private func checkContext() {
        guard !manager.isStreaming else { return }
        DispatchQueue.global().async {
            let ctx = XcodeContextProvider.shared.fetchSelection()
            let name = XcodeContextProvider.shared.readCurrentFileName()
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) { selectionCtx = ctx }
                currentFileName = name
            }
        }
    }

    private func send() {
        guard !activeTab.inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        manager.sendMessage(from: activeTab.id)
    }

    private func readCurrentFile() {
        DispatchQueue.global().async {
            guard let content = XcodeContextProvider.shared.readCurrentFile(),
                  let name = XcodeContextProvider.shared.readCurrentFileName() else { return }
            DispatchQueue.main.async { manager.updateInput("I'm looking at `\(name)`:\n\n```swift\n\(content)\n```", for: activeTab.id) }
        }
    }

    private func startBuild() {
        showBuildLog = true; isBuilding = true
        buildLog = ["Building...\n"]
        XcodeContextProvider.shared.buildDelegate = self
        XcodeContextProvider.shared.buildProject()
    }

    private func startTest() { showTestOptions = true }

    private func createAndRunTests() {
        showBuildLog = true; isBuilding = true
        buildLog = ["Creating test target...\n"]
        guard let info = XcodeContextProvider.shared.getProjectInfo(),
              let scheme = info.activeScheme ?? info.schemes.first else {
            buildLog.append("Could not determine project/scheme"); isBuilding = false; return
        }
        let projDir = (info.projectPath as NSString).deletingLastPathComponent
        let testDir = "\(projDir)/Hermes4XcodeTests"
        let testFile = "\(testDir)/Hermes4XcodeTests.swift"
        let cmds = """
        mkdir -p "\(testDir)"
        cat > "\(testFile)" << 'TESTEOF'
        import XCTest
        @testable import Hermes4Xcode
        final class Hermes4XcodeTests: XCTestCase {
            func testAppLaunches() throws { XCTAssertTrue(true) }
        }
        TESTEOF
        """
        XcodeContextProvider.shared.runShellAsync("cd \"\(projDir)\" && \(cmds)")
        buildLog.append("Created test file\nAdd test target in Xcode\n")
        isBuilding = false
    }

    private func cancelBuild() {
        XcodeContextProvider.shared.cancelBuild()
        isBuilding = false; buildLog.append("\nCancelled")
    }

    private func showProjectInfo() {
        guard let info = XcodeContextProvider.shared.getProjectInfo() else {
            manager.appendMessage(StoredMessage(role: "assistant", text: "Could not read project info."), to: activeTab.id)
            return
        }
        let text = info.summary + (!info.targets.isEmpty ? "\nTargets: " + info.targets.joined(separator: ", ") : "")
        manager.appendMessage(StoredMessage(role: "assistant", text: text), to: activeTab.id)
    }

    private func handleQuickAction(_ action: String) {
        // Check permission for each action
        switch action {
        case "fix_build":
            guard permissions.build else { return }
        case "generate_tests":
            guard permissions.test else { return }
        case "review", "refactor", "analyze":
            guard permissions.analyze else { return }
        case "commit":
            guard permissions.commit else { return }
        case "structure":
            guard permissions.structure else {
                if let s = XcodeContextProvider.shared.readProjectStructure() {
                    manager.appendMessage(StoredMessage(role: "assistant", text: s), to: activeTab.id)
                }
                return
            }
        case "save_note":
            guard permissions.note else { return }
        default:
            break
        }

        let prompt: String
        switch action {
        case "fix_build": prompt = "Read the last build errors and fix them. Build again to verify."
        case "generate_tests": prompt = "Look at the current file and generate comprehensive unit tests using XCTest."
        case "review": prompt = "Review the current file. Check for: code style, bugs, performance."
        case "refactor": prompt = "Refactor the selected code. Explain what you changed."
        case "commit": prompt = "Look at the current git diff and generate a concise git commit message."
        case "structure":
            if let s = XcodeContextProvider.shared.readProjectStructure() {
                manager.appendMessage(StoredMessage(role: "assistant", text: s), to: activeTab.id)
            } else { manager.appendMessage(StoredMessage(role: "assistant", text: "Could not read project structure."), to: activeTab.id) }
            return
        case "save_note": manager.updateInput("Remember this about the project: ", for: activeTab.id); return
        case "analyze":
            guard let fp = getCurrentFilePath() else {
                manager.appendMessage(StoredMessage(role: "assistant", text: "No file open."), to: activeTab.id); return
            }
            let fn = (fp as NSString).lastPathComponent
            manager.appendMessage(StoredMessage(role: "assistant", text: "Analyzing \(fn) with SourceKit-LSP..."), to: activeTab.id)
            Task {
                let r = await SourceKitLSPClient.shared.getDiagnostics(file: fp) ?? "Analysis complete"
                await MainActor.run { manager.appendMessage(StoredMessage(role: "assistant", text: r), to: activeTab.id) }
            }
            return
        default: return
        }
        manager.updateInput(prompt, for: activeTab.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { send() }
    }

    private func getCurrentFilePath() -> String? {
        XcodeContextProvider.shared.readCurrentFilePath()
    }
}

// MARK: - Build Delegate

extension HermesChatView: XcodeBuildDelegate {
    func buildOutputReceived(_ line: String) { buildLog.append(line); if !showBuildLog { showBuildLog = true } }
    func buildFinished(exitCode: Int32) {
        isBuilding = false
        buildLog.append("\n\(exitCode == 0 ? "Build Succeeded" : "Build Failed (exit \(exitCode))")\n")
    }
}

// MARK: - Terminal Message View

struct TerminalMessageView: View {
    let msg: StructuredMessage
    let manager: AgentManager?

    init(msg: StructuredMessage, manager: AgentManager? = nil) {
        self.msg = msg
        self.manager = manager
    }

    @State private var showForwardPicker = false

    var body: some View {
        VStack(spacing: 0) {
            if msg.role == "user" {
                HStack {
                    Spacer(minLength: 40)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("You")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.hermesAmber)
                        md(msg.rawText)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Color(white: 0.9))
                            .textSelection(.enabled)
                            .padding(10)
                            .background(Color(white: 0.15))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hermesAmber.opacity(0.3), lineWidth: 1))
                            .contextMenu {
                                if let mgr = manager, !mgr.eligibleForwardTargets.isEmpty {
                                    Button("Forward to Agent...") { showForwardPicker = true }
                                }
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(msg.rawText, forType: .string)
                                }
                            }
                    }
                    .frame(maxWidth: 380, alignment: .trailing)
                }
                .sheet(isPresented: $showForwardPicker) {
                    AgentForwardPicker(
                        manager: manager,
                        message: StoredMessage(role: msg.role, text: msg.rawText)
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        // Forwarded from badge
                        if let storedMsg = msg as? StoredMessage, let fromName = storedMsg.forwardedFromName {
                            Text("\u{21B3} from \(fromName)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.hermes.opacity(0.6))
                                .padding(.leading, 14)
                        }
                        Text("\u{256D}\u{2500} \u{2695} Hermes ")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(.hermes.opacity(0.8))
                            .fixedSize()
                        Rectangle()
                            .fill(Color.hermes.opacity(0.8))
                            .frame(height: 1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(msg.segments) { segment in
                            SegmentView(segment: segment)
                        }
                    }
                    .padding(.leading, 14).padding(.vertical, 4)
                    .contextMenu {
                        if let mgr = manager, !mgr.eligibleForwardTargets.isEmpty {
                            Button("Forward to Agent...") { showForwardPicker = true }
                        }
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(msg.rawText, forType: .string)
                        }
                    }
                    HStack(spacing: 0) {
                        Text("\u{2570}\u{2500}")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(.hermes.opacity(0.4))
                            .fixedSize()
                        Rectangle()
                            .fill(Color.hermes.opacity(0.4))
                            .frame(height: 1)
                    }
                }
            }
        }
    }
}

// MARK: - Segment View

struct SegmentView: View {
    let segment: MessageSegment

    var body: some View {
        switch segment {
        case .text(let t):
            md(t)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Color(white: 0.85))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .toolCall(let icon, let name, let status, let detail):
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption).foregroundColor(statusColor(status))
                Text(status.rawValue + " " + name).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(statusColor(status))
                Spacer()
                Text(detail).font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(white: 0.12)).cornerRadius(4)
        case .diff(let file, let code):
            DiffPreviewView(file: file, code: code) {
                DispatchQueue.global().async {
                    _ = XcodeContextProvider.shared.replaceSelection(with: code)
                }
            }
        }
    }

    func statusColor(_ s: ToolCallStatus) -> Color {
        switch s { case .pending: return .gray; case .running: return .blue; case .success: return .green; case .failed: return .red }
    }
}

// MARK: - Permission-Aware Toolbar

struct XcodeToolbarView: View {
    let currentFile: String?
    let isBuilding: Bool
    let permissions: AgentPermissions
    @Binding var mode: ExecutionMode

    let onReadFile: (() -> Void)?
    let onBuild: (() -> Void)?
    let onTest: (() -> Void)?
    let onProjectInfo: (() -> Void)?
    let onCancel: () -> Void
    let onQuickAction: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            if let file = currentFile {
                Text(file).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()

            // Plan & ReAct mode toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    mode = mode == .chat ? .plan : .chat
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: mode.icon)
                        .font(.system(size: 9))
                    Text(mode.shortLabel)
                        .font(.system(size: 9, design: .monospaced))
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(mode == .plan ? Color.hermes.opacity(0.25) : Color(white: 0.12))
                .cornerRadius(4)
                .foregroundColor(mode == .plan ? .hermes : .gray)
            }
            .buttonStyle(.plain)
            .help(mode == .chat ? "Enable Plan & ReAct — plan first, then execute" : "Disable Plan & ReAct — chat mode")

            // Permission-gated buttons
            if let read = onReadFile {
                TBtn(icon: "doc.text.magnifyingglass", label: "Read", action: read, disabled: isBuilding)
            }
            if let build = onBuild {
                TBtn(icon: "hammer.fill", label: "Build", action: build, disabled: isBuilding)
            }
            if let test = onTest {
                TBtn(icon: "checkmark.circle", label: "Test", action: test, disabled: isBuilding)
            }
            if isBuilding {
                TBtn(icon: "stop.fill", label: "Stop", action: onCancel, disabled: false).foregroundColor(.red)
            }

            // Permission-gated quick menu
            if hasQuickActions {
                Menu {
                    if permissions.build {
                        Button("Fix Build Errors") { onQuickAction("fix_build") }
                    }
                    if permissions.test {
                        Button("Generate Tests") { onQuickAction("generate_tests") }
                    }
                    if permissions.analyze {
                        Button("Review File") { onQuickAction("review") }
                        Button("Refactor") { onQuickAction("refactor") }
                    }
                    if permissions.commit {
                        Button("Commit Message") { onQuickAction("commit") }
                    }
                    if permissions.structure || permissions.readFile {
                        Divider()
                        if permissions.structure {
                            Button("Project Structure") { onQuickAction("structure") }
                        }
                    }
                    if permissions.note {
                        Button("Save Note...") { onQuickAction("save_note") }
                    }
                    if permissions.analyze {
                        Divider()
                        Button("Analyze (LSP)") { onQuickAction("analyze") }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill").font(.caption)
                        Text("Quick").font(.system(size: 10, design: .monospaced))
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.hermes.opacity(0.15)).cornerRadius(4).foregroundColor(.hermes)
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
    }

    private var hasQuickActions: Bool {
        permissions.build || permissions.test || permissions.analyze ||
        permissions.commit || permissions.structure || permissions.note
    }
}

struct TBtn: View {
    let icon: String; let label: String; let action: () -> Void; let disabled: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: icon).font(.caption)
                Text(label).font(.system(size: 10, design: .monospaced))
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(disabled ? Color.gray.opacity(0.1) : Color.hermes.opacity(0.1)).cornerRadius(4)
        }
        .buttonStyle(.plain).disabled(disabled).foregroundColor(disabled ? .gray : .hermes)
    }
}

// MARK: - Build Log

struct BuildLogView: View {
    let log: [String]
    let isBuilding: Bool
    let onClose: () -> Void

    @State private var entries: [BuildLogEntry] = []
    @State private var summary: BuildSummary?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let s = summary, !isBuilding {
                    HStack(spacing: 6) {
                        Image(systemName: s.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .font(.caption).foregroundColor(s.succeeded ? .green : .red)
                        Text(s.succeeded ? "Build Succeeded" : "Build Failed")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        if s.errorCount > 0 {
                            Text("\(s.errorCount) errors").font(.system(size: 9, design: .monospaced)).foregroundColor(.red)
                        }
                        if s.warningCount > 0 {
                            Text("\(s.warningCount) warnings").font(.system(size: 9, design: .monospaced)).foregroundColor(.yellow)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Circle().fill(Color.hermes).frame(width: 6, height: 6)
                            .opacity(isBuilding ? 1 : 0)
                        Text(isBuilding ? "Building..." : "Build Log")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(isBuilding ? .hermes : .green)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    if !isBuilding {
                        Button(action: copyLog) {
                            Image(systemName: "doc.on.doc").font(.caption2)
                        }.buttonStyle(.plain).foregroundColor(.secondary)
                    }
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)

            if !isBuilding, let s = summary, s.errorCount > 0 {
                // Error list view
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(entries) { entry in
                                BuildLogRow(entry: entry)
                            }
                        }
                        .padding(4)
                        .id("logBottom")
                    }
                    .onChange(of: entries.count) { _, _ in
                        withAnimation { proxy.scrollTo("logBottom") }
                    }
                }
            } else {
                // Raw log view (during build or no errors)
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(log.joined())
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(white: 0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id("logBottom")
                    }
                    .onChange(of: log.count) { _, _ in
                        withAnimation { proxy.scrollTo("logBottom") }
                    }
                }
            }
        }
        .onChange(of: log) { _, newLog in
            let full = newLog.joined()
            entries = BuildLogParser.parse(full)
            summary = BuildLogParser.summary(from: entries)
        }
    }

    private func copyLog() {
        let full = log.joined()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full, forType: .string)
    }
}

// MARK: - Build Log Row

struct BuildLogRow: View {
    let entry: BuildLogEntry

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.type.icon)
                .font(.system(size: 8))
                .foregroundColor(entry.type.color)
                .frame(width: 12)

            if let file = entry.file, let line = entry.line {
                Button(action: { openInXcode(file: file, line: line) }) {
                    Text("\((file as NSString).lastPathComponent):\(line)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(entry.type.color.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Open in Xcode")
            }

            Text(entry.message)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(white: 0.7))
                .lineLimit(2)
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(entry.type == .error ? Color.red.opacity(0.06) : Color.clear)
        .cornerRadius(3)
    }

    private func openInXcode(file: String, line: Int) {
        let fullPath: String
        if file.hasPrefix("/") {
            fullPath = file
        } else {
            fullPath = FileManager.default.currentDirectoryPath + "/" + file
        }
        let url = URL(fileURLWithPath: fullPath)
        NSWorkspace.shared.open(url)
        // Also try to open to specific line via AppleScript
        let script = """
        tell application "Xcode"
            open "\(fullPath)"
            activate
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }
}

// MARK: - Selection Pill

struct SelectionPill: View {
    let context: XcodeSelectionContext; let onDismiss: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            Text(context.summary).font(.system(size: 9, design: .monospaced)).foregroundColor(.hermes)
            Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 8)).foregroundColor(.secondary) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.hermes.opacity(0.1)).cornerRadius(4)
    }
}

// MARK: - Gateway Status (kept for compatibility, not directly used in tab layout)

struct GatewayStatusDot: View {
    @State private var isReachable = false; @State private var checking = true
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(checking ? Color.gray : (isReachable ? Color.green : Color.red)).frame(width: 6, height: 6)
            Text(checking ? "..." : (isReachable ? "Connected" : "Offline"))
                .font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary)
        }
        .onAppear { checkGateway() }
    }
    private func checkGateway() {
        guard let url = URL(string: "http://127.0.0.1:8642/v1/models") else { return }
        URLSession.shared.dataTask(with: url) { _, resp, err in
            Task { @MainActor in
                checking = false; isReachable = (resp as? HTTPURLResponse)?.statusCode == 200 && err == nil
            }
        }.resume()
    }
}

// MARK: - Thinking Indicator

/// Pulsing "Thinking..." animation shown while backend processes but hasn't returned text yet.
struct ThinkingIndicator: View {
    @State private var phase = 0
    private let dots = ["", ".", "..", "...", "..", "."]

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.hermes)
                .frame(width: 8, height: 8)
                .opacity(phase == 0 ? 1 : 0.3)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: phase)
            Text("Thinking\(dots[phase])")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.hermes.opacity(0.8))
        }
        .padding(.leading, 14).padding(.vertical, 8)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                phase = (phase + 1) % dots.count
            }
        }
    }
}
