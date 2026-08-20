import SwiftUI
import UIKit
import Photos

private struct IOSSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

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
    @State private var isShowingAdvancedFilters = false
    @State private var selectedApps: Set<String> = []
    @State private var selectedCategories: Set<ContentCategory> = []
    @State private var selectedDateFilter: ClipboardDateFilter? = nil
    @State private var isShowingAppFilter = false
    @State private var isShowingTypeFilter = false
    @State private var isShowingDateFilter = false
    @State private var copiedItemToast: String? = nil
    @State private var quickLookURL: URL? = nil
    @State private var inAppLinkURL: URL? = nil
    @State private var sharePayload: IOSSharePayload? = nil
    @State private var exportURL: URL? = nil
    @State private var editingItem: ClipboardItem? = nil
    @State private var isPreparingCardAction = false

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

        // These use the same shared categories and date rules as the macOS
        // filter controls, so a filter means the same thing on every device.
        if !selectedApps.isEmpty {
            base = base.filter { selectedApps.contains($0.sourceAppName) }
        }
        if !selectedCategories.isEmpty {
            base = base.filter { selectedCategories.contains(ContentCategory.detect(from: $0)) }
        }
        if let selectedDateFilter {
            base = base.filter { selectedDateFilter.contains($0.createdAt) }
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
                    VStack(spacing: 10) {
                        searchField
                        if isShowingAdvancedFilters { advancedFilterControls }
                    }
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
        .sheet(isPresented: urlPresentationBinding(for: $quickLookURL)) {
            if let quickLookURL { IOSQuickLookPreview(url: quickLookURL).ignoresSafeArea() }
        }
        .sheet(isPresented: urlPresentationBinding(for: $inAppLinkURL)) {
            if let inAppLinkURL { IOSSafariPreview(url: inAppLinkURL).ignoresSafeArea() }
        }
        .sheet(item: $sharePayload) { payload in
            IOSShareSheet(items: payload.items)
        }
        .sheet(isPresented: urlPresentationBinding(for: $exportURL)) {
            if let exportURL { IOSFileExporter(url: exportURL) }
        }
        .sheet(item: $editingItem) { item in
            IOSRichTextEditorSheet(item: item) { contentText, rtfData, htmlData, rtfdData in
                let didSave = history.updateItemContent(id: item.id, contentText: contentText, rtfData: rtfData, htmlData: htmlData, rtfdData: rtfdData)
                if didSave { showToast("Saved") }
                return didSave
            }
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
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isShowingAdvancedFilters.toggle() } }) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(hasAdvancedFilters ? Color.accentColor : .secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Color(uiColor: .white), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var availableApps: [(name: String, iconData: Data?)] {
        let icons = ClipboardAppIconIndex(items: history.items)
        let apps: [(name: String, iconData: Data?)] = Dictionary(grouping: history.items, by: \ClipboardItem.sourceAppName)
            .map { name, _ in (name, icons.iconData(appName: name)) }
        return apps.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var appIcons: ClipboardAppIconIndex { ClipboardAppIconIndex(items: history.items) }

    private var filterCategories: [ContentCategory] {
        [.text, .url, .image, .file, .code, .color, .email, .phone, .richText, .video]
    }

    private var hasAdvancedFilters: Bool {
        !selectedApps.isEmpty || !selectedCategories.isEmpty || selectedDateFilter != nil
    }

    private var advancedFilterControls: some View {
        HStack(spacing: 8) {
            Button { isShowingAppFilter.toggle() } label: {
                filterPill(title: selectedApps.isEmpty ? "Apps" : "Apps · \(selectedApps.count)", icon: "app.fill", active: !selectedApps.isEmpty)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingAppFilter, arrowEdge: .top) { appFilterPopover }

            Button { isShowingTypeFilter.toggle() } label: {
                filterPill(title: selectedCategories.isEmpty ? "Types" : "Types · \(selectedCategories.count)", icon: "square.grid.2x2.fill", active: !selectedCategories.isEmpty)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingTypeFilter, arrowEdge: .top) { typeFilterPopover }

            Button { isShowingDateFilter.toggle() } label: {
                filterPill(title: selectedDateFilter.map { "Date · \($0.rawValue)" } ?? "Date", icon: "calendar", active: selectedDateFilter != nil)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingDateFilter, arrowEdge: .top) { dateFilterPopover }

            if hasAdvancedFilters {
                Button("Clear") { selectedApps.removeAll(); selectedCategories.removeAll(); selectedDateFilter = nil }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appFilterPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterPopoverHeading("Apps", hasSelection: !selectedApps.isEmpty) { selectedApps.removeAll() }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(availableApps, id: \.name) { app in
                        let selected = selectedApps.contains(app.name)
                        Button {
                            if selected { selectedApps.remove(app.name) } else { selectedApps.insert(app.name) }
                        } label: {
                            HStack(spacing: 10) {
                                if let iconData = app.iconData, let image = UIImage(data: iconData) {
                                    Image(uiImage: image).resizable().frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 5))
                                } else {
                                    Image(systemName: "app.fill").frame(width: 22, height: 22).foregroundStyle(.secondary)
                                }
                                Text(app.name).foregroundStyle(.primary).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 14).frame(height: 44)
                            .background(selected ? Color.accentColor.opacity(0.12) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 290)
        .background(Color.white.opacity(0.9))
        .presentationBackground(Color.white.opacity(0.9))
        .preferredColorScheme(.light)
        .presentationCompactAdaptation(.popover)
    }

    private var typeFilterPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterPopoverHeading("Types", hasSelection: !selectedCategories.isEmpty) { selectedCategories.removeAll() }
            ForEach(filterCategories, id: \.self) { category in
                let selected = selectedCategories.contains(category)
                Button {
                    if selected { selectedCategories.remove(category) } else { selectedCategories.insert(category) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: ClipboardSearchToken.category(category).icon).frame(width: 22)
                        Text(category.searchFilterTitle).foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 14).frame(height: 42)
                    .background(selected ? Color.accentColor.opacity(0.12) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 260)
        .background(Color.white.opacity(0.9))
        .presentationBackground(Color.white.opacity(0.9))
        .preferredColorScheme(.light)
        .presentationCompactAdaptation(.popover)
    }

    private var dateFilterPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterPopoverHeading("Date", hasSelection: selectedDateFilter != nil) { selectedDateFilter = nil }
            ForEach([ClipboardDateFilter.today, .yesterday, .last7Days, .thisMonth]) { filter in
                let selected = selectedDateFilter == filter
                Button { selectedDateFilter = selected ? nil : filter } label: {
                    HStack(spacing: 10) {
                        Image(systemName: filter.icon).frame(width: 22)
                        Text(filter.rawValue).foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 14).frame(height: 42)
                    .background(selected ? Color.accentColor.opacity(0.12) : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 240)
        .background(Color.white.opacity(0.9))
        .presentationBackground(Color.white.opacity(0.9))
        .preferredColorScheme(.light)
        .presentationCompactAdaptation(.popover)
    }

    private func filterPopoverHeading(_ title: String, hasSelection: Bool, clear: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if hasSelection {
                Button("Clear", action: clear)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func filterPill(title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Capsule().fill(active ? Color.accentColor.opacity(0.1) : Color.white))
        .overlay(Capsule().stroke(active ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1))
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
                            resolvedAppIconData: appIcons.iconData(for: item),
                            onCopy: {
                                history.copy(item)
                                showToast("Copied to clipboard")
                            },
                            onCopyPlainText: {
                                history.copyAsPlainText(item)
                                showToast("Copied as plain text")
                            },
                            onQuickLook: { prepareAssetAction(for: item, action: .quickLook) },
                            onSave: { prepareAssetAction(for: item, action: .save) },
                            onShare: { share(item) },
                            onOpenLink: { openLink(item) },
                            onOpenLinkPreview: { openLinkPreview(item) },
                            onEdit: { editingItem = item },
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

    private enum CardAssetAction { case quickLook, save, share }

    private func openLink(_ item: ClipboardItem) {
        guard let text = item.contentText, let url = URL(string: text) else { return }
        UIApplication.shared.open(url)
    }

    private func openLinkPreview(_ item: ClipboardItem) {
        guard let text = item.contentText, let url = URL(string: text) else { return }
        inAppLinkURL = url
    }

    private func share(_ item: ClipboardItem) {
        if item.contentType == .url,
           let text = item.contentText,
           let url = URL(string: text) {
            sharePayload = IOSSharePayload(items: [url])
        } else {
            prepareAssetAction(for: item, action: .share)
        }
    }

    private func urlPresentationBinding(for url: Binding<URL?>) -> Binding<Bool> {
        Binding(get: { url.wrappedValue != nil }, set: { if !$0 { url.wrappedValue = nil } })
    }

    private func prepareAssetAction(for item: ClipboardItem, action: CardAssetAction) {
        guard !isPreparingCardAction else { return }
        isPreparingCardAction = true
        Task {
            defer { isPreparingCardAction = false }
            do {
                // Let UIKit finish dismissing the native context menu before
                // presenting another controller from the same interaction.
                try? await Task.sleep(for: .milliseconds(120))
                let url = try await history.materializedAssetURL(for: item)
                switch action {
                case .quickLook:
                    quickLookURL = url
                case .share:
                    if item.contentType == .image, let image = UIImage(contentsOfFile: url.path) {
                        // Sharing an image object avoids asking File Provider
                        // to resolve our short-lived temporary preview URL.
                        sharePayload = IOSSharePayload(items: [image])
                    } else {
                        sharePayload = IOSSharePayload(items: [url])
                    }
                case .save:
                    if item.contextMenuCapabilities.saveDestination == .photos {
                        try await saveToPhotos(url: url, isVideo: item.contentType == .video || item.mimeType?.lowercased().hasPrefix("video/") == true)
                        showToast("Saved to Photos")
                    } else {
                        exportURL = url
                    }
                }
            } catch {
                showToast("Couldn’t prepare this item")
            }
        }
    }

    private func saveToPhotos(url: URL, isVideo: Bool) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw CocoaError(.userCancelled)
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let resourceType: PHAssetResourceType = isVideo ? .video : .photo
            request.addResource(with: resourceType, fileURL: url, options: nil)
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
                        Label(syncDiagnostics.lastError == nil ? "Status" : "Sync needs attention", systemImage: syncDiagnostics.lastError == nil ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                            .foregroundStyle(syncDiagnostics.lastError == nil ? .green : .orange)
                        Spacer()
                        Text(syncDiagnostics.lastError == nil
                             ? (syncDiagnostics.lastSuccessfulSync == nil ? "Waiting for first sync" : "Synced")
                             : "Retrying")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Last Sync", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Text(syncDiagnostics.lastSuccessfulSync?.formatted(date: .omitted, time: .shortened) ?? "Not yet")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Last Delta", systemImage: "arrow.down.circle")
                        Spacer()
                        Text("\(syncDiagnostics.lastImportedChangeCount) updated · \(syncDiagnostics.lastDeletedChangeCount) deleted")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Sync Source", systemImage: "dot.radiowaves.left.and.right")
                        Spacer()
                        Text(syncDiagnostics.lastSyncSource)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Last Timing", systemImage: "speedometer")
                        Spacer()
                        Text("Cloud \(Int(syncDiagnostics.lastCloudFetchDuration * 1_000)) ms · apply \(Int(syncDiagnostics.lastLocalApplyDuration * 1_000)) ms")
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
