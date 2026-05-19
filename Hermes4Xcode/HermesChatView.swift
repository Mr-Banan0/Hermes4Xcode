import SwiftUI
import AppKit

struct Message: Identifiable {
    let id = UUID()
    let role: String
    let text: String
}

// MARK: - Main Chat View

struct HermesChatView: View {
    @State private var messages: [StructuredMessage] = []
    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var currentAssistantText = ""
    @FocusState private var isInputFocused: Bool
    @State private var selectionCtx: XcodeSelectionContext?

    @State private var buildLog: [String] = []
    @State private var isBuilding = false
    @State private var showBuildLog = false
    @State private var currentFileName: String?
    @State private var showTestOptions = false
    @State private var pendingTestAction: (() -> Void)?

    let initialCode: String?
    private let client = HermesAPIClient()

    private let welcomeMessage = StructuredMessage(
        role: "assistant",
        segments: [.text(
            "██╗  ██╗███████╗██████╗ ███╗   ███╗███████╗███████╗       █████╗  ██████╗ ███████╗███╗   ██╗████████╗\n" +
            "██║  ██║██╔════╝██╔══██╗████╗ ████║██╔════╝██╔════╝      ██╔══██╗██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝\n" +
            "███████║█████╗  ██████╔╝██╔████╔██║█████╗  ███████╗█████╗███████║██║  ███╗█████╗  ██╔██╗ ██║   ██║\n" +
            "██╔══██║██╔══╝  ██╔══██╗██║╚██╔╝██║██╔══╝  ╚════██║╚════╝██╔══██║██║   ██║██╔══╝  ██║╚██╗██║   ██║\n" +
            "██║  ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗███████║      ██║  ██║╚██████╔╝███████╗██║ ╚████║   ██║\n" +
            "╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝      ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝\n\n" +
            "Select code in Xcode, then chat with me below.\n\n" +
            "  \u{2022} \u{1F3D7} Build \u{2014} compile\n  \u{2022} \u{1F9EA} Test \u{2014} run/create tests\n  \u{2022} \u{26A1} Quick \u{2014} fix, review, refactor\n  \u{2022} \u{1F504} Refresh \u{2014} detect Xcode selection"
        )],
        rawText: "Welcome"
    )

