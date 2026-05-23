import Foundation
import SwiftUI

// MARK: - Agent Tab Model

struct AgentTab: Identifiable, Codable {
    let id: UUID
    var name: String
    var roleDescription: String
    var messages: [StoredMessage]
    var inputText: String

    // MARK: Agent Profile (specialization)

    var template: AgentTemplate
    var systemPrompt: String
    var permissions: AgentPermissions

    init(
        id: UUID = UUID(),
        name: String,
        roleDescription: String = "",
        template: AgentTemplate = .custom,
        systemPrompt: String = "",
        permissions: AgentPermissions = .all
    ) {
        self.id = id
        self.name = name
        self.roleDescription = roleDescription
        self.messages = []
        self.inputText = ""
        self.template = template
        self.systemPrompt = systemPrompt
        self.permissions = permissions
    }

    /// Apply a full AgentProfile to this tab
    mutating func applyProfile(_ profile: AgentProfile) {
        name = profile.name
        template = profile.template
        roleDescription = profile.role
        systemPrompt = profile.systemPrompt
        permissions = profile.permissions
    }

    /// Build a profile snapshot from current tab state
    var profile: AgentProfile {
        AgentProfile(
            id: id,
            name: name,
            template: template,
            role: roleDescription,
            systemPrompt: systemPrompt,
            permissions: permissions
        )
    }

    /// The effective system message sent with each request
    var effectiveSystemMessage: String {
        if !systemPrompt.isEmpty { return systemPrompt }
        if !roleDescription.isEmpty { return roleDescription }
        return ""
    }

    /// Human-readable permission summary for display
    var permissionSummary: String {
        var parts: [String] = []
        if permissions.readFile   { parts.append("read") }
        if permissions.writeCode  { parts.append("write") }
        if permissions.build      { parts.append("build") }
        if permissions.test       { parts.append("test") }
        if permissions.analyze    { parts.append("analyze") }
        if permissions.commit     { parts.append("commit") }
        if permissions.structure  { parts.append("structure") }
        if permissions.note       { parts.append("note") }
        return parts.joined(separator: ", ")
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
