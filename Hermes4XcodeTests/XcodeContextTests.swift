@testable import HermesXcode
import XCTest

final class XcodeSelectionContextTests: XCTestCase {

    func test_selectionContext_init() {
        let ctx = XcodeSelectionContext(
            filePath: "/Users/test/Project/File.swift",
            fileName: "File.swift",
            startLine: 10,
            endLine: 20,
            selectedText: "func test() {}"
        )
        XCTAssertEqual(ctx.filePath, "/Users/test/Project/File.swift")
        XCTAssertEqual(ctx.fileName, "File.swift")
        XCTAssertEqual(ctx.startLine, 10)
        XCTAssertEqual(ctx.endLine, 20)
        XCTAssertEqual(ctx.selectedText, "func test() {}")
    }

    func test_selectionContext_summary() {
        let ctx = XcodeSelectionContext(
            filePath: "/path/to/File.swift",
            fileName: "File.swift",
            startLine: 5,
            endLine: 15,
            selectedText: "code"
        )
        XCTAssertEqual(ctx.summary, "File.swift · lines 5-15")
    }

    func test_selectionContext_singleLine_summary() {
        let ctx = XcodeSelectionContext(
            filePath: "/path/to/File.swift",
            fileName: "File.swift",
            startLine: 42,
            endLine: 42,
            selectedText: "let x = 1"
        )
        XCTAssertEqual(ctx.summary, "File.swift · lines 42-42")
    }

    func test_selectionContext_systemPrompt_containsInfo() {
        let ctx = XcodeSelectionContext(
            filePath: "/project/Source.swift",
            fileName: "Source.swift",
            startLine: 1,
            endLine: 3,
            selectedText: "import SwiftUI"
        )
        let prompt = ctx.systemPrompt
        XCTAssertTrue(prompt.contains("Source.swift"))
        XCTAssertTrue(prompt.contains("/project/Source.swift"))
        XCTAssertTrue(prompt.contains("lines 1-3"))
        XCTAssertTrue(prompt.contains("import SwiftUI"))
        XCTAssertTrue(prompt.contains("code block"))
    }

    func test_selectionContext_systemPrompt_mentionsAutoReplace() {
        let ctx = XcodeSelectionContext(
            filePath: "/a.swift", fileName: "a.swift",
            startLine: 1, endLine: 1, selectedText: ""
        )
        let prompt = ctx.systemPrompt
        XCTAssertTrue(prompt.contains("replace the selection"))
        XCTAssertTrue(prompt.contains("automatically"))
    }
}

final class XcodeProjectInfoTests: XCTestCase {

    func test_projectInfo_init() {
        let info = XcodeProjectInfo(
            projectPath: "/path/Project.xcodeproj",
            projectName: "MyProject",
            schemes: ["Debug", "Release"],
            targets: ["App", "Tests"],
            activeScheme: "Debug"
        )
        XCTAssertEqual(info.projectName, "MyProject")
        XCTAssertEqual(info.schemes, ["Debug", "Release"])
        XCTAssertEqual(info.activeScheme, "Debug")
    }

    func test_projectInfo_summary_withActiveScheme() {
        let info = XcodeProjectInfo(
            projectPath: "/p.xcodeproj",
            projectName: "App",
            schemes: ["App", "AppTests"],
            targets: ["App"],
            activeScheme: "App"
        )
        let summary = info.summary
        XCTAssertTrue(summary.contains("App"))
        XCTAssertTrue(summary.contains("App, AppTests"))
        XCTAssertTrue(summary.contains("Active: App"))
    }

    func test_projectInfo_summary_nilActiveScheme() {
        let info = XcodeProjectInfo(
            projectPath: "/p.xcodeproj",
            projectName: "TestApp",
            schemes: ["TestApp"],
            targets: ["TestApp"],
            activeScheme: nil
        )
        let summary = info.summary
        XCTAssertTrue(summary.contains("TestApp"))
        XCTAssertFalse(summary.contains("Active:"))
    }

    func test_projectInfo_noSchemes() {
        let info = XcodeProjectInfo(
            projectPath: "/p.xcodeproj",
            projectName: "Empty",
            schemes: [],
            targets: [],
            activeScheme: nil
        )
        XCTAssertTrue(info.summary.contains("Empty"))
    }
}

final class XcodeBuildDelegateTests: XCTestCase {

    // Test that the protocol compiles and can be implemented
    func test_buildDelegate_protocol() {
        class MockDelegate: XcodeBuildDelegate {
            var outputs: [String] = []
            var exitCode: Int32?

            func buildOutputReceived(_ line: String) {
                outputs.append(line)
            }

            func buildFinished(exitCode: Int32) {
                self.exitCode = exitCode
            }
        }

        let delegate = MockDelegate()
        delegate.buildOutputReceived("Build started")
        delegate.buildOutputReceived("Compiling File.swift")
        delegate.buildFinished(exitCode: 0)

        XCTAssertEqual(delegate.outputs, ["Build started", "Compiling File.swift"])
        XCTAssertEqual(delegate.exitCode, 0)
    }

    func test_buildDelegate_failureExitCode() {
        class MockDelegate: XcodeBuildDelegate {
            var exitCode: Int32?

            func buildOutputReceived(_ line: String) {}
            func buildFinished(exitCode: Int32) {
                self.exitCode = exitCode
            }
        }

        let delegate = MockDelegate()
        delegate.buildFinished(exitCode: 1)
        XCTAssertEqual(delegate.exitCode, 1)
    }
}
