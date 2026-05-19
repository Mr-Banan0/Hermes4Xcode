import Foundation
import SwiftUI

// MARK: - Agent Tab Model

struct AgentTab: Identifiable, Codable {
    let id: UUID
    var name: String
    var roleDescription: String = ""
    var messages: [StoredMessage] = []
    var inputText: String = ""

    init(id: UUID = UUID(), name: String, roleDescription: String = "") {
        self.id = id
        self.name = name
        self.roleDescription = roleDescription
    }
}

/// Codable version of StructuredMessage for persistence.
struct StoredMessage: Identifiable, Codable {
    let id: UUID
    let role: String
    let text: String

    init(id: UUID = UUID(), role: String, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

extension StoredMessage {
    var asStructured: StructuredMessage {
        StructuredMessage(role: role, segments: [.text(text)], rawText: text)
    }
}
