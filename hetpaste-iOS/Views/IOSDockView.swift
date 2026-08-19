import SwiftUI

enum IOSDockTab: String, CaseIterable, Identifiable {
    case allHistory = "All History"
    case favorites = "Favorites"
    case chain = "Chain"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .allHistory: return "clock"
        case .favorites: return "star"
        case .chain: return "link"
        case .settings: return "gearshape"
        }
    }
}

struct IOSDockView: View {
    @Binding var selectedTab: IOSDockTab
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            ForEach(IOSDockTab.allCases) { tab in
                dockButton(for: tab)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Color.white.opacity(0.95),
            in: Capsule()
        )
        .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 10)
    }

    private func dockButton(for tab: IOSDockTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            if tab == .settings {
                onOpenSettings()
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = tab
                }
            }
        } label: {
            Image(systemName: isSelected ? (tab == .favorites ? "star.fill" : tab.icon) : tab.icon)
                .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? (tab == .favorites ? IOSTheme.starActive : Color.blue) : Color(uiColor: .tertiaryLabel))
                .frame(width: 44, height: 44)
                .background(
                    isSelected
                        ? (tab == .favorites ? IOSTheme.starActive.opacity(0.15) : Color.blue.opacity(0.12))
                        : Color.clear,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
    }
}
