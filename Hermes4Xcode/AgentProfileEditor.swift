import SwiftUI

// MARK: - Agent Profile Editor

struct AgentProfileEditor: View {
    @ObservedObject var manager: AgentManager
    let tabId: UUID

    @State private var name: String = ""
    @State private var role: String = ""
    @State private var systemPrompt: String = ""
    @State private var permissions: AgentPermissions = .all
    @State private var template: AgentTemplate = .custom
    @State private var selectedTab = 0

    init(manager: AgentManager, tabId: UUID) {
        self.manager = manager
        self.tabId = tabId
        let tab = manager.tabs.first(where: { $0.id == tabId }) ?? manager.tabs[0]
        _name = State(initialValue: tab.name)
        _role = State(initialValue: tab.roleDescription)
        _systemPrompt = State(initialValue: tab.systemPrompt)
        _permissions = State(initialValue: tab.permissions)
        _template = State(initialValue: tab.template)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: template.icon)
                    .foregroundColor(.hermes)
                Text("Agent Profile: \(name)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.hermes)
                Spacer()
                Button("Done") { saveAndClose() }
                    .buttonStyle(.plain)
                    .foregroundColor(.hermes)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.hermes.opacity(0.15)).cornerRadius(4)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().background(Color.hermes.opacity(0.3))

            // Segmented tabs
            Picker("", selection: $selectedTab) {
                Text("Profile").tag(0)
                Text("Prompt").tag(1)
                Text("Permissions").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 10)

            Divider().background(Color.hermes.opacity(0.2))

            // Content
            ScrollView {
                switch selectedTab {
                case 0: profileTab
                case 1: promptTab
                case 2: permissionsTab
                default: EmptyView()
                }
            }
        }
        .frame(width: 460, height: 520)
        .background(Color.black)
    }

    // MARK: - Profile Tab

    private var profileTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Name
            fieldLabel("Agent Name")
            HermesField(text: $name, placeholder: "e.g. code-reviewer")

            // Template picker
            fieldLabel("Role Template")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 6) {
                ForEach(AgentTemplate.allCases) { t in
                    TemplateChip(
                        template: t,
                        isSelected: template == t
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            applyTemplate(t)
                        }
                    }
                }
            }

            // Role description
            fieldLabel("Role Description")
            HermesEditor(text: $role, placeholder: "Describe this agent's role...", height: 60)

            // Reset button
            HStack {
                Spacer()
                Button(action: resetToTemplate) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise").font(.caption)
                        Text("Reset to Template Defaults")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color(white: 0.12)).cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            // Preview
            if !systemPrompt.isEmpty {
                fieldLabel("Current System Prompt (preview)")
                Text(systemPrompt)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(6)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.08)).cornerRadius(6)
            }

            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill").font(.caption).foregroundColor(.hermesAmber)
                Text("Permissions: \(permissionSummary)")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
            }
        }
        .padding(16)
    }

    // MARK: - Prompt Tab

    private var promptTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                fieldLabel("System Prompt")
                Spacer()
                Text("\(systemPrompt.count) chars")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
            }

            TextEditor(text: $systemPrompt)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(white: 0.1))
                .cornerRadius(6)
                .frame(minHeight: 300)

            HStack {
                Button(action: {
                    systemPrompt = template.defaultPrompt
                }) {
                    Text("Restore Template Prompt")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.hermesAmber)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("This prompt is sent as the system message with each request")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }

    // MARK: - Permissions Tab

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                fieldLabel("Tool Permissions")
                Spacer()
                HStack(spacing: 6) {
                    Button("All") { permissions = .all }
                        .font(.system(size: 9, design: .monospaced))
                        .buttonStyle(.plain).foregroundColor(.hermes)
                    Button("None") {
                        permissions = AgentPermissions(
                            readFile: false, writeCode: false, build: false, test: false,
                            analyze: false, commit: false, structure: false, note: false
                        )
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .buttonStyle(.plain).foregroundColor(.red.opacity(0.7))
                }
            }

            Text("Control which tools this agent can use. Disabled tools are hidden from the toolbar.")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)

            Divider().background(Color.hermes.opacity(0.2))

            PermissionToggle(
                icon: "doc.text.magnifyingglass",
                label: "Read File",
                detail: "Read current file from Xcode",
                isOn: $permissions.readFile
            )
            PermissionToggle(
                icon: "pencil",
                label: "Write Code",
                detail: "Apply code changes to Xcode selection",
                isOn: $permissions.writeCode
            )
            PermissionToggle(
                icon: "hammer.fill",
                label: "Build",
                detail: "Run xcodebuild",
                isOn: $permissions.build
            )
            PermissionToggle(
                icon: "checkmark.circle",
                label: "Test",
                detail: "Run XCTest suite",
                isOn: $permissions.test
            )
            PermissionToggle(
                icon: "magnifyingglass.circle",
                label: "Analyze",
                detail: "Code review, refactor, SourceKit-LSP diagnostics",
                isOn: $permissions.analyze
            )
            PermissionToggle(
                icon: "arrow.triangle.branch",
                label: "Commit",
                detail: "Generate git commit messages",
                isOn: $permissions.commit
            )
            PermissionToggle(
                icon: "folder",
                label: "Structure",
                detail: "Read project structure / file tree",
                isOn: $permissions.structure
            )
            PermissionToggle(
                icon: "note.text",
                label: "Note",
                detail: "Save cross-session project notes",
                isOn: $permissions.note
            )

            Spacer()
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(.secondary)
    }

    private func applyTemplate(_ t: AgentTemplate) {
        template = t
        name = t == .custom ? name : t.rawValue
        role = t.defaultRole
        systemPrompt = t.defaultPrompt
        permissions = t.defaultPermissions
    }

    private func resetToTemplate() {
        applyTemplate(template)
    }

    private var permissionSummary: String {
        var parts: [String] = []
        if permissions.readFile { parts.append("read") }
        if permissions.writeCode { parts.append("write") }
        if permissions.build { parts.append("build") }
        if permissions.test { parts.append("test") }
        if permissions.analyze { parts.append("analyze") }
        if permissions.commit { parts.append("commit") }
        if permissions.structure { parts.append("structure") }
        if permissions.note { parts.append("note") }
        return parts.joined(separator: ", ")
    }

    private func saveAndClose() {
        let profile = AgentProfile(
            id: tabId,
            name: name,
            template: template,
            role: role,
            systemPrompt: systemPrompt,
            permissions: permissions
        )
        manager.updateProfile(for: tabId, profile)
        manager.showProfileEditor = false
    }
}

// MARK: - Subviews

struct TemplateChip: View {
    let template: AgentTemplate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: template.icon)
                    .font(.system(size: 10))
                Text(template.label)
                    .font(.system(size: 10, design: .monospaced))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.hermes.opacity(0.2) : Color(white: 0.1))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.hermes : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .hermes : .gray)
    }
}

struct PermissionToggle: View {
    let icon: String
    let label: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(isOn ? .hermes : .gray)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shared UI Components

struct HermesField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(.white)
            .padding(10)
            .background(Color(white: 0.12))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.hermes.opacity(0.3), lineWidth: 1))
    }
}

struct HermesEditor: View {
    @Binding var text: String
    let placeholder: String
    let height: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.white)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Color(white: 0.12))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.hermes.opacity(0.3), lineWidth: 1))
            .frame(height: height)
    }
}
