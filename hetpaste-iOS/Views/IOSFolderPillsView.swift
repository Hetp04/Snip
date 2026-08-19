import SwiftUI

struct IOSFolderPillsView: View {
    let folders: [ClipboardFolder]
    @Binding var selectedFolderID: UUID?
    let itemCountForFolder: (UUID) -> Int
    let onCreateFolder: (String) -> Void

    @State private var isShowingCreateAlert = false
    @State private var newFolderName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FOLDERS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.8))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if selectedFolderID != nil {
                        allFilterPill
                    }

                    ForEach(folders) { folder in
                        folderPill(for: folder)
                    }

                    newFolderButton
                }
                .padding(.horizontal, 16)
            }
        }
        .alert("New Folder", isPresented: $isShowingCreateAlert) {
            TextField("Folder Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    onCreateFolder(trimmed)
                }
            }
        }
    }

    private var allFilterPill: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFolderID = nil
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                Text("All Items")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.12), in: Capsule())
            .foregroundStyle(Color.blue)
        }
        .buttonStyle(.plain)
    }

    private func folderPill(for folder: ClipboardFolder) -> some View {
        let isSelected = selectedFolderID == folder.id
        let count = itemCountForFolder(folder.id)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if selectedFolderID == folder.id {
                    selectedFolderID = nil
                } else {
                    selectedFolderID = folder.id
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(isSelected ? Color.blue : Color(uiColor: .darkGray))
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 0) {
                    Text(folder.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.blue : .primary)
                        .lineLimit(1)
                    Text("\(count) \(count == 1 ? "item" : "items")")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.blue : Color(uiColor: .tertiaryLabel))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minWidth: 130, alignment: .leading)
            .background(
                isSelected ? Color.blue.opacity(0.08) : Color(uiColor: .white),
                in: Capsule()
            )
            .overlay {
                if isSelected {
                    Capsule().stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
                }
            }
            .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var newFolderButton: some View {
        Button {
            newFolderName = ""
            isShowingCreateAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .foregroundStyle(.primary)
                    .font(.system(size: 14, weight: .medium))
                Text("New Folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 120, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}
