import SwiftUI

// MARK: - Tab Bar View

struct TabBarView: View {
    @ObservedObject var manager: AgentManager
    @State private var editingTabId: UUID?
    @State private var editName = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(manager.tabs) { tab in
                    TabItemView(
                        tab: tab,
                        isActive: tab.id == manager.activeTabId,
                        isEditing: editingTabId == tab.id,
                        editName: $editName,
                        canDelete: manager.tabs.count > 1,
                        onSelect: { manager.switchToTab(id: tab.id) },
                        onDelete: { manager.removeTab(id: tab.id) },
                        onStartEdit: {
                            editingTabId = tab.id
                            editName = tab.name
                        },
                        onEndEdit: {
                            if let id = editingTabId {
                                let name = editName.trimmingCharacters(in: .whitespaces)
                                if !name.isEmpty {
                                    manager.renameTab(id: id, name: name)
                                }
                            }
                            editingTabId = nil
                            editName = ""
                        },
                        onEditProfile: { manager.openProfileEditor(for: tab.id) }
                    )
                }

                // Add button
                Button(action: {
                    _ = manager.createTab(name: "stranger")
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.hermes)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .help("New agent tab")
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 32)
        .background(Color(white: 0.06))
    }
}

// MARK: - Tab Item

struct TabItemView: View {
    let tab: AgentTab
    let isActive: Bool
    let isEditing: Bool
    @Binding var editName: String
    let canDelete: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onStartEdit: () -> Void
    let onEndEdit: () -> Void
    let onEditProfile: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Template icon
            if !isEditing {
                Image(systemName: tab.template.icon)
                    .font(.system(size: 9))
                    .foregroundColor(isActive ? .hermes : .gray.opacity(0.6))
            }

            if isEditing {
                TextField("", text: $editName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 80)
                    .onSubmit(onEndEdit)
            } else {
                Text(tab.name)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular, design: .monospaced))
                    .foregroundColor(isActive ? .hermes : .gray)
                    .onTapGesture(count: 2) { onStartEdit() }
            }

            if canDelete && tab.name != "supervisor" {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isActive ? Color.hermes.opacity(0.12) : Color.clear)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isActive ? Color.hermes.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onTapGesture { onSelect() }
        .contextMenu {
            Button {
                onEditProfile()
            } label: {
                Label("Edit Agent Profile", systemImage: "slider.horizontal.3")
            }

            Button {
                onStartEdit()
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            if canDelete && tab.name != "supervisor" {
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Agent", systemImage: "trash")
                }
            }
        }
        .padding(.trailing, 4)
    }
}
