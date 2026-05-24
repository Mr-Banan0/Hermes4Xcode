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

    func test_permissions_readOnly_correct() {
        let p = AgentPermissions.readOnly
        XCTAssertTrue(p.readFile)
        XCTAssertTrue(p.analyze)
        XCTAssertTrue(p.structure)
        XCTAssertFalse(p.writeCode)
        XCTAssertFalse(p.build)
        XCTAssertFalse(p.test)
        XCTAssertFalse(p.commit)
        XCTAssertFalse(p.note)
    }

    func test_permissions_testOnly_correct() {
        let p = AgentPermissions.testOnly
        XCTAssertTrue(p.readFile)
        XCTAssertTrue(p.writeCode)
        XCTAssertTrue(p.build)
        XCTAssertTrue(p.test)
        XCTAssertTrue(p.analyze)
        XCTAssertFalse(p.commit)
        XCTAssertFalse(p.structure)
        XCTAssertFalse(p.note)
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

    func test_permissions_equality() {
        let a = AgentPermissions.all
        let b = AgentPermissions.all
        XCTAssertEqual(a, b)
    }

    func test_permissions_inequality() {
        XCTAssertNotEqual(AgentPermissions.all, AgentPermissions.readOnly)
    }

    func test_permissions_codable_roundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let permissions: [AgentPermissions] = [.all, .readOnly, .testOnly, .docOnly]

        for p in permissions {
            let data = try encoder.encode(p)
            let decoded = try decoder.decode(AgentPermissions.self, from: data)
            XCTAssertEqual(p, decoded)
        }
    }
}

final class AgentTemplateTests: XCTestCase {

    func test_allCases_count() {
        XCTAssertEqual(AgentTemplate.allCases.count, 8)
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

    func test_techLead_defaultPermissions() {
        XCTAssertEqual(AgentTemplate.techLead.defaultPermissions.readFile, true)
        XCTAssertEqual(AgentTemplate.techLead.defaultPermissions.writeCode, true)
        XCTAssertEqual(AgentTemplate.techLead.defaultPermissions.build, true)
        XCTAssertEqual(AgentTemplate.techLead.defaultPermissions.test, false)
        XCTAssertEqual(AgentTemplate.techLead.defaultPermissions.analyze, true)
        XCTAssertEqual(AgentTemplate.techLead.defaultPermissions.commit, false)
        XCTAssertEqual(AgentTemplate.techLead.defaultPermissions.structure, true)
        XCTAssertEqual(AgentTemplate.techLead.defaultPermissions.note, true)
    }

    func test_qaEngineer_defaultPermissions_testOnly() {
        XCTAssertEqual(AgentTemplate.qaEngineer.defaultPermissions, .testOnly)
    }

    func test_documenter_defaultPermissions_docOnly() {
        XCTAssertEqual(AgentTemplate.documenter.defaultPermissions, .docOnly)
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
        XCTAssertTrue(prompt.contains("supervisor agent"))
        XCTAssertTrue(prompt.contains("Read and understand Swift code"))
        XCTAssertTrue(prompt.contains("Build and test"))
        XCTAssertTrue(prompt.contains("SourceKit-LSP"))
    }

    func test_techLead_defaultPrompt_containsGuidelines() {
        let prompt = AgentTemplate.techLead.defaultPrompt
        XCTAssertTrue(prompt.contains("Tech Lead"))
        XCTAssertTrue(prompt.contains("architecture"))
        XCTAssertTrue(prompt.contains("code quality"))
        XCTAssertTrue(prompt.contains("Swift API Design Guidelines"))
    }

    func test_qaEngineer_defaultPrompt_containsTestingGuidelines() {
        let prompt = AgentTemplate.qaEngineer.defaultPrompt
        XCTAssertTrue(prompt.contains("QA Engineer"))
        XCTAssertTrue(prompt.contains("XCTest"))
        XCTAssertTrue(prompt.contains("Arrange-Act-Assert"))
    }

    func test_developer_defaultPrompt_containsBestPractices() {
        let prompt = AgentTemplate.developer.defaultPrompt
        XCTAssertTrue(prompt.contains("Swift API Design Guidelines"))
        XCTAssertTrue(prompt.contains("@State"))
        XCTAssertTrue(prompt.contains("value types"))
    }

    func test_documenter_defaultPrompt_containsDocGuidelines() {
        let prompt = AgentTemplate.documenter.defaultPrompt
        XCTAssertTrue(prompt.contains("Documentation Specialist"))
        XCTAssertTrue(prompt.contains("WHAT, WHY, and HOW"))
        XCTAssertTrue(prompt.contains("///"))
    }
}

final class AgentProfileTests: XCTestCase {

    func test_profile_init_withDefaults() {
        let profile = AgentProfile(name: "TestAgent", template: .qaEngineer)
        XCTAssertEqual(profile.name, "TestAgent")
        XCTAssertEqual(profile.template, .qaEngineer)
        XCTAssertEqual(profile.role, AgentTemplate.qaEngineer.defaultRole)
        XCTAssertEqual(profile.systemPrompt, AgentTemplate.qaEngineer.defaultPrompt)
        XCTAssertEqual(profile.permissions, AgentTemplate.qaEngineer.defaultPermissions)
    }

    func test_profile_init_withOverrides() {
        let profile = AgentProfile(
            name: "CustomAgent",
            template: .supervisor,
            role: "Custom Role",
            systemPrompt: "Custom Prompt",
            permissions: .readOnly
        )
        XCTAssertEqual(profile.name, "CustomAgent")
        XCTAssertEqual(profile.template, .supervisor)
        XCTAssertEqual(profile.role, "Custom Role")
        XCTAssertEqual(profile.systemPrompt, "Custom Prompt")
        XCTAssertEqual(profile.permissions, .readOnly)
    }

    func test_profile_resetToTemplate_restoresDefaults() {
        var profile = AgentProfile(
            name: "Modified",
            template: .techLead,
            role: "Changed Role",
            systemPrompt: "Changed Prompt",
            permissions: .all
        )
        profile.resetToTemplate()
        XCTAssertEqual(profile.role, AgentTemplate.techLead.defaultRole)
        XCTAssertEqual(profile.systemPrompt, AgentTemplate.techLead.defaultPrompt)
        XCTAssertEqual(profile.permissions, AgentTemplate.techLead.defaultPermissions)
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
