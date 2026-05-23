@testable import HermesXcode
import XCTest

final class ExecutionModeTests: XCTestCase {

    func test_allCases_count() {
        XCTAssertEqual(ExecutionMode.allCases.count, 2)
    }

    func test_labels_areCorrect() {
        XCTAssertEqual(ExecutionMode.chat.label, "Chat")
        XCTAssertEqual(ExecutionMode.plan.label, "Plan ⟳ ReAct")
    }

    func test_shortLabels_areCorrect() {
        XCTAssertEqual(ExecutionMode.chat.shortLabel, "Chat")
        XCTAssertEqual(ExecutionMode.plan.shortLabel, "Plan")
    }

    func test_icons_areCorrect() {
        XCTAssertEqual(ExecutionMode.chat.icon, "message.fill")
        XCTAssertEqual(ExecutionMode.plan.icon, "list.clipboard.fill")
    }

    func test_systemInstruction_chat_returnsEmpty() {
        XCTAssertTrue(ExecutionMode.chat.systemInstruction.isEmpty)
    }

    func test_systemInstruction_plan_containsPlanMode() {
        let instruction = ExecutionMode.plan.systemInstruction
        XCTAssertTrue(instruction.contains("[PLAN MODE]"))
        XCTAssertTrue(instruction.contains("Plan & ReAct"))
        XCTAssertTrue(instruction.contains("DO NOT"))
        XCTAssertTrue(instruction.contains("execute"))
    }

    func test_systemInstruction_plan_containsAllPhases() {
        let instruction = ExecutionMode.plan.systemInstruction
        XCTAssertTrue(instruction.contains("ANALYZE"))
        XCTAssertTrue(instruction.contains("CREATE"))
        XCTAssertTrue(instruction.contains("PRESENT"))
        XCTAssertTrue(instruction.contains("WAIT"))
    }

    func test_rawValues_matchEnum() {
        XCTAssertEqual(ExecutionMode(rawValue: "chat"), .chat)
        XCTAssertEqual(ExecutionMode(rawValue: "plan"), .plan)
        XCTAssertNil(ExecutionMode(rawValue: "invalid"))
    }

    func test_codable_roundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for mode in ExecutionMode.allCases {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(ExecutionMode.self, from: data)
            XCTAssertEqual(mode, decoded)
        }
    }
}
