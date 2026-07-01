import AppKit
import Foundation

// MARK: - Models

struct XcodeSelectionContext {
    let filePath: String
    let fileName: String
    let startLine: Int
    let endLine: Int
    let selectedText: String

    var summary: String { "\(fileName) · lines \(startLine)-\(endLine)" }

    var systemPrompt: String {
        """
        The user is working on the file `\(fileName)` (\(filePath)) \
        and has selected lines \(startLine)-\(endLine):

        ```swift
        \(selectedText)
        ```

        Use this context to inform your response. \
        If you generate code that should replace the selection, \
        wrap it in a code block so the app can apply it automatically.
        """
    }
}

struct XcodeProjectInfo {
    let projectPath: String
    let projectName: String
    let schemes: [String]
    let targets: [String]
    let activeScheme: String?

    var summary: String {
        var s = "📁 \(projectName)\n  Schemes: \(schemes.joined(separator: ", "))"
        if let active = activeScheme { s += "\n  Active: \(active)" }
        return s
    }
}

/// Delegate for receiving build/test output line by line.
protocol XcodeBuildDelegate {
    func buildOutputReceived(_ line: String)
    func buildFinished(exitCode: Int32)
}

// MARK: - Provider

final class XcodeContextProvider {
    static let shared = XcodeContextProvider()
    private var buildProcess: Process?
    var buildDelegate: XcodeBuildDelegate?

    /// Callback fired when a build completes, forwarding exit code + captured output.
    var onBuildComplete: ((Int32, String) -> Void)?

    private var buildOutputBuffer = ""
    private var buildStartTime: Date?

    private init() {}

    // ── Selection ──

    func fetchSelection() -> XcodeSelectionContext? {
        guard XcodeIsRunning() else { return nil }

        let script = """
        tell application "Xcode"
            try
                set src to source document 1
                set srcFile to file of src
                set docPath to POSIX path of srcFile
                set docName to name of src
                try
                    set selRange to selected paragraph range of src
                    set sLine to item 1 of selRange
                    set eLine to item 2 of selRange
                on error
                    return "ERR_NO_SELECTION"
                end try
                set fullText to text of src
                set lineList to paragraphs of fullText
                set selText to ""
                repeat with i from sLine to eLine
                    set selText to selText & item i of lineList & linefeed
                end repeat
                return docPath & "|||" & docName & "|||" & sLine & "|||" & eLine & "|||" & selText
            on error errMsg
                return "ERR: " & errMsg
            end try
        end tell
        """
        guard let output = runOSAScript(script), !output.isEmpty, !output.hasPrefix("ERR:"),
              output != "ERR_NO_SELECTION" else { return nil }
        let parts = output.components(separatedBy: "|||")
        guard parts.count == 5,
              let startLine = Int(parts[2]), let endLine = Int(parts[3]) else { return nil }
        let text = parts[4].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return XcodeSelectionContext(filePath: parts[0], fileName: parts[1], startLine: startLine, endLine: endLine, selectedText: text)
    }

    // ── Read Current File ──

    func readCurrentFile() -> String? {
        guard XcodeIsRunning() else { return nil }
        let script = """
        tell application "Xcode"
            try
                set src to source document 1
                return text of src
            on error errMsg
                return "ERR: " & errMsg
            end try
        end tell
        """
        guard let output = runOSAScript(script), !output.hasPrefix("ERR:"), !output.isEmpty else { return nil }
        return output
    }

    func readCurrentFileName() -> String? {
        guard XcodeIsRunning() else { return nil }
        let script = """
        tell application "Xcode"
            try
                return name of source document 1
            on error
                return ""
            end try
        end tell
        """
        return runOSAScript(script)
    }

    // ── Replace Selection ──

    func replaceSelection(with code: String) -> Bool {
        let escaped = code.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let script = """
        tell application "Xcode"
            try
                set src to source document 1
                set selRange to selected paragraph range of src
                set sLine to item 1 of selRange
                set eLine to item 2 of selRange
                set fullText to text of src
                set lineList to paragraphs of fullText
                set charStart to 1
                repeat with i from 1 to sLine - 1
                    set charStart to charStart + (length of item i of lineList) + 1
                end repeat
                set charEnd to charStart
                repeat with i from sLine to eLine
                    set charEnd to charEnd + (length of item i of lineList) + 1
                end repeat
                set charEnd to charEnd - 1
                set selected character range to {charStart, charEnd}
                set selection to "\(escaped)"
                return "OK"
            end try
        end tell
        """
        guard let result = runOSAScript(script) else { return false }
        return result == "OK"
    }

