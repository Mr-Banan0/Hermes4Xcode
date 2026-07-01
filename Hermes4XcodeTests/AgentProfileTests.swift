@testable import HermesXcode
import XCTest

final class AgentPermissionsTests: XCTestCase {

    func test_permissions_all_defaultsTrue() {
        let p = AgentPermissions.all
        XCTAssertTrue(p.readFile)
        XCTAssertTrue(p.writeCode)
        XCTAssertTrue(p.build)
        XCTAssertTrue(p.test)
        XCTAssertTrue(p.analyze)
        XCTAssertTrue(p.commit)
        XCTAssertTrue(p.structure)
        XCTAssertTrue(p.note)
    }

    func test_permissions_docOnly_correct() {
        let p = AgentPermissions.docOnly
        XCTAssertTrue(p.readFile)
        XCTAssertTrue(p.structure)
        XCTAssertTrue(p.note)
        XCTAssertFalse(p.writeCode)
        XCTAssertFalse(p.build)
        XCTAssertFalse(p.test)
        XCTAssertFalse(p.analyze)
        XCTAssertFalse(p.commit)
    }

    func test_permissions_reviewer_correct() {
        let p = AgentPermissions.reviewer
        XCTAssertTrue(p.readFile)
        XCTAssertTrue(p.writeTests)
        XCTAssertTrue(p.build)
        XCTAssertTrue(p.test)
        XCTAssertTrue(p.analyze)
        XCTAssertTrue(p.structure)
        XCTAssertTrue(p.note)
        XCTAssertFalse(p.writeCode)
        XCTAssertFalse(p.commit)
    }

    func test_permissions_equality() {
        let a = AgentPermissions.all
        let b = AgentPermissions.all
        XCTAssertEqual(a, b)
    }

    func test_permissions_inequality() {
        XCTAssertNotEqual(AgentPermissions.all, AgentPermissions.docOnly)
    }

    func test_permissions_codable_roundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let permissions: [AgentPermissions] = [.all, .docOnly, .reviewer]

        for p in permissions {
            let data = try encoder.encode(p)
            let decoded = try decoder.decode(AgentPermissions.self, from: data)
            XCTAssertEqual(p, decoded)
        }
    }
}

final class AgentTemplateTests: XCTestCase {

    func test_allCases_count() {
        XCTAssertEqual(AgentTemplate.allCases.count, 5)
    }

    func test_ids_matchRawValues() {
        for t in AgentTemplate.allCases {
            XCTAssertEqual(t.id, t.rawValue)
        }
    }

    func test_supervisor_hasCorrectProperties() {
        let t = AgentTemplate.supervisor
        XCTAssertEqual(t.label, "Supervisor")
        XCTAssertEqual(t.icon, "star.fill")
        XCTAssertTrue(t.defaultRole.contains("Supervisor"))
        XCTAssertTrue(t.defaultPermissions == .all)
    }

    func test_developer_hasCorrectProperties() {
        let t = AgentTemplate.developer
        XCTAssertEqual(t.label, "Developer")
        XCTAssertEqual(t.icon, "hammer.fill")
        XCTAssertTrue(t.defaultRole.contains("Developer"))
        XCTAssertTrue(t.defaultPermissions == .all)
    }

    func test_documenter_defaultPermissions_docOnly() {
        XCTAssertEqual(AgentTemplate.documenter.defaultPermissions, .docOnly)
    }

    func test_reviewer_defaultPermissions() {
        XCTAssertEqual(AgentTemplate.reviewer.defaultPermissions, .reviewer)
    }

    func test_reviewer_hasCorrectProperties() {
        let t = AgentTemplate.reviewer
        XCTAssertEqual(t.label, "Reviewer")
        XCTAssertEqual(t.icon, "eyeglasses")
        XCTAssertTrue(t.defaultRole.contains("Reviewer"))
    }

    func test_developer_defaultPermissions_all() {
        XCTAssertEqual(AgentTemplate.developer.defaultPermissions, .all)
    }

    func test_custom_defaultPermissions_all() {
        XCTAssertEqual(AgentTemplate.custom.defaultPermissions, .all)
    }

