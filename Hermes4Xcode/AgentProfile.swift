import Foundation

// MARK: - Agent Permissions

/// 细粒度的工具权限控制。8 个 bool 直接绑定 UI toggle。
struct AgentPermissions: Codable, Equatable {
    var readFile: Bool = true
    var writeCode: Bool = true
    var build: Bool = true
    var test: Bool = true
    var analyze: Bool = true
    var commit: Bool = true
    var structure: Bool = true
    var note: Bool = true

    static let all = Self()

    static let docOnly = Self(
        readFile: true, writeCode: false, build: false, test: false,
        analyze: false, commit: false, structure: true, note: true
    )

    /// Reviewer 权限：读 + 构建 + 分析 + 结构 + 笔记
    static let reviewer = Self(
        readFile: true, writeCode: false, build: true, test: false,
        analyze: true, commit: false, structure: true, note: true
    )
}

// MARK: - Agent Template

/// 内置 agent 角色模板
enum AgentTemplate: String, Codable, CaseIterable, Identifiable {
    case supervisor = "supervisor"
    case developer = "developer"
    case documenter = "documenter"
    case reviewer = "reviewer"
    case custom = "custom"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .supervisor: return "Supervisor"
        case .developer: return "Developer"
        case .documenter: return "Documenter"
        case .reviewer:  return "Reviewer"
        case .custom:    return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .supervisor: return "star.fill"
        case .developer: return "hammer.fill"
        case .documenter: return "doc.text.fill"
        case .reviewer:  return "eyeglasses"
        case .custom:    return "person.fill"
        }
    }

    var defaultRole: String {
        switch self {
        case .supervisor: return "Supervisor — orchestrates all development tasks"
        case .developer: return "Full-Stack iOS/macOS Developer"
        case .documenter: return "Documentation Specialist"
        case .reviewer:  return "Reviewer — code review, architecture, design, testing, specs"
        case .custom:    return "Custom Agent"
        }
    }

    var defaultPrompt: String {
        switch self {
        case .supervisor:
            return """
You are the **Supervisor Agent** for an Xcode project. You oversee tasks and delegate when appropriate.

Capabilities:
- Read/understand Swift code, build & test, refactor & generate code
- SourceKit-LSP analysis, git commits, cross-session project notes
- Delegate to specialized agents (Developer, Reviewer, Documenter)

**Workflow:**
1. Analyze the request, break into sub-tasks
2. `[delegate to developer]` — Developer implements + builds
3. After delegation, agents auto-route between themselves:
   Developer → Reviewer → Documenter (or back to Developer if fixes needed)
4. You only get involved again if:
   - A new request comes in
   - The user explicitly asks for your input
   - Documenter reports back to you for final summary

You DO NOT write code yourself. You plan, delegate, and decide initial direction.

Refer to `CODING_STANDARDS.md` for safety rules and project conventions before delegating.
"""
        case .developer:
            return """
You are a **Full-Stack iOS/macOS Developer**. Write clean, maintainable Swift code following Apple's best practices.

Guidelines:
- Prefer value types (structs) unless you need reference semantics
- Use SwiftUI native patterns: @State, @Binding, @ObservableObject
- Handle errors with proper types, not force-unwrapping
- Write doc comments for public APIs
- Build after every logical change — only move on when BUILD SUCCEEDED

Refer to `CODING_STANDARDS.md` for safety rules and project conventions before editing.
"""
        case .documenter:
            return """
You are a **Documentation Specialist**. Create clear docs that explain WHAT, WHY, and HOW.

Guidelines:
- Use Apple's documentation comment format (///)
- Cover setup, architecture, usage examples
- Document build config and project structure
- Save notes for cross-session memory

Read-only permissions: you can read files, view structure, and save notes.
"""
        case .reviewer:
            return """
You are a **Reviewer**. Your role depends on the `Role Description` set for this tab.

General guidelines:
- Read the file before reviewing it
- Structure feedback with ✅ what's good / ⚠️ issues / 📋 summary
- Prefer `patch` over `write_file` for suggesting changes to existing files

**Functional Simulation (mandatory on every review):**
After reviewing the code, you MUST simulate the feature's behavior:
1. Trace the user interaction flow: what happens when a button is tapped? input is entered? a signal arrives?
2. Check state transitions: does isLoading toggle correctly? does the UI reflect error states?
3. Verify data flow: does ViewModel → Model → API chain look correct? Are edge cases handled (empty state, network failure, invalid input)?
4. Note any missing states: loading indicators, error handling, empty views, keyboard handling

Report simulation results explicitly:
- ✅ Simulation passed — all interaction paths verified → use `[report back]` (auto-routes to Documenter)
- ❌ Simulation failed — describe exactly which path broke and what should change → use `[report back]` (auto-routes to Developer for fixes)
"""
        case .custom:
            return ""
        }
    }

    var defaultPermissions: AgentPermissions {
        switch self {
        case .supervisor: return .all
        case .developer: return .all
        case .documenter: return .docOnly
        case .reviewer:  return .reviewer
        case .custom:    return .all
        }
    }
}

// MARK: - Agent Profile (the active config attached to each tab)

struct AgentProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var template: AgentTemplate
    var role: String
    var systemPrompt: String
    var permissions: AgentPermissions

    init(
        id: UUID = UUID(),
        name: String,
        template: AgentTemplate = .custom,
        role: String? = nil,
        systemPrompt: String? = nil,
        permissions: AgentPermissions? = nil
    ) {
        self.id = id
        self.name = name
        self.template = template
        self.role = role ?? template.defaultRole
        self.systemPrompt = systemPrompt ?? template.defaultPrompt
        self.permissions = permissions ?? template.defaultPermissions
    }

    /// Reset profile to template defaults
    mutating func resetToTemplate() {
        role = template.defaultRole
        systemPrompt = template.defaultPrompt
        permissions = template.defaultPermissions
    }
}
