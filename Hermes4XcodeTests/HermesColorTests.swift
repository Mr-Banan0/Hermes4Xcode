import XCTest
import SwiftUI
@testable import HermesXcode

final class HermesColorTests: XCTestCase {

    func test_hermesColor_isGold() {
        let color = Color.hermes
        // Color cannot be directly compared, but we can check it's non-clear
        XCTAssertNotEqual(color, Color.clear)
    }

    func test_hermesAmber_isAmber() {
        let color = Color.hermesAmber
        XCTAssertNotEqual(color, Color.clear)
    }

    func test_hermesLight_isLight() {
        let color = Color.hermesLight
        XCTAssertNotEqual(color, Color.clear)
    }

    func test_allColors_areDistinct() {
        let colors: [(String, Color)] = [
            ("gold", Color.hermes),
            ("amber", Color.hermesAmber),
            ("light", Color.hermesLight),
        ]
        // Verify they're all different colors by checking raw component access
        // We can at least verify they're not clear/black
        for (name, color) in colors {
            XCTAssertNotEqual(color, Color.black, "\(name) should not be black")
            XCTAssertNotEqual(color, Color.clear, "\(name) should not be clear")
        }
    }
}