    var body: some View {
        VStack(spacing: 0) {
            // Title Bar
            HStack {
                Text("Hermes4Xcode")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.hermes)
                Spacer()
                HStack(spacing: 4) {
                    GatewayStatusDot()
                    if isStreaming {
                        ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 4)

            Divider().background(Color.hermes.opacity(0.3))

            // Toolbar
            XcodeToolbarView(
                currentFile: currentFileName, isBuilding: isBuilding,
                onReadFile: readCurrentFile, onBuild: startBuild, onTest: startTest,
                onProjectInfo: showProjectInfo, onCancel: cancelBuild,
                onQuickAction: handleQuickAction
            )
            .padding(.horizontal, 10).padding(.vertical, 4)

            Divider().background(Color.hermes.opacity(0.3))

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { msg in
                            TerminalMessageView(msg: msg)
                        }
                        if isStreaming {
                            TerminalMessageView(msg: StructuredMessage(
                                role: "assistant",
                                segments: MessageParser.parse(currentAssistantText + "\u{258C}"),
                                rawText: currentAssistantText + "\u{258C}"
                            )).id("cursor")
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 8).id("bottom")
                }
                .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
                .onChange(of: currentAssistantText) { _, _ in proxy.scrollTo("cursor", anchor: .bottom) }
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
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Spacer()
                    Button { checkContextOnActivate() } label: {
                        Image(systemName: "arrow.clockwise").font(.caption2)
                    }.buttonStyle(.plain).foregroundColor(.hermes.opacity(0.6))
                        .help("Refresh Xcode selection").disabled(isStreaming)
                }

                HStack(spacing: 6) {
                    TextField("Ask Hermes...", text: $inputText)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .onSubmit(send)
                        .disabled(isStreaming)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color(white: 0.12))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.hermes.opacity(0.4), lineWidth: 1))

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title3)
                            .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming ? .gray : .hermes)
                    }.buttonStyle(.plain)
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .background(Color.black)
        .frame(minWidth: 420, minHeight: 540)
        .onAppear {
            if messages.isEmpty { messages.append(welcomeMessage) }
            checkContextOnActivate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in checkContextOnActivate() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in checkContextOnActivate() }
        .onChange(of: isInputFocused) { _, _ in checkContextOnActivate() }
        .onAppear { XcodeContextProvider.shared.buildDelegate = self }
        .confirmationDialog("No test targets found", isPresented: $showTestOptions, titleVisibility: .visible) {
            Button("Build only (skip tests)") { startBuild() }
            Button("Create Unit Test Target + Run") { createAndRunTests() }
            Button("How to add tests") {
                messages.append(StructuredMessage(role: "assistant", segments: [.text(
"To add a test target in Xcode:\n\n1. File -> New -> Target\n2. Select \"Unit Testing Bundle\"\n3. Language: Swift\n4. Target: Hermes4Xcode\n5. Click Finish"
                )], rawText: "Test setup"))
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func checkContextOnActivate() {
        guard !isStreaming else { return }
        DispatchQueue.global().async {
            let ctx = XcodeContextProvider.shared.fetchSelection()
            let name = XcodeContextProvider.shared.readCurrentFileName()
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) { selectionCtx = ctx }
                currentFileName = name
            }
        }
    }

    private func getCurrentFilePath() -> String? {
        return XcodeContextProvider.shared.readCurrentFilePath()
    }

    private func readCurrentFile() {
        DispatchQueue.global().async {
            guard let content = XcodeContextProvider.shared.readCurrentFile(),
                  let name = XcodeContextProvider.shared.readCurrentFileName() else { return }
            DispatchQueue.main.async { inputText = "I'm looking at `\(name)`:\n\n```swift\n\(content)\n```" }
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
        buildLog.append("Created test file: Hermes4XcodeTests/Hermes4XcodeTests.swift\n")
        buildLog.append("Add test target in Xcode: File > New > Target > Unit Testing Bundle\n")
        isBuilding = false
    }

    private func cancelBuild() {
        XcodeContextProvider.shared.cancelBuild()
        isBuilding = false; buildLog.append("\nCancelled")
    }

    private func showProjectInfo() {
        guard let info = XcodeContextProvider.shared.getProjectInfo() else {
            messages.append(StructuredMessage(role: "assistant", segments: [.text("Could not read project info.")], rawText: "Error"))
            return
        }
        let text = info.summary + (!info.targets.isEmpty ? "\nTargets: " + info.targets.joined(separator: ", ") : "")
        messages.append(StructuredMessage(role: "assistant", segments: [.text(text)], rawText: text))
    }

    private func handleQuickAction(_ action: String) {
        let prompt: String
        switch action {
        case "fix_build": prompt = "Read the last build errors and fix them. Build again to verify."
        case "generate_tests": prompt = "Look at the current file and generate comprehensive unit tests using XCTest."
        case "review": prompt = "Review the current file. Check for: code style, bugs, performance, Swift best practices."
        case "refactor": prompt = "Refactor the selected code. Explain what you changed."
        case "commit": prompt = "Look at the current git diff and generate a concise git commit message."
        case "structure":
            if let s = XcodeContextProvider.shared.readProjectStructure() {
                messages.append(StructuredMessage(role: "assistant", segments: [.text(s)], rawText: s))
            } else { messages.append(StructuredMessage(role: "assistant", segments: [.text("Could not read project structure.")], rawText: "Error")) }
            return
        case "save_note": inputText = "Remember this about the project: "; return
        case "analyze":
            guard let fp = getCurrentFilePath() else {
                messages.append(StructuredMessage(role: "assistant", segments: [.text("No file open in Xcode.")], rawText: "Error")); return
            }
            let fn = (fp as NSString).lastPathComponent
            messages.append(StructuredMessage(role: "assistant", segments: [.text("Analyzing \(fn) with SourceKit-LSP...")], rawText: "Analyzing..."))
            Task {
                let r = await SourceKitLSPClient.shared.getDiagnostics(file: fp) ?? "Analysis complete"
                await MainActor.run { messages.append(StructuredMessage(role: "assistant", segments: [.text(r)], rawText: r)) }
            }
            return
        default: return
        }
        inputText = prompt
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { send() }
    }

    private func send() {
        let text = inputText; inputText = ""
        messages.append(StructuredMessage(role: "user", segments: [.text(text)], rawText: text))
        let attachedCtx = selectionCtx
        isStreaming = true; currentAssistantText = ""
        Task {
            var history = messages.map { ["role": $0.role, "content": $0.rawText] }
            if let ctx = attachedCtx {
                history.removeLast()
                history.append(["role": "system", "content": ctx.systemPrompt])
                history.append(["role": "user", "content": text])
            }
            await client.sendMessage(text, contextCode: attachedCtx?.selectedText, history: history,
                onDelta: { d in Task { @MainActor in currentAssistantText += d } },
                onComplete: { r in
                    Task { @MainActor in
                        isStreaming = false
                        switch r {
                        case .success(let full):
                            messages.append(StructuredMessage(role: "assistant", segments: MessageParser.parse(full), rawText: full))
                            autoApplyIfNeeded(response: full)
                        case .failure(let err):
                            messages.append(StructuredMessage(role: "assistant", segments: [.text("Error: \(err.localizedDescription)")], rawText: "Error"))
                        }
                        currentAssistantText = ""
                    }
                })
        }
    }

    private func autoApplyIfNeeded(response: String) {
        guard let ctx = selectionCtx else { return }
        guard let start = response.range(of: "```swift\n"),
              let end = response.range(of: "\n```", range: start.upperBound..<response.endIndex) else { return }
        let code = String(response[start.upperBound..<end.lowerBound])
        guard !code.isEmpty else { return }
        DispatchQueue.global().async {
            if XcodeContextProvider.shared.replaceSelection(with: code) {
                DispatchQueue.main.async { withAnimation { selectionCtx = nil } }
            }
        }
    }
}

