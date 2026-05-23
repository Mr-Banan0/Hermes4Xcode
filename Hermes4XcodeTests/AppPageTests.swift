import XCTest
@testable import HermesXcode

final class AppPageTests: XCTestCase {

    func test_allCases_count() {
        XCTAssertEqual(AppPage.allCases.count, 3)
    }

    func test_rawValues() {
        XCTAssertEqual(AppPage.chat.rawValue, "chat")
        XCTAssertEqual(AppPage.cron.rawValue, "cron")
        XCTAssertEqual(AppPage.provider.rawValue, "provider")
    }

    func test_ids_matchRawValues() {
        for page in AppPage.allCases {
            XCTAssertEqual(page.id, page.rawValue)
        }
    }

    func test_icons() {
        XCTAssertEqual(AppPage.chat.icon, "message.fill")
        XCTAssertEqual(AppPage.cron.icon, "clock.arrow.circlepath")
        XCTAssertEqual(AppPage.provider.icon, "gear")
    }

    func test_labels() {
        XCTAssertEqual(AppPage.chat.label, "Chat")
        XCTAssertEqual(AppPage.cron.label, "Scheduled Tasks")
        XCTAssertEqual(AppPage.provider.label, "Provider")
    }
}
