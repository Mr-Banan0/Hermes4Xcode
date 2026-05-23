import SwiftUI

struct SidebarView: View {
    @Binding var selectedPage: AppPage
    @Binding var isCollapsed: Bool
    let onToggleCollapse: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Toggle button — leading in expanded, centered in collapsed
            Button(action: onToggleCollapse) {
                Image(systemName: isCollapsed ? "line.3.horizontal" : "sidebar.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.hermes)
            }
            .buttonStyle(.plain)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .padding(.leading, isCollapsed ? 0 : 12)

            Divider().background(Color.hermes.opacity(0.2))
                .padding(.horizontal, isCollapsed ? 0 : 8)

            if isCollapsed {
                // ── Collapsed: icons only, tight ──
                collapsedContent
                    .transition(.opacity)
            } else {
                // ── Expanded: icon + label ──
                expandedContent
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color(white: 0.08))
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
    }

    // MARK: - Collapsed: icon only, centered in 40px

    private var collapsedContent: some View {
        VStack(spacing: 4) {
            ForEach(AppPage.allCases) { page in
                Image(systemName: page.icon)
                    .font(.system(size: 16))
                    .foregroundColor(selectedPage == page ? .hermes : .gray)
                    .frame(width: 34, height: 34)
                    .background(selectedPage == page ? Color.hermes.opacity(0.15) : Color.clear)
                    .cornerRadius(6)
                    .onTapGesture { selectedPage = page }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Expanded: full row with label

    private var expandedContent: some View {
        VStack(spacing: 0) {
            ForEach(AppPage.allCases) { page in
                HStack(spacing: 8) {
                    Image(systemName: page.icon)
                        .font(.system(size: 14))
                        .foregroundColor(selectedPage == page ? .hermes : .gray)
                        .frame(width: 20)

                    Text(page.label)
                        .font(.system(size: 11,
                                      weight: selectedPage == page ? .semibold : .regular,
                                      design: .monospaced))
                        .foregroundColor(selectedPage == page ? .hermes : .gray)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(selectedPage == page ? Color.hermes.opacity(0.12) : Color.clear)
                .cornerRadius(6)
                .onTapGesture { selectedPage = page }
                .padding(.horizontal, 6)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}
