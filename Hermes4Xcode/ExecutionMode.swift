import SwiftUI

/// Execution mode for the Plan & ReAct workflow
enum ExecutionMode: String, Codable, CaseIterable {
    /// Normal chat — ReAct loop, no plan required
    case chat = "chat"

    /// Plan mode — agent creates a plan but does NOT execute
    case plan = "plan"

    var label: String {
        switch self {
        case .chat: return "Chat"
        case .plan: return "Plan ⟳ ReAct"
        }
    }

    var shortLabel: String {
        switch self {
        case .chat: return "Chat"
        case .plan: return "Plan"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "message.fill"
        case .plan: return "list.clipboard.fill"
        }

    }

    /// System prompt prefix injected for each mode
    var systemInstruction: String {
        switch self {
        case .chat:
            return ""
        case .plan:
            return """
[PLAN MODE]
You are in PLAN mode. Follow the Plan & ReAct workflow:

1. ANALYZE the user's request
2. CREATE a detailed step-by-step plan with exact file paths and changes
3. PRESENT the plan to the user
4. WAIT for the user to say "execute", "go ahead", "proceed", or similar before taking any action
5. DO NOT edit files, run code, or execute commands during planning

When the user approves, you will switch to EXECUTE mode and ReAct through each step.
"""
        }
    }
}
