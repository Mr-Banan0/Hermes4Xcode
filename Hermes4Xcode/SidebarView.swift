import SwiftUI

struct SidebarView: View {
    @Binding var selectedPage: AppPage

    var body: some View {
        VStack(spacing: 0) {
            // Logo
            VStack(spacing: 2) {
                Text("⚡")
                    .font(.title2)
                Text("H4X")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(.hermes)
            }
            .padding(.top, 12)
            .padding(.bottom, 16)

            Divider().background(Color.hermes.opacity(0.2))
                .padding(.horizontal, 6)

            // Menu items
            ForEach(AppPage.allCases) { page in
                SidebarItem(
                    icon: page.icon,
                    label: page.label,
                    isSelected: selectedPage == page
                )
                .onTapGesture { selectedPage = page }
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(width: 56)
        .background(Color(white: 0.08))
    }
}

struct SidebarItem: View {
    let icon: String
    let label: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .hermes : .gray)
            Text(label)
                .font(.system(size: 7, weight: isSelected ? .bold : .regular, design: .monospaced))
                .foregroundColor(isSelected ? .hermes : .gray)
                .lineLimit(1)
        }
        .frame(width: 48, height: 48)
        .background(isSelected ? Color.hermes.opacity(0.15) : Color.clear)
        .cornerRadius(8)
    }
}
