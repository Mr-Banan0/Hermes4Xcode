import SwiftUI

// MARK: - Model

struct CronTask: Identifiable, Codable {
    let id: UUID
    var name: String
    var schedule: CronSchedule
    var prompt: String
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, schedule: CronSchedule, prompt: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.schedule = schedule
        self.prompt = prompt
        self.isEnabled = isEnabled
    }
}

enum CronSchedule: String, Codable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case custom = "custom"

    var label: String {
        switch self {
        case .daily: return "Every Day"
        case .weekly: return "Every Week"
        case .custom: return "Custom (cron)"
        }
    }

    var cronExpr: String {
        switch self {
        case .daily: return "0 9 * * *"
        case .weekly: return "0 9 * * 1"
        case .custom: return ""
        }
    }
}

// MARK: - View

struct CronSettingsView: View {
    @State private var tasks: [CronTask] = []
    @State private var showAddSheet = false

    private let storageKey = "Hermes4Xcode_cronTasks"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Scheduled Tasks")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.hermes)
                Spacer()
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill").foregroundColor(.hermes)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Color.hermes.opacity(0.3))

            if tasks.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text("No scheduled tasks")
                        .font(.system(size: 13, design: .monospaced)).foregroundColor(.secondary)
                    Text("Click + to add one")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(tasks) { task in
                        TaskRow(task: task, onToggle: { toggleTask(task) }, onDelete: { deleteTask(task) })
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color.black)
        .onAppear(perform: loadTasks)
        .sheet(isPresented: $showAddSheet) {
            AddTaskSheet { newTask in
                tasks.append(newTask)
                saveTasks()
            }
        }
    }

    private func toggleTask(_ task: CronTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].isEnabled.toggle()
        saveTasks()
        updateHermesCron(task: tasks[idx])
    }

    private func deleteTask(_ task: CronTask) {
        tasks.removeAll { $0.id == task.id }
        saveTasks()
        // Remove from hermes cron
        let _ = XcodeContextProvider.shared.runShell("hermes cron remove \(task.id.uuidString) 2>/dev/null")
    }

    private func saveTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadTasks() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CronTask].self, from: data) else { return }
        tasks = decoded
    }

    private func updateHermesCron(task: CronTask) {
        if task.isEnabled {
            let expr = task.schedule.cronExpr
            let escapedPrompt = task.prompt.replacingOccurrences(of: "'", with: "'\\''")
            let _ = XcodeContextProvider.shared.runShell(
                "hermes cron create '\(expr)' --name '\(task.name)' --prompt '\(escapedPrompt)' 2>/dev/null"
            )
        } else {
            let _ = XcodeContextProvider.shared.runShell("hermes cron pause \(task.id.uuidString) 2>/dev/null")
        }
    }
}

// MARK: - Task Row

struct TaskRow: View {
    let task: CronTask
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: task.isEnabled ? "clock.badge.checkmark" : "clock.badge.xmark")
                .foregroundColor(task.isEnabled ? .hermes : .gray)
                .font(.caption)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.name)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Text(task.schedule.label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { task.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Button(action: onDelete) {
                Image(systemName: "trash").font(.caption).foregroundColor(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Task Sheet

struct AddTaskSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var schedule: CronSchedule = .daily
    @State private var prompt = ""
    let onSave: (CronTask) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("New Scheduled Task")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.hermes)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                TextField("e.g. Nightly Build Check", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8).background(Color(white: 0.15)).cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Schedule").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                Picker("", selection: $schedule) {
                    ForEach(CronSchedule.allCases, id: \.self) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                TextEditor(text: $prompt)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(8).background(Color(white: 0.15)).cornerRadius(6)
                    .frame(height: 100)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                Spacer()
                Button("Save") {
                    let task = CronTask(name: name, schedule: schedule, prompt: prompt)
                    onSave(task)
                    // Register with hermes cron
                    let expr = schedule.cronExpr
                    let escaped = prompt.replacingOccurrences(of: "'", with: "'\\''")
                    let _ = XcodeContextProvider.shared.runShell(
                        "hermes cron create '\(expr)' --name '\(name)' --prompt '\(escaped)' 2>/dev/null"
                    )
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.hermes)
                .disabled(name.isEmpty || prompt.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Color(white: 0.08))
    }
}