    // ── Build ──

    func buildProject(projectPath: String? = nil, scheme: String? = nil) {
        let projectArg: String
        if let pp = projectPath {
            projectArg = pp.hasSuffix(".xcworkspace") ? "-workspace \"\(pp)\"" : "-project \"\(pp)\""
            let dir = (pp as NSString).deletingLastPathComponent
            let schemeArg = scheme ?? ""
            let cmd = "cd \"\(dir)\" && xcodebuild \(projectArg) -scheme \"\(schemeArg)\" build 2>&1"
            runShellAsync(cmd)
        } else if let info = getProjectInfo() {
            projectArg = "-project \"\(info.projectPath)\""
            let dir = (info.projectPath as NSString).deletingLastPathComponent
            let schemeArg = scheme ?? info.activeScheme ?? info.schemes.first ?? ""
            let cmd = "cd \"\(dir)\" && xcodebuild \(projectArg) -scheme \"\(schemeArg)\" build 2>&1"
            runShellAsync(cmd)
        }
    }

    func testProject(projectPath: String? = nil, scheme: String? = nil) {
        let projectArg: String
        if let pp = projectPath {
            projectArg = pp.hasSuffix(".xcworkspace") ? "-workspace \"\(pp)\"" : "-project \"\(pp)\""
            let dir = (pp as NSString).deletingLastPathComponent
            let schemeArg = scheme ?? ""
            let cmd = "cd \"\(dir)\" && xcodebuild \(projectArg) -scheme \"\(schemeArg)\" test 2>&1"
            runShellAsync(cmd)
        } else if let info = getProjectInfo() {
            projectArg = "-project \"\(info.projectPath)\""
            let dir = (info.projectPath as NSString).deletingLastPathComponent
            let schemeArg = scheme ?? info.activeScheme ?? info.schemes.first ?? ""
            // Check if scheme has test targets; if not, fall back to build
            let checkCmd = "xcodebuild \(projectArg) -scheme \"\(schemeArg)\" -showTestPlans 2>/dev/null | head -1"
            if let check = runShell(checkCmd), check.contains("No test plans") || check.isEmpty {
                let cmd = "cd \"\(dir)\" && xcodebuild \(projectArg) -scheme \"\(schemeArg)\" build 2>&1"
                runShellAsync(cmd)
            } else {
                let cmd = "cd \"\(dir)\" && xcodebuild \(projectArg) -scheme \"\(schemeArg)\" test 2>&1"
                runShellAsync(cmd)
            }
        }
    }

    func cancelBuild() {
        buildProcess?.terminate()
        buildProcess = nil
    }

    var isBuilding: Bool {
        if let p = buildProcess, p.isRunning { return true }
        return false
    }

    // ── Project Info ──

    func getProjectInfo() -> XcodeProjectInfo? {
        guard XcodeIsRunning() else { return nil }

        // Get active project path and schemes
        let script = """
        tell application "Xcode"
            try
                set ws to workspace document 1
                set wsFile to file of ws
                set wsPath to POSIX path of wsFile
                set schNames to name of every scheme of ws
                set schList to ""
                repeat with s in schNames
                    set schList to schList & s & ","
                end repeat
                set activeSch to ""
                try
                    set activeSch to name of active scheme of ws
                end try
                return wsPath & "|||" & schList & "|||" & activeSch
            on error errMsg
                return "ERR: " & errMsg
            end try
        end tell
        """
        guard let output = runOSAScript(script), !output.hasPrefix("ERR:"), !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "|||")
        guard parts.count == 3 else { return nil }

        let path = parts[0]
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let schemes = parts[1].split(separator: ",").filter { !$0.isEmpty }.map(String.init)
        let active = parts[2].isEmpty ? nil : parts[2]

        // Get targets via xcodebuild
        var targets: [String] = []
        let projPath = (path as NSString).deletingPathExtension + ".xcodeproj"
        if let targetList = runShell("xcodebuild -project \"\(projPath)\" -list 2>/dev/null | sed -n '/^Targets:/,/^$/p' | tail -n +2") {
            targets = targetList.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        return XcodeProjectInfo(projectPath: path, projectName: name, schemes: schemes, targets: targets, activeScheme: active)
    }

