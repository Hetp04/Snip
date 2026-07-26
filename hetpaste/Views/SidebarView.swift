import SwiftUI
import UniformTypeIdentifiers
struct SidebarView: View {
    @Binding var destination: NavDestination
    var onDropToTrash: ((UUID) -> Void)? = nil
    private let items: [(title: String, icon: String, destination: NavDestination)] = [
        ("Apps", "square.grid.2x2", .launchpad),
        ("All History", "clock", .history),
        ("Favorites", "star", .favorites),
        ("Chain", "link", .chain),
        ("Settings", "gearshape", .settings)
    ]
    @State private var isTrashHovered = false
    @State private var isTrashDropTargeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.title) { item in
                SidebarItem(
                    icon: item.icon,
                    label: item.title,
                    isSelected: destination == item.destination
                ) {
                    destination = item.destination
                }
            }
            Spacer()
            Divider()
                .background(Theme.divider)
                .padding(.vertical, 4)
            Button(action: { destination = .trash }) {
                HStack(spacing: 8) {
                    Image(systemName: isTrashDropTargeted ? "trash.fill" : "trash")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 18)
                        .foregroundColor(isTrashDropTargeted ? .red : (destination == .trash ? Theme.textPrimary : Theme.textSecondary))
                    Text("Trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(destination == .trash ? Theme.textPrimary : Theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            isTrashDropTargeted
                                ? Color.red.opacity(0.12)
                                : (destination == .trash ? Theme.selection : (isTrashHovered ? Theme.cardHover : Color.clear))
                        )
                        .softInnerShadow(
                            RoundedRectangle(cornerRadius: 7),
                            darkShadow: Color.black.opacity(destination == .trash ? 0.2 : 0),
                            lightShadow: Color.white.opacity(destination == .trash ? 0.6 : 0),
                            spread: 0.05,
                            radius: 2
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isTrashDropTargeted ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.15), value: isTrashDropTargeted)
            }
            .buttonStyle(.plain)
            .onHover { isTrashHovered = $0 }
            .onDrop(of: [.plainText], isTargeted: $isTrashDropTargeted) { providers in
                for provider in providers {
                    provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, _ in
                        guard let data = data as? Data,
                              let uuidStr = String(data: data, encoding: .utf8),
                              let uuid = UUID(uuidString: uuidStr) else { return }
                        DispatchQueue.main.async {
                            onDropToTrash?(uuid)
                        }
                    }
                }
                return true
            }
        }
        .padding(10)
        .frame(minWidth: 176, idealWidth: 176, maxWidth: 176, maxHeight: .infinity)
        .background(Theme.sidebar)
    }
}
struct SidebarItem: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Theme.selection : (isHovered ? Theme.cardHover : Color.clear))
                    .softInnerShadow(
                        RoundedRectangle(cornerRadius: 7),
                        darkShadow: Color.black.opacity(isSelected ? 0.2 : 0),
                        lightShadow: Color.white.opacity(isSelected ? 0.6 : 0),
                        spread: 0.05,
                        radius: 2
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}