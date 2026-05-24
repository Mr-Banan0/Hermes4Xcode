@testable import HermesXcode
import XCTest

final class AgentTabTests: XCTestCase {

    func test_tab_init_defaults() {
        let tab = AgentTab(name: "TestTab")
        XCTAssertEqual(tab.name, "TestTab")
        XCTAssertTrue(tab.messages.isEmpty)
        XCTAssertTrue(tab.inputText.isEmpty)
        XCTAssertEqual(tab.template, .custom)
        XCTAssertEqual(tab.roleDescription, "")
        XCTAssertEqual(tab.systemPrompt, "")
        XCTAssertEqual(tab.permissions, .all)
    }

    func test_tab_init_withAllParameters() {
        let tab = AgentTab(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "CustomTab",
            roleDescription: "Custom role",
            template: .techLead,
            systemPrompt: "Custom system prompt",
            permissions: .all
        )
        XCTAssertEqual(tab.id.uuidString, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(tab.name, "CustomTab")
        XCTAssertEqual(tab.roleDescription, "Custom role")
        XCTAssertEqual(tab.template, .techLead)
        XCTAssertEqual(tab.systemPrompt, "Custom system prompt")
        XCTAssertEqual(tab.permissions, .all)
    }

    func test_tab_applyProfile_updatesAllFields() {
        var tab = AgentTab(name: "OldName")
        let profile = AgentProfile(
            name: "NewName",
            template: .qaEngineer,
            role: "New role",
            systemPrompt: "New prompt",
            permissions: .testOnly
        )
        tab.applyProfile(profile)
        XCTAssertEqual(tab.name, "NewName")
        XCTAssertEqual(tab.template, .qaEngineer)
        XCTAssertEqual(tab.roleDescription, "New role")
        XCTAssertEqual(tab.systemPrompt, "New prompt")
        XCTAssertEqual(tab.permissions, .testOnly)
    }

    func test_tab_profile_snapshotMatches() {
        let tab = AgentTab(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "ProfileTest",
            roleDescription: "Role",
            template: .documenter,
            systemPrompt: "Prompt",
            permissions: .docOnly
        )
        let profile = tab.profile
        XCTAssertEqual(profile.id, tab.id)
        XCTAssertEqual(profile.name, "ProfileTest")
        XCTAssertEqual(profile.template, .documenter)
        XCTAssertEqual(profile.role, "Role")
        XCTAssertEqual(profile.systemPrompt, "Prompt")
        XCTAssertEqual(profile.permissions, .docOnly)
    }

    func test_tab_effectiveSystemMessage_usesPromptFirst() {
        let tab = AgentTab(
            name: "Test",
            roleDescription: "Role desc",
            template: .custom,
            systemPrompt: "Explicit prompt",
            permissions: .all
        )
        XCTAssertEqual(tab.effectiveSystemMessage, "Explicit prompt")
    }

    func test_tab_effectiveSystemMessage_fallsBackToRole() {
        let tab = AgentTab(
            name: "Test",
            roleDescription: "Role only",
            template: .custom,
            systemPrompt: "",
            permissions: .all
        )
        XCTAssertEqual(tab.effectiveSystemMessage, "Role only")
    }

    func test_tab_effectiveSystemMessage_emptyWhenBothEmpty() {
        let tab = AgentTab(name: "Test")
        XCTAssertTrue(tab.effectiveSystemMessage.isEmpty)
    }

    func test_tab_permissionSummary_all() {
        let tab = AgentTab(name: "Test", permissions: .all)
        let summary = tab.permissionSummary
        XCTAssertTrue(summary.contains("read"))
        XCTAssertTrue(summary.contains("write"))
        XCTAssertTrue(summary.contains("build"))
        XCTAssertTrue(summary.contains("test"))
        XCTAssertTrue(summary.contains("analyze"))
        XCTAssertTrue(summary.contains("commit"))
        XCTAssertTrue(summary.contains("structure"))
        XCTAssertTrue(summary.contains("note"))
    }

    func test_tab_permissionSummary_readOnly() {
        let tab = AgentTab(name: "Test", permissions: .readOnly)
        let summary = tab.permissionSummary
        XCTAssertTrue(summary.contains("read"))
        XCTAssertTrue(summary.contains("analyze"))
        XCTAssertTrue(summary.contains("structure"))
        XCTAssertFalse(summary.contains("write"))
        XCTAssertFalse(summary.contains("build"))
    }

    func test_tab_codable_roundTrip() throws {
        let tab = AgentTab(name: "CodableTab", template: .supervisor)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(tab)
        let decoded = try decoder.decode(AgentTab.self, from: data)
        XCTAssertEqual(decoded.name, "CodableTab")
        XCTAssertEqual(decoded.template, .supervisor)
    }
}

final class StoredMessageTests: XCTestCase {

    func test_storedMessage_init() {
        let msg = StoredMessage(role: "user", text: "Hello")
        XCTAssertEqual(msg.role, "user")
        XCTAssertEqual(msg.text, "Hello")
    }

    func test_storedMessage_asStructured() {
        let msg = StoredMessage(role: "assistant", text: "Hi there")
        let structured = msg.asStructured
        XCTAssertEqual(structured.role, "assistant")
        XCTAssertEqual(structured.rawText, "Hi there")
        XCTAssertEqual(structured.segments.count, 1)
        if case .text(let t) = structured.segments[0] {
            XCTAssertEqual(t, "Hi there")
        } else {
            XCTFail("Expected .text segment")
        }
    }

    func test_storedMessage_codable_roundTrip() throws {
        let msg = StoredMessage(role: "user", text: "Can you review this code?")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(StoredMessage.self, from: data)
        XCTAssertEqual(decoded.role, msg.role)
        XCTAssertEqual(decoded.text, msg.text)
    }
}