    func test_custom_defaultRole_andPrompt_empty() {
        XCTAssertTrue(AgentTemplate.custom.defaultRole.contains("Custom"))
        XCTAssertTrue(AgentTemplate.custom.defaultPrompt.isEmpty)
    }

    func test_supervisor_defaultPrompt_containsCapabilities() {
        let prompt = AgentTemplate.supervisor.defaultPrompt
        XCTAssertTrue(prompt.contains("supervisor agent") || prompt.contains("Supervisor Agent"))
        XCTAssertTrue(prompt.contains("Read"))
        XCTAssertTrue(prompt.contains("CODING_STANDARDS.md"))
    }

    func test_developer_defaultPrompt_containsBestPractices() {
        let prompt = AgentTemplate.developer.defaultPrompt
        XCTAssertTrue(prompt.contains("@State"))
        XCTAssertTrue(prompt.contains("value types"))
        XCTAssertTrue(prompt.contains("CODING_STANDARDS.md"))
    }

    func test_documenter_defaultPrompt_containsDocGuidelines() {
        let prompt = AgentTemplate.documenter.defaultPrompt
        XCTAssertTrue(prompt.contains("Documentation Specialist"))
        XCTAssertTrue(prompt.contains("WHAT, WHY, and HOW"))
        XCTAssertTrue(prompt.contains("///"))
    }

    func test_reviewer_defaultPrompt_containsReviewGuidelines() {
        let prompt = AgentTemplate.reviewer.defaultPrompt
        XCTAssertTrue(prompt.contains("Reviewer"))
        XCTAssertTrue(prompt.contains("Functional Simulation"))
        XCTAssertTrue(prompt.contains("Hermes4XcodeTests/"))
        XCTAssertTrue(prompt.contains("XCUITest"))
        XCTAssertTrue(prompt.contains("Simulation passed"))
        XCTAssertTrue(prompt.contains("Simulation failed"))
    }
}

final class AgentProfileTests: XCTestCase {

    func test_profile_init_withDefaults() {
        let profile = AgentProfile(name: "TestAgent", template: .reviewer)
        XCTAssertEqual(profile.name, "TestAgent")
        XCTAssertEqual(profile.template, .reviewer)
        XCTAssertEqual(profile.role, AgentTemplate.reviewer.defaultRole)
        XCTAssertEqual(profile.systemPrompt, AgentTemplate.reviewer.defaultPrompt)
        XCTAssertEqual(profile.permissions, AgentTemplate.reviewer.defaultPermissions)
    }

    func test_profile_init_withOverrides() {
        let profile = AgentProfile(
            name: "CustomAgent",
            template: .supervisor,
            role: "Custom Role",
            systemPrompt: "Custom Prompt",
            permissions: .docOnly
        )
        XCTAssertEqual(profile.name, "CustomAgent")
        XCTAssertEqual(profile.template, .supervisor)
        XCTAssertEqual(profile.role, "Custom Role")
        XCTAssertEqual(profile.systemPrompt, "Custom Prompt")
        XCTAssertEqual(profile.permissions, .docOnly)
    }

    func test_profile_resetToTemplate_restoresDefaults() {
        var profile = AgentProfile(
            name: "Modified",
            template: .reviewer,
            role: "Changed Role",
            systemPrompt: "Changed Prompt",
            permissions: .all
        )
        profile.resetToTemplate()
        XCTAssertEqual(profile.role, AgentTemplate.reviewer.defaultRole)
        XCTAssertEqual(profile.systemPrompt, AgentTemplate.reviewer.defaultPrompt)
        XCTAssertEqual(profile.permissions, AgentTemplate.reviewer.defaultPermissions)
        // Name should NOT be reset
        XCTAssertEqual(profile.name, "Modified")
    }

    func test_profile_codable_roundTrip() throws {
        let profile = AgentProfile(name: "CodableTest", template: .developer)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(profile)
        let decoded = try decoder.decode(AgentProfile.self, from: data)
        XCTAssertEqual(decoded.name, "CodableTest")
        XCTAssertEqual(decoded.template, .developer)
        XCTAssertEqual(decoded.role, profile.role)
        XCTAssertEqual(decoded.systemPrompt, profile.systemPrompt)
        XCTAssertEqual(decoded.permissions, profile.permissions)
    }
}
