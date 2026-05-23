import XCTest

/// Base test class for Hermes4Xcode unit tests.
/// All test files in this target test the main app module via @testable import.
final class TestSetup: XCTestCase {
    /// Verify the test harness itself is working
    func test_testHarnessWorks() {
        XCTAssertTrue(true, "Test harness should be functional")
    }
}
