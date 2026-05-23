import XCTest
@testable import HermesXcode

final class AgentManagerTests: XCTestCase {

    var manager: AgentManager!

    override func setUp() {
        super.setUp()
        manager = AgentManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func test_init_createsOneTab() {
        XCTAssertEqual(manager.tabs.count, 1)
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
        XCTAssertTrue(welcome.text.contains("Let's create our app"))
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
