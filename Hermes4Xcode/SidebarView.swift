import SwiftUI

struct SidebarView: View {
    @Binding var selectedPage: AppPage
    @Binding var isCollapsed: Bool
    let onToggleCollapse: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Logo / Toggle button area
            HStack {
                if isCollapsed {
                    Button(action: onToggleCollapse) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.hermes)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                } else {
                    HStack {
                        Button(action: onToggleCollapse) {
                            Image(systemName: "sidebar.left")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)

            Divider().background(Color.hermes.opacity(0.2))
                .padding(.horizontal, isCollapsed ? 4 : 8)

            // Menu items
            ForEach(AppPage.allCases) { page in
                if isCollapsed {
                    // Icon only
                    VStack(spacing: 3) {
                        Image(systemName: page.icon)
                            .font(.system(size: 16))
                            .foregroundColor(selectedPage == page ? .hermes : .gray)
                        Text(page.label.prefix(3))
                            .font(.system(size: 6, weight: .medium, design: .monospaced))
                            .foregroundColor(selectedPage == page ? .hermes : .gray)
                    }
                    .frame(width: 36, height: 40)
                    .background(selectedPage == page ? Color.hermes.opacity(0.15) : Color.clear)
                    .cornerRadius(6)
                    .onTapGesture { selectedPage = page }
                    .padding(.top, 4)
                } else {
                    // Icon + label
                    HStack(spacing: 8) {
                        Image(systemName: page.icon)
                            .font(.system(size: 14))
                            .foregroundColor(selectedPage == page ? .hermes : .gray)
                            .frame(width: 20)
                        Text(page.label)
                            .font(.system(size: 11, weight: selectedPage == page ? .semibold : .regular, design: .monospaced))
                            .foregroundColor(selectedPage == page ? .hermes : .gray)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedPage == page ? Color.hermes.opacity(0.12) : Color.clear)
                    .cornerRadius(6)
                    .onTapGesture { selectedPage = page }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                }
            }

            Spacer()
        }
        .background(Color(white: 0.08))
    }
}