    // ── Phase 4: Project Structure ──

    func readCurrentFilePath() -> String? {
        guard XcodeIsRunning() else { return nil }
        let script = """
        tell application "Xcode"
            try
                set src to source document 1
                set srcFile to file of src
                return POSIX path of srcFile
            on error
                return ""
            end try
        end tell
        """
        return runOSAScript(script)
    }

    func readProjectStructure() -> String? {
        guard XcodeIsRunning() else { return nil }
        let script = """
        tell application "Xcode"
            try
                set ws to workspace document 1
                set wsFile to file of ws
                set wsPath to POSIX path of wsFile
                set schNames to name of every scheme of ws
                set schList to ""
                repeat with s in schNames
                    set schList to schList & s & ","
                end repeat
                return wsPath & "|||" & schList
            on error
                return ""
            end try
        end tell
        """
        guard let output = runOSAScript(script), !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "|||")
        let projPath = parts.count >= 1 ? parts[0] : "?"
        let schemes = parts.count >= 2 ? parts[1] : ""
        let dir = (projPath as NSString).deletingLastPathComponent

        // List source files
        var structure = "📁 \((projPath as NSString).lastPathComponent)\n"
        if let files = runShell("find \"\(dir)\" -name \"*.swift\" -not -path \"*/DerivedData/*\" -not -path \"*/.build/*\" -not -path \"*/Pods/*\" 2>/dev/null | head -50") {
            let fileList = files.split(separator: "\n").map(String.init)
            if !fileList.isEmpty {
                structure += "📄 Swift files (\(fileList.count)):\n"
                for f in fileList.prefix(20) {
                    let relPath = f.replacingOccurrences(of: dir + "/", with: "")
                    structure += "  · \(relPath)\n"
                }
                if fileList.count > 20 {
                    structure += "  ... and \(fileList.count - 20) more\n"
                }
            }
        }
        if !schemes.isEmpty {
            structure += "🎯 Schemes: \(schemes)"
        }
        return structure
    }

    // ── Phase 4: Project Memory ──

    func saveProjectNote(_ note: String) {
        guard let projName = getProjectInfo()?.projectName else { return }
        var notes = loadProjectNotes(projName)
        notes.append(note)
        UserDefaults.standard.set(notes, forKey: "Hermes4Xcode_notes_\(projName)")
    }

    func loadProjectNotes(_ projName: String? = nil) -> [String] {
        let name = projName ?? getProjectInfo()?.projectName ?? "default"
        return UserDefaults.standard.stringArray(forKey: "Hermes4Xcode_notes_\(name)") ?? []
    }

    func readMultipleFiles(_ paths: [String]) -> String {
        var result = ""
        for path in paths {
            if let content = runShell("cat \"\(path)\" 2>/dev/null") {
                let name = (path as NSString).lastPathComponent
                result += "// File: \(name)\n\(content)\n\n"
            }
        }
        return result
    }

    private func XcodeIsRunning() -> Bool {
        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Xcode").first != nil
    }

    @discardableResult
    private func runOSAScript(_ script: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if p.terminationStatus != 0 { return nil }
            return output
        } catch { return nil }
    }

    @discardableResult
    func runShell(_ cmd: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", cmd]
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = outPipe
        do {
            try p.run()
            p.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }

    func runShellAsync(_ cmd: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", cmd]
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = outPipe

        buildProcess = p
        buildOutputBuffer = ""
        buildStartTime = Date()

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.buildOutputBuffer += line
                self?.buildDelegate?.buildOutputReceived(line)
            }
        }

        p.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                let elapsed = self?.buildStartTime.map { Date().timeIntervalSince($0) } ?? 0
                let output = self?.buildOutputBuffer ?? ""
                self?.buildDelegate?.buildFinished(exitCode: process.terminationStatus)
                self?.onBuildComplete?(process.terminationStatus, output)
                self?.buildProcess = nil
            }
        }

        do {
            try p.run()
        } catch {
            buildDelegate?.buildOutputReceived("Failed to start build: \(error.localizedDescription)")
            buildDelegate?.buildFinished(exitCode: -1)
        }
    }
}