// MARK: - Terminal Message View

struct TerminalMessageView: View {
    let msg: StructuredMessage

    var body: some View {
        VStack(spacing: 0) {
            if msg.role == "user" {
                HStack {
                    Spacer(minLength: 40)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("You")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.hermesAmber)
                        Text(msg.rawText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(white: 0.9))
                            .textSelection(.enabled)
                            .padding(10)
                            .background(Color(white: 0.15))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hermesAmber.opacity(0.3), lineWidth: 1))
                    }
                    .frame(maxWidth: 380, alignment: .trailing)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    // Top border — stretches with window
                    HStack(spacing: 0) {
                        Text("\u{256D}\u{2500} \u{2695} Hermes ")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(.hermes.opacity(0.8))
                            .fixedSize()
                        Rectangle()
                            .fill(Color.hermes.opacity(0.8))
                            .frame(height: 1)
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(msg.segments) { segment in
                            SegmentView(segment: segment)
                        }
                    }
                    .padding(.leading, 14).padding(.vertical, 4)

                    // Bottom border
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
            Text(t)
                .font(.system(size: 11, design: .monospaced))
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
            VStack(alignment: .leading, spacing: 4) {
                if !file.isEmpty {
                    HStack {
                        Image(systemName: "doc.badge.plus").font(.caption).foregroundColor(.hermes)
                        Text(file).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                        Spacer()
                        Button("Apply") {
                            DispatchQueue.global().async { _ = XcodeContextProvider.shared.replaceSelection(with: code) }
                        }.font(.system(size: 8, design: .monospaced)).buttonStyle(.plain).foregroundColor(.hermes)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code).font(.system(size: 10, design: .monospaced)).foregroundColor(Color(white: 0.8)).textSelection(.enabled)
                }
                .padding(8).background(Color(white: 0.08)).cornerRadius(6)
            }
        }
    }

    private func statusColor(_ s: ToolCallStatus) -> Color {
        switch s { case .pending: return .gray; case .running: return .blue; case .success: return .green; case .failed: return .red }
    }
}

// MARK: - Toolbar

struct XcodeToolbarView: View {
    let currentFile: String?; let isBuilding: Bool
    let onReadFile: () -> Void; let onBuild: () -> Void; let onTest: () -> Void
    let onProjectInfo: () -> Void; let onCancel: () -> Void; let onQuickAction: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            if let file = currentFile {
                Text(file).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            TBtn(icon: "doc.text.magnifyingglass", label: "Read", action: onReadFile, disabled: isBuilding)
            TBtn(icon: "hammer.fill", label: "Build", action: onBuild, disabled: isBuilding)
            TBtn(icon: "checkmark.circle", label: "Test", action: onTest, disabled: isBuilding)
            if isBuilding { TBtn(icon: "stop.fill", label: "Stop", action: onCancel, disabled: false).foregroundColor(.red) }
            Menu {
                Button("Fix Build Errors") { onQuickAction("fix_build") }
                Button("Generate Tests") { onQuickAction("generate_tests") }
                Button("Review File") { onQuickAction("review") }
                Button("Refactor") { onQuickAction("refactor") }
                Button("Commit Message") { onQuickAction("commit") }
                Divider()
                Button("Project Structure") { onQuickAction("structure") }
                Button("Save Note...") { onQuickAction("save_note") }
                Divider()
                Button("Analyze (LSP)") { onQuickAction("analyze") }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill").font(.caption)
                    Text("Quick").font(.system(size: 9, design: .monospaced))
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.hermes.opacity(0.15)).cornerRadius(4).foregroundColor(.hermes)
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }
}

struct TBtn: View {
    let icon: String; let label: String; let action: () -> Void; let disabled: Bool
    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: icon).font(.caption)
                Text(label).font(.system(size: 9, design: .monospaced))
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(disabled ? Color.gray.opacity(0.1) : Color.hermes.opacity(0.1)).cornerRadius(4)
        }
        .buttonStyle(.plain).disabled(disabled).foregroundColor(disabled ? .gray : .hermes)
    }
}

// MARK: - Build Log

struct BuildLogView: View {
    let log: [String]; let isBuilding: Bool; let onClose: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isBuilding ? "Building..." : "Build Log")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(isBuilding ? .hermes : .green)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            ScrollViewReader { proxy in
                ScrollView {
                    Text(log.joined()).font(.system(size: 8, design: .monospaced)).foregroundColor(Color(white: 0.6))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).id("logBottom")
                }
                .onChange(of: log.count) { _, _ in withAnimation { proxy.scrollTo("logBottom") } }
            }
        }
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

// MARK: - Gateway Status

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
