import Foundation
import SwiftUI

// MARK: - Conversation Model

/// A full conversation snapshot — all tabs, messages, and state.
struct Conversation: Codable, Identifiable {
    var id: UUID
    var title: String
    var tabs: [AgentTab]
    var activeTabId: UUID
    var mode: ExecutionMode
    var createdAt: Date
    var updatedAt: Date
}

/// Lightweight summary for list display.
struct ConversationSummary: Identifiable, Equatable {
    let id: UUID
    let title: String
    let tabCount: Int
    let messageCount: Int
    let updatedAt: Date
    let createdAt: Date
}

// MARK: - ConversationStore

/// Manages saving/loading/list/search of conversations as JSON files.
///
/// Storage: `~/Library/Application Support/Hermes4Xcode/Conversations/<id>.json`
///
final class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    @Published var summaries: [ConversationSummary] = []
    @Published var currentConversationId: UUID?
    @Published var searchQuery = ""

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var saveDir: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Hermes4Xcode/Conversations", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var saveDebounceTask: Task<Void, Never>?
    private let debounceSeconds: UInt64 = 1_000_000_000  // 1 second

    private init() {}

    // MARK: - Public API

    /// Save a conversation snapshot. Debounced — call frequently.
    func save(conversation: Conversation) {
        let url = saveDir.appendingPathComponent("\(conversation.id.uuidString).json")
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceSeconds)
            guard !Task.isCancelled else { return }
            do {
                let data = try encoder.encode(conversation)
                try data.write(to: url, options: .atomic)
                await refreshSummaries()
            } catch {
                print("[ConversationStore] Save error: \(error)")
            }
        }
    }

    /// Load a specific conversation by ID.
    func load(id: UUID) -> Conversation? {
        let url = saveDir.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url),
              let conv = try? decoder.decode(Conversation.self, from: data)
        else { return nil }
        return conv
    }

    /// Delete a conversation file.
    func delete(id: UUID) {
        let url = saveDir.appendingPathComponent("\(id.uuidString).json")
        try? fileManager.removeItem(at: url)
        Task { @MainActor in await refreshSummaries() }
    }

    /// Search conversations by title or message content.
    func search(_ query: String) -> [ConversationSummary] {
        guard !query.isEmpty else { return summaries }
        let lower = query.lowercased()
        return summaries.filter { $0.title.lowercased().contains(lower) }
    }

    /// Refresh the summaries list from disk.
    @MainActor
    func refreshSummaries() async {
        do {
            let files = try fileManager.contentsOfDirectory(at: saveDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            var results: [ConversationSummary] = []
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let conv = try? decoder.decode(Conversation.self, from: data)
                else { continue }
                let msgCount = conv.tabs.reduce(0) { $0 + $1.messages.count }
                results.append(ConversationSummary(
                    id: conv.id,
                    title: conv.title,
                    tabCount: conv.tabs.count,
                    messageCount: msgCount,
                    updatedAt: conv.updatedAt,
                    createdAt: conv.createdAt
                ))
            }
            summaries = results.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            print("[ConversationStore] Refresh error: \(error)")
        }
    }

    /// Duplicate a conversation (for branching).
    func duplicate(id: UUID, newTitle: String? = nil) -> UUID? {
        guard var conv = load(id: id) else { return nil }
        conv.id = UUID()
        conv.title = newTitle ?? "\(conv.title) (copy)"
        conv.createdAt = Date()
        conv.updatedAt = Date()
        save(conversation: conv)
        return conv.id
    }
}

// MARK: - AgentManager Extension (snapshot)

extension AgentManager {
    /// Take a snapshot of current state as a Conversation
    func snapshot(title: String? = nil) -> Conversation {
        Conversation(
            id: ConversationStore.shared.currentConversationId ?? UUID(),
            title: title ?? "会话 \(dateFormatter.string(from: Date()))",
            tabs: tabs,
            activeTabId: activeTabId,
            mode: mode,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Restore state from a Conversation snapshot
    func restore(from conversation: Conversation) {
        tabs = conversation.tabs
        activeTabId = conversation.activeTabId
        mode = conversation.mode
        ConversationStore.shared.currentConversationId = conversation.id
    }

    /// Auto-save current state
    func autoSave() {
        let conv = snapshot()
        ConversationStore.shared.currentConversationId = conv.id
        ConversationStore.shared.save(conversation: conv)
    }
}

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MM-dd HH:mm"
    return f
}()
