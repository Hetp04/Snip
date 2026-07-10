import SwiftUI
struct TrashView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    var onExpandItem: ((ClipboardItem) -> Void)? = nil
    @State private var showConfirmEmpty = false
    let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                Text("Trash")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if !viewModel.trashedItems.isEmpty {
                    Button(action: { showConfirmEmpty = true }) {
                        Text("Empty Trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.red.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)
            Divider().background(Theme.divider)
            if viewModel.trashedItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.trashedItems) { item in
                            ClipboardItemRow(
                                item: item,
                                isTrashMode: true,
                                onRestore: { viewModel.restoreFromTrash(item) },
                                onPermanentDelete: { viewModel.deleteItem(item) },
                                onExpand: { onExpandItem?(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
        .background(Theme.bg)
        .alert("Empty Trash", isPresented: $showConfirmEmpty) {
            Button("Empty Trash", role: .destructive) {
                viewModel.emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all items in the Trash. This action cannot be undone.")
        }
    }
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "trash")
                .font(.system(size: 42))
                .foregroundColor(Theme.textTertiary)
            Text("Trash is Empty")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            Text("Drag cards here to remove them from your history.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}