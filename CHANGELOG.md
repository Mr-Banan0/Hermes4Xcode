# Changelog

All notable changes to Hermes4Xcode will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] — 2026-07-02

### Added

- **Build result tracking**: `BuildResult` model + `lastBuildResults[tabId]` caching
- **Auto history injection**: build exit code + output automatically appended to next LLM request
- **Report-back protocol**: `checkForReportBack()` detects `[report to supervisor]` / `[report back]` and auto-routes
- **Workflow phase tracking**: `WorkflowPhase` enum auto-advances on delegate/report events
- **XcodeContext build output buffer**: accumulates stdout/stderr during async build via onBuildComplete callback
- **Supervisor welcome text**: documents Agent Protocol for delegation and report-back

## [0.3.0] — 2026-06-28

### Changed

- **Agent permissions**: tightened writeCode for non-Developer roles
  - `testOnly` (used by QA Engineer): writeCode `true` → `false`
  - `uiDesigner`: writeCode `true` → `false`
  - `techLead`: writeCode `true` → `false`
  - Only `supervisor`, `developer`, and `custom` retain write access,
    eliminating file conflict risk in multi-agent delegation flow

## [0.2.0] — 2026-05-24

### Added

- **Unit test suite**: 104 XCTest covering MessageParser, AgentManager, AgentProfile,
  AgentTab, ExecutionMode, AppPage, XcodeContext, and HermesColor modules
- **GitHub Actions CI**: automated build + test on every push/PR on macOS 15 + Xcode 26
- **SwiftLint configuration**: code quality enforcement with 0-violation baseline
- **ExecutionMode**: Plan & ReAct workflow mode with system prompt injection
- **AgentProfile system**: customizable agent roles with permissions (readOnly, testOnly, docOnly, all)
- **Multi-agent tab support**: TabBarView, SidebarView, dynamic agent creation from conversation
- **Cron settings page**: scheduled task configuration UI
- **Provider settings page**: model provider configuration UI
- **`.gitignore`**: added `.xcodebuildmcp/` exclusion

### Changed

- **HermesXcodeApp.swift**: refactored sidebar with collapsible toggle and drag handle
- **XcodeContext**: improved AppleScript integration and error handling
- **AgentManager**: moved to ObservableObject with mode and profile state management
- **MessageParser**: changed from struct to enum (convenience type)

## [0.1.0] — 2026-05-18

### Added

- **Initial release**: macOS companion app for Xcode
- **Chat panel**: SSE streaming integration with Hermes Gateway (port 8642)
- **Xcode selection detection**: AppleScript-based code context extraction
- **Auto-replace**: agent code blocks automatically replace selected Xcode code
- **Build & Test**: real-time build output log with toolbar buttons
- **Quick actions**: fix errors, generate tests, code review, refactor
- **Project structure scanning**: cross-session memory via SourceKit-LSP
- **SourceKit-LSP integration**: background code analysis on app launch
- **In-Xcode Chat Provider**: Custom Provider integration (Xcode 26+)
- **Dark theme**: Hermes brand colors (#FFD700 gold, #FFBF00 amber)
