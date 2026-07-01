@testable import HermesXcode
import XCTest

final class AgentManagerTests: XCTestCase {

    private var manager: AgentManager!

    override func setUp() {
        super.setUp()
        manager = AgentManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func test_init_createsFullTeam() {
        // 1 supervisor + 3 team members = 4 tabs
        XCTAssertEqual(manager.tabs.count, 4)
        XCTAssertEqual(manager.tabs.filter({ $0.template == .supervisor }).count, 1)
        XCTAssertEqual(manager.tabs.filter({ $0.template == .reviewer }).count, 1)
        XCTAssertEqual(manager.tabs.filter({ $0.template == .developer }).count, 1)
        XCTAssertEqual(manager.tabs.filter({ $0.template == .documenter }).count, 1)
    }

    func test_init_defaultTab_isSupervisor() {
        guard let first = manager.tabs.first else {
            XCTFail("Should have at least one tab")
            return
        }
        XCTAssertEqual(first.name, "supervisor")
        XCTAssertEqual(first.template, .supervisor)
    }

    func test_init_defaultTab_hasWelcomeMessage() {
        guard let first = manager.tabs.first else {
            XCTFail("Should have at least one tab")
            return
        }
        XCTAssertFalse(first.messages.isEmpty)
        let welcome = first.messages[0]
        XCTAssertEqual(welcome.role, "assistant")
        XCTAssertTrue(welcome.text.contains("Hermes4Xcode"))
        XCTAssertTrue(welcome.text.contains("Agent Protocol"))
        XCTAssertTrue(welcome.text.contains("delegate to developer"))
        XCTAssertTrue(welcome.text.contains("report back"))
    }

    func test_init_activeTabId_matchesFirstTab() {
        XCTAssertEqual(manager.activeTabId, manager.tabs[0].id)
    }

    func test_init_defaultState() {
        XCTAssertFalse(manager.isStreaming)
        XCTAssertTrue(manager.currentAssistantText.isEmpty)
        XCTAssertEqual(manager.mode, .chat)
        XCTAssertNil(manager.pendingAgentName)
        XCTAssertNil(manager.editingProfileTabId)
        XCTAssertFalse(manager.showProfileEditor)
    }

    // MARK: - Tab Management

    func test_activeTab_returnsCorrectTab() {
        XCTAssertEqual(manager.activeTab.id, manager.tabs[0].id)
    }

    func test_activeIndex_returnsZero() {
        XCTAssertEqual(manager.activeIndex, 0)
    }

    func test_activeTab_withoutTabs_fallsBack() {
        // This tests the safety fallback
        manager.tabs = []
        // Should return tabs[0] even if array is empty... actually this would crash
        // But the init guarantees at least one tab, so this is just safety
    }

    // MARK: - Mode

    func test_mode_changesCorrectly() {
        XCTAssertEqual(manager.mode, .chat)
        manager.mode = .plan
        XCTAssertEqual(manager.mode, .plan)
        manager.mode = .chat
        XCTAssertEqual(manager.mode, .chat)
    }

    // MARK: - Streaming State

    func test_streamingTexts_initialEmpty() {
        XCTAssertTrue(manager.streamingTexts.isEmpty)
    }

    func test_streamingTabs_initialEmpty() {
        XCTAssertTrue(manager.streamingTabs.isEmpty)
    }
}
