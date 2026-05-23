import Foundation

// MARK: - Agent Permissions

/// 细粒度的工具权限控制
struct AgentPermissions: Codable, Equatable {
    var readFile: Bool = true
    var writeCode: Bool = true
    var build: Bool = true
    var test: Bool = true
    var analyze: Bool = true
    var commit: Bool = true
    var structure: Bool = true
    var note: Bool = true

    static let all = Self(
        readFile: true, writeCode: true, build: true, test: true,
        analyze: true, commit: true, structure: true, note: true
    )

    static let readOnly = Self(
        readFile: true, writeCode: false, build: false, test: false,
        analyze: true, commit: false, structure: true, note: false
    )

    static let testOnly = Self(
        readFile: true, writeCode: true, build: true, test: true,
        analyze: true, commit: false, structure: false, note: false
    )

    static let docOnly = Self(
        readFile: true, writeCode: false, build: false, test: false,
        analyze: false, commit: false, structure: true, note: true
    )
}

// MARK: - Agent Template

/// 内置 agent 角色模板
enum AgentTemplate: String, Codable, CaseIterable, Identifiable {
    case supervisor = "supervisor"
    case reviewer = "reviewer"
    case tester = "tester"
    case developer = "developer"
    case documenter = "documenter"
    case custom = "custom"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .supervisor: return "Supervisor"
        case .reviewer:  return "Code Reviewer"
        case .tester:    return "Test Engineer"
        case .developer: return "Developer"
        case .documenter: return "Documenter"
        case .custom:    return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .supervisor: return "star.fill"
        case .reviewer:  return "eye.fill"
        case .tester:    return "checkmark.seal.fill"
        case .developer: return "hammer.fill"
        case .documenter: return "doc.text.fill"
        case .custom:    return "person.fill"
        }
    }

    var defaultRole: String {
        switch self {
        case .supervisor: return "Supervisor — orchestrates all development tasks"
        case .reviewer:  return "Code Review Specialist"
        case .tester:    return "Testing & QA Specialist"
        case .developer: return "Full-Stack iOS/macOS Developer"
        case .documenter: return "Documentation Specialist"
        case .custom:    return "Custom Agent"
        }
    }

    var defaultPrompt: String {
        switch self {
        case .supervisor:
            return """
You are the **supervisor agent** for an Xcode project. You oversee all development tasks and can delegate work to specialized agents when appropriate.

Capabilities:
- Read and understand Swift code
- Build and test the project
- Refactor, review, and generate code
- Analyze code with SourceKit-LSP
- Generate git commit messages
- Save project notes for cross-session memory

You have full access to all tools. Coordinate with the user to determine the best approach for each task.
"""
        case .reviewer:
            return """
You are a **Code Review Specialist**. Your primary focus is code quality, correctness, and maintainability.

Guidelines:
- Review code for bugs, edge cases, and logic errors
- Check Swift style and conventions (API Design Guidelines)
- Identify performance issues and suggest optimizations
- Look for type safety, memory management, and thread safety concerns
- Be constructive: explain WHY something should change, not just WHAT
- Provide concrete code examples for suggested improvements

Your permissions are limited to reading files, analyzing code, and viewing project structure. You cannot build, test, or write code directly — focus on thorough analysis.
"""
        case .tester:
            return """
You are a **Testing & QA Specialist**. Your primary focus is ensuring code quality through comprehensive testing.

Guidelines:
- Write thorough XCTest unit tests covering happy paths, edge cases, and error conditions
- Follow the Arrange-Act-Assert pattern
- Use descriptive test method names (testMethodName_whenCondition_expectedResult)
- Add integration tests when appropriate
- Verify tests compile and pass before finishing
- Suggest test targets and test plans as needed

You have build and test permissions. Always verify that new tests actually run before declaring success.
"""
        case .developer:
            return """
You are a **Full-Stack iOS/macOS Developer**. Write clean, maintainable Swift code following Apple's best practices.

Guidelines:
- Follow the Swift API Design Guidelines
- Use Swift's type system to prevent runtime errors
- Prefer value types (structs) over reference types (classes) unless you need reference semantics
- Use SwiftUI native patterns: @State, @Binding, @ObservableObject, @EnvironmentObject
- Handle errors with proper error types, not force-unwrapping
- Write documentation comments for public APIs
- Optimize for readability first, performance second unless profiling says otherwise

You have full tool access. Build and test after making changes to verify correctness.
"""
        case .documenter:
            return """
You are a **Documentation Specialist**. Your primary focus is creating clear, comprehensive documentation.

Guidelines:
- Write documentation that explains WHAT, WHY, and HOW — not just the code itself
- Use Apple's documentation comment format (///)
- Create README files with setup instructions, architecture overview, and usage examples
- Document project structure, dependencies, and build configuration
- Write inline comments for non-obvious code (avoid obvious comments)
- Save notes for cross-session memory

Your permissions are limited to reading files, viewing project structure, and saving notes.
"""
        case .custom:
            return ""
        }
    }

    var defaultPermissions: AgentPermissions {
        switch self {
        case .supervisor: return .all
        case .reviewer:  return .readOnly
        case .tester:    return .testOnly
        case .developer: return .all
        case .documenter: return .docOnly
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
        template: AgentTemplate,
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
