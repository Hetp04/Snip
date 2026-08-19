import SwiftUI
import UIKit

/// The iPhone and iPad clipboard card history view.
/// Assembles search, live folder pills, history cards, and the floating dock.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var history = IOSClipboardHistoryViewModel()
    @ObservedObject private var syncDiagnostics = CloudSyncDiagnostics.shared
    @State private var searchText = ""
    @State private var selectedFolderID: UUID? = nil
    @State private var selectedTab: IOSDockTab = .allHistory
    @State private var isShowingSettings = false
    @State private var copiedItemToast: String? = nil

    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 14),
        GridItem(.flexible(minimum: 0), spacing: 14)
    ]

    private var visibleItems: [ClipboardItem] {
        var base = history.items

        // Tab filter (Favorites)
        if selectedTab == .favorites {
            base = base.filter { $0.isPinned }
        }

        // Folder filter
        if let selectedFolderID {
            base = base.filter { $0.folderIDs.contains(selectedFolderID) }
        }

        // Search query filter
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            base = base.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
        }

        // `items` is already maintained in chronological order by the view
        // model. Filtering must preserve that order: changing a pin or folder
        // must not make an old clipboard capture jump ahead of a newer one.
        return base
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    searchField
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    // Folders Section (Only show if not in Chain tab)
                    if selectedTab != .chain {
                        IOSFolderPillsView(
                            folders: history.folders,
                            selectedFolderID: $selectedFolderID,
                            itemCountForFolder: { history.itemCount(inFolder: $0) },
                            onCreateFolder: { history.createFolder(name: $0) }
                        )
                    }

                    // Content Section
                    if selectedTab == .chain {
                        chainSection
                    } else {
                        historySection
                    }
                }
                .padding(.bottom, 120) // Space for floating dock
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .refreshable { await history.refresh() }

            // Floating Bottom Dock
            IOSDockView(
                selectedTab: $selectedTab,
                onOpenSettings: { isShowingSettings = true }
            )
            .padding(.bottom, 16)

            // Copied Toast Notification
            if let copiedItemToast {
                Text(copiedItemToast)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .shadow(radius: 6)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .colorScheme(.light)
        .task { history.load() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                history.startAutomaticSyncLoop()
                Task { await history.refresh() }
            } else {
                history.stopAutomaticSyncLoop()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            settingsSheet
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history...", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: { isShowingSettings = true }) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Color(uiColor: .white), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(sectionTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.secondary.opacity(0.8))

                Spacer()

                if selectedFolderID != nil || selectedTab == .favorites {
                    Text("\(visibleItems.count) items")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)

            if history.isLoading && history.items.isEmpty {
                ProgressView("Syncing iCloud Library…")
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else if let error = history.loadError, history.items.isEmpty {
                unavailableState(error)
            } else if visibleItems.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(visibleItems) { item in
                        IOSClipboardCard(
                            item: item,
                            onCopy: {
                                history.copy(item)
                                showToast("Copied to clipboard")
                            },
                            onToggleFavorite: {
                                history.toggleFavorite(item)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)

                Text("\(visibleItems.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
        }
    }

    private var sectionTitle: String {
        if selectedTab == .favorites { return "FAVORITES" }
        if let folder = history.folders.first(where: { $0.id == selectedFolderID }) {
            return folder.name.uppercased()
        }
        return "ALL HISTORY"
    }

    private var chainSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CHAIN")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.8))
                .padding(.horizontal, 16)

            if history.chains.isEmpty {
                ContentUnavailableView(
                    "No Active Chains",
                    systemImage: "link",
                    description: Text("Create sequential paste chains on your Mac to execute them on iPhone.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ForEach(history.chains) { chain in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(chain.name)
                            .font(.headline)
                        Text(chain.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            emptyStateTitle,
            systemImage: selectedTab == .favorites ? "star" : (searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass"),
            description: Text(emptyStateDescription)
        )
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var emptyStateTitle: String {
        if selectedTab == .favorites { return "No Favorites Yet" }
        if !searchText.isEmpty { return "No Matching Snippets" }
        return "No Copied Snippets Yet"
    }

    private var emptyStateDescription: String {
        if selectedTab == .favorites { return "Star important snippets to quickly access them here." }
        if !searchText.isEmpty { return "Try a different search query." }
        return "Snippets copied on your Mac will sync to your iPhone automatically."
    }

    private func unavailableState(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Sync Unavailable", systemImage: "icloud.slash")
        } description: {
            Text(error)
        } actions: {
            Button("Retry Sync") {
                history.load()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section("iCloud Sync") {
                    HStack {
                        Label("Status", systemImage: "checkmark.icloud.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text("Active & Synced")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Last Sync", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Text(syncDiagnostics.lastSuccessfulSync?.formatted(date: .omitted, time: .shortened) ?? "Not yet")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Live Update", systemImage: "bolt.horizontal.icloud")
                        Spacer()
                        Text(syncDiagnostics.lastSyncSource)
                            .foregroundStyle(.secondary)
                    }
                    if let error = syncDiagnostics.lastError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    HStack {
                        Label("Total Items", systemImage: "doc.on.doc")
                        Spacer()
                        Text("\(history.items.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Folders", systemImage: "folder")
                        Spacer()
                        Text("\(history.folders.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    HStack {
                        Text("App Name")
                        Spacer()
                        Text("Sniphet iOS")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingSettings = false
                    }
                }
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            copiedItemToast = text
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                if copiedItemToast == text {
                    copiedItemToast = nil
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
