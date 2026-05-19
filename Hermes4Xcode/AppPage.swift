import SwiftUI

enum AppPage: String, CaseIterable, Identifiable {
    case chat = "chat"
    case cron = "cron"
    case provider = "provider"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chat: return "message.fill"
        case .cron: return "clock.arrow.circlepath"
        case .provider: return "gear"
        }
    }

    var label: String {
        switch self {
        case .chat: return "Chat"
        case .cron: return "Scheduled Tasks"
        case .provider: return "Provider"
        }
    }
}
