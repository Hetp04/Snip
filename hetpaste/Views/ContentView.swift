import SwiftUI
import UniformTypeIdentifiers
enum NavDestination: Equatable {
    case launchpad           
    case history             
    case favorites           
    case chain
    case filteredByApp(String) 
    case filteredByType(ContentType) 
    case folder(ClipboardFolder)
    case trash               
    case settings
}
struct ContentView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @State private var destination: NavDestination = .launchpad
    @State private var showToast: Bool = false
    @State private var copiedAppName: String = ""
    @State private var toastTimer: Timer? = nil
    @State private var isSidebarVisible: Bool = true
    @State private var expandedItem: ClipboardItem? = nil
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if isSidebarVisible {
                    SidebarView(
                        destination: $destination,
                        onDropToTrash: { id in
                            if let item = viewModel.items.first(where: { $0.id == id }) {
                                viewModel.moveToTrash(item)
                            }
                        }
                    )
                    .transition(.move(edge: .leading))
                    Divider()
                        .background(Theme.divider)
                }
                mainStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: destination)
            }
            .blur(radius: expandedItem != nil ? 10 : 0)
            if let item = expandedItem {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            expandedItem = nil
                        }
                    }
                ClipboardItemRow(
                    item: item,
                    isExpanded: true,
                    onExpand: {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            expandedItem = nil
                        }
                    }
                )
                .frame(width: 700, height: 600)
                .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .zIndex(100)
            }
            if showToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Copied from \(copiedAppName)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(hex: "191919").opacity(0.95))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 10, y: 5)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(1)
            }
        }
        .frame(
            minWidth: 900, idealWidth: 900, maxWidth: .infinity,
            minHeight: 640, idealHeight: 640, maxHeight: .infinity
        )
        .background(Theme.bg)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isSidebarVisible.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .foregroundColor(Theme.textSecondary)
                }
                .help("Toggle Sidebar")
            }
        }
        .onChange(of: viewModel.focusedItemID) { _, focusedID in
            guard focusedID != nil else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                destination = .history
            }
        }
        .onChange(of: viewModel.expandedItemID) { _, expandedID in
            guard let expandedID = expandedID,
                  let item = viewModel.items.first(where: { $0.id == expandedID }) else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                expandedItem = item
                destination = .history
            }
        }
    }
    @ViewBuilder
    private var mainStage: some View {
        switch destination {
        case .launchpad:
            LaunchpadView(
                items: viewModel.items,
                onSelectApp: { selectedApp in
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    if let app = selectedApp {
                        destination = .filteredByApp(app)
                    } else {
                        destination = .history
                    }
                }
            },
                onSelectCategory: { type in
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        destination = .filteredByType(type)
                    }
                }
            )
        case .history:
            ClipboardFeedView(
                viewModel: viewModel,
                preFilteredApp: nil,
                showFavoritesOnly: false,
                onItemCopy: triggerCopyToast,
                onLaunchpadTap: { destination = .launchpad },
                onSelectFolder: { folder in destination = .folder(folder) },
                onExpandItem: { item in
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        expandedItem = item
                    }
                }
            )
        case .favorites:
            ClipboardFeedView(
                viewModel: viewModel,
                preFilteredApp: nil,
                showFavoritesOnly: true,
                onItemCopy: triggerCopyToast,
                onLaunchpadTap: { destination = .launchpad },
                onExpandItem: { item in
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        expandedItem = item
                    }
                }
            )
        case .chain:
            placeholderView(title: "Chains", icon: "link")
        case .filteredByApp(let appName):
            ClipboardFeedView(
                viewModel: viewModel,
                preFilteredApp: appName,
                preFilteredType: nil,
                showFavoritesOnly: false,
                onItemCopy: triggerCopyToast,
                onLaunchpadTap: { destination = .launchpad },
                onExpandItem: { item in
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        expandedItem = item
                    }
                }
            )
        case .filteredByType(let type):
            ClipboardFeedView(
                viewModel: viewModel,
                preFilteredApp: nil,
                preFilteredType: type,
                showFavoritesOnly: false,
                onItemCopy: triggerCopyToast,
                onLaunchpadTap: { destination = .launchpad },
                onExpandItem: { item in
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        expandedItem = item
                    }
                }
            )
        case .folder(let folder):
            ClipboardFeedView(
                viewModel: viewModel,
                selectedFolder: folder,
                showFavoritesOnly: false,
                onItemCopy: triggerCopyToast,
                onLaunchpadTap: { destination = .launchpad },
                onBackToHistory: { destination = .history },
                onExpandItem: { item in
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        expandedItem = item
                    }
                }
            )
        case .trash:
            TrashView(
                viewModel: viewModel,
                onExpandItem: { item in
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        expandedItem = item
                    }
                }
            )
        case .settings:
            SettingsView(manager: viewModel.psychoCopyManager)
        }
    }
    @ViewBuilder
    private func placeholderView(title: String, icon: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(Theme.textTertiary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            Text("Coming soon")
                .font(.system(size: 12))
                .foregroundColor(Theme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
    }
    private func triggerCopyToast(for item: ClipboardItem) {
        copiedAppName = item.sourceAppName
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            showToast = true
        }
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showToast = false
            }
        }
    }
}
struct ClipboardFeedView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    var preFilteredApp: String? = nil      
    var preFilteredType: ContentType? = nil
    var selectedFolder: ClipboardFolder? = nil
    var showFavoritesOnly: Bool = false
    let onItemCopy: (ClipboardItem) -> Void
    var onLaunchpadTap: (() -> Void)? = nil
    var onSelectFolder: ((ClipboardFolder) -> Void)? = nil
    var onBackToHistory: (() -> Void)? = nil
    var onExpandItem: ((ClipboardItem) -> Void)? = nil
    private var allItems: [ClipboardItem] { viewModel.activeItems }
    @State private var searchQuery: String = ""
    @State private var selectedDateRange: String = "All Time"
    @State private var showDatePicker: Bool = false
    @State private var selectedItemID: UUID? = nil
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var editingFolderID: UUID? = nil
    @State private var editingFolderName: String = ""
    @State private var folderToast: String?
    @State private var isGridView: Bool = true
    
    var layoutColumns: [GridItem] {
        if isGridView {
            return [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ]
        } else {
            return [
                GridItem(.flexible(), spacing: 16)
            ]
        }
    }
    var filteredItems: [ClipboardItem] {
        var result = allItems
        if showFavoritesOnly {
            result = result.filter { $0.isPinned }
        }
        if let selectedFolder {
            result = result.filter { $0.folderID == selectedFolder.id }
        }
        if let app = preFilteredApp {
            result = result.filter { $0.sourceAppName.lowercased() == app.lowercased() }
        }
        if let type = preFilteredType {
            result = result.filter { $0.contentType == type }
        }
        if !searchQuery.isEmpty {
            result = result.filter {
                ($0.contentText?.localizedCaseInsensitiveContains(searchQuery) ?? false) ||
                $0.sourceAppName.localizedCaseInsensitiveContains(searchQuery)
            }
        }
        let cal = Calendar.current
        switch selectedDateRange {
        case "Today":        result = result.filter { cal.isDateInToday($0.createdAt) }
        case "Yesterday":    result = result.filter { cal.isDateInYesterday($0.createdAt) }
        case "Last 7 Days":
            let cutoff = Date().addingTimeInterval(-7 * 86400)
            result = result.filter { $0.createdAt >= cutoff }
        default: break
        }
        return result
    }
    var mostRecentID: UUID? { filteredItems.first?.id }
    var todayItems:     [ClipboardItem] { filteredItems.filter { Calendar.current.isDateInToday($0.createdAt) } }
    var yesterdayItems: [ClipboardItem] { filteredItems.filter { Calendar.current.isDateInYesterday($0.createdAt) } }
    var thisWeekItems: [ClipboardItem] {
        let cal = Calendar.current
        let startOfWeek = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return filteredItems.filter { 
            !cal.isDateInToday($0.createdAt) &&
            !cal.isDateInYesterday($0.createdAt) &&
            $0.createdAt >= startOfWeek
        }
    }
    var olderItems: [ClipboardItem] {
        let cal = Calendar.current
        let startOfWeek = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return filteredItems.filter { 
            $0.createdAt < startOfWeek
        }
    }
    private var feedTitle: String {
        if showFavoritesOnly { return "Favorites" }
        if let selectedFolder { return selectedFolder.name }
        if let type = preFilteredType {
            switch type {
            case .url: return "Links"
            case .image: return "Images"
            case .video: return "Videos"
            case .file: return "Files"
            case .text: return "Code Snippets"
            case .richText: return "Rich Text"
            }
        }
        if let app = preFilteredApp { return app }
        return "All History"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    if selectedFolder != nil {
                        Button(action: { onBackToHistory?() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Theme.textSecondary)
                                .frame(width: 26, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color(hex: "#F7F7F5"))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Back to All History")
                    }
                    Text(feedTitle)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: { showDatePicker = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 13, weight: .semibold))
                                if selectedDateRange != "All Time" {
                                    Text(selectedDateRange)
                                        .font(.system(size: 10, weight: .semibold))
                                }
                            }
                            .foregroundColor(selectedDateRange == "All Time" ? Theme.textTertiary : Theme.accent)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 32, minHeight: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(hex: "#F6F6F6"))
                                    .softInnerShadow(RoundedRectangle(cornerRadius: 10), darkShadow: Color(hex: "#A3B1C6").opacity(0.6), lightShadow: Color.white, spread: 0.15, radius: 6)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Filter by date")
                        .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                            datePickerPopover
                        }
                        
                        // Slider toggle for List/Grid
                        HStack(spacing: 0) {
                            Button(action: { withAnimation { isGridView = false } }) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(!isGridView ? Theme.accent : Theme.textTertiary)
                                    .frame(width: 32, height: 26)
                                    .background(
                                        !isGridView ? Capsule().fill(Color(hex: "#F6F6F6")).softOuterShadow(darkShadow: Color(hex: "#A3B1C6").opacity(0.4), lightShadow: Color.white, offset: 2, radius: 4) : nil
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("List view")
                            
                            Button(action: { withAnimation { isGridView = true } }) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(isGridView ? Theme.accent : Theme.textTertiary)
                                    .frame(width: 32, height: 26)
                                    .background(
                                        isGridView ? Capsule().fill(Color(hex: "#F6F6F6")).softOuterShadow(darkShadow: Color(hex: "#A3B1C6").opacity(0.4), lightShadow: Color.white, offset: 2, radius: 4) : nil
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Grid view")
                        }
                        .padding(3)
                        .background(
                            Capsule()
                                .fill(Color(hex: "#F6F6F6"))
                                .softInnerShadow(Capsule(), darkShadow: Color(hex: "#A3B1C6").opacity(0.6), lightShadow: Color.white, spread: 0.15, radius: 6)
                        )
                    }
                }
                SearchBarView(text: $searchQuery)
                if let selectedID = selectedItemID, let item = allItems.first(where: { $0.id == selectedID }), item.sourceAppName.lowercased() == "finder" {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                        Text(path(for: item))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.05))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
            Divider().background(Theme.divider)
            ScrollView {
                if viewModel.isLoading && allItems.isEmpty {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 80)
                        ProgressView()
                        Text("Loading from Supabase…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                } else if let error = viewModel.loadError, allItems.isEmpty {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 80)
                        Image(systemName: "exclamationmark.icloud")
                            .font(.system(size: 32))
                            .foregroundColor(Theme.textTertiary)
                        Text("Couldn't load history")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity)
                } else if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 80)
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 32))
                            .foregroundColor(Theme.textTertiary)
                        Text("Nothing copied yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textTertiary)
                        Text("Copy something and it'll show up here.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        if shouldShowFolders {
                            folderSection
                        }
                        if !todayItems.isEmpty     { gridSection("Today",     items: todayItems) }
                        if !yesterdayItems.isEmpty { gridSection("Yesterday", items: yesterdayItems) }
                        if !thisWeekItems.isEmpty  { gridSection("This Week", items: thisWeekItems) }
                        if !olderItems.isEmpty     { gridSection("Older",     items: olderItems) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(Theme.bg)
        .onAppear {
            selectedItemID = viewModel.focusedItemID
        }
        .onChange(of: viewModel.focusedItemID) { _, focusedID in
            guard let focusedID else { return }
            selectedItemID = focusedID
        }
    }
    private var shouldShowFolders: Bool {
        selectedFolder == nil &&
        preFilteredApp == nil &&
        preFilteredType == nil &&
        !showFavoritesOnly &&
        searchQuery.isEmpty &&
        selectedDateRange == "All Time"
    }
    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Folders")
            if let error = viewModel.loadError {
                Text("Folder sync error: \(error)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.red.opacity(0.82))
                    .padding(.horizontal, 2)
            }
            LazyVGrid(columns: layoutColumns, spacing: 16) {
                ForEach(viewModel.folders) { folder in
                    FolderCardView(
                        folder: folder,
                        itemCount: viewModel.itemCount(in: folder),
                        isEditing: editingFolderID == folder.id,
                        editingName: $editingFolderName,
                        onOpen: { onSelectFolder?(folder) },
                        onBeginRename: {
                            editingFolderID = folder.id
                            editingFolderName = folder.name
                        },
                        onCommitRename: {
                            viewModel.renameFolder(folder, name: editingFolderName)
                            editingFolderID = nil
                        },
                        onDelete: {
                            viewModel.deleteFolder(folder)
                        },
                        onDropItems: { itemIDs in
                            viewModel.assignItems(itemIDs, to: folder)
                            folderToast = itemIDs.count == 1
                                ? "Added to \(folder.name)"
                                : "\(itemIDs.count) items added to \(folder.name)"
                        }
                    )
                }
                NewFolderCardView {
                    let folder = viewModel.createFolder()
                    editingFolderID = folder.id
                    editingFolderName = folder.name
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let folderToast {
                Text(folderToast)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#191919").opacity(0.94)))
                    .padding(.bottom, -8)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                self.folderToast = nil
                            }
                        }
                    }
            }
        }
    }
    @ViewBuilder
    private func gridSection(_ title: String, items: [ClipboardItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            LazyVGrid(columns: layoutColumns, spacing: 16) {
                ForEach(items) { item in
                    gridItemRow(item)
                }
            }
        }
    }
    private func gridItemRow(_ item: ClipboardItem) -> some View {
        ClipboardItemRow(
            item: item,
            isSelected: selectedItemID == item.id,
            isMostRecent: item.id == mostRecentID,
            onToggleFavorite: { viewModel.toggleFavorite(item) },
            onRetrySync: { viewModel.retrySync(item) },
            onCopy: {
                selectedItemID = item.id
                viewModel.copyToPasteboard(item)
                onItemCopy(item)
            },
            onDelete: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if selectedFolder != nil {
                        viewModel.removeFromFolder(item)
                    } else {
                        viewModel.deleteItem(item)
                    }
                }
            },
            onTrash: { viewModel.moveToTrash(item) },
            onExpand: { onExpandItem?(item) },
            onPrimaryTap: {
                selectedItemID = item.id
                selectedItemIDs = [item.id]
                viewModel.copyToPasteboard(item)
                onItemCopy(item)
            }
        )
        .onDrag {
            let ids = selectedItemIDs.contains(item.id) ? Array(selectedItemIDs) : [item.id]
            return viewModel.folderDragItemProvider(for: ids)
        }
        .onAppear {
            if item.contentType == .image {
                viewModel.loadLocalDataIfNeeded(for: item)
            }
        }
    }
    private func path(for item: ClipboardItem) -> String {
        if let url = item.revealableFileURL {
            return url.path
        }
        if item.contentType == .url, let text = item.contentText, URL(string: text) != nil {
            return text
        }
        if let storagePath = item.storagePath {
            return storagePath
        }
        if let text = item.contentText {
            let truncated = String(text.prefix(50)).replacingOccurrences(of: "\n", with: " ")
            return "\(item.sourceAppName) • \(truncated)..."
        }
        return item.sourceAppName
    }
    private var datePickerPopover: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(["All Time", "Today", "Yesterday", "Last 7 Days"], id: \.self) { range in
                Button(action: {
                    selectedDateRange = range
                    showDatePicker = false
                }) {
                    HStack {
                        Text(range)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        if selectedDateRange == range {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .frame(width: 140, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .background(Theme.bg)
    }
}
struct FolderCardView: View {
    let folder: ClipboardFolder
    let itemCount: Int
    let isEditing: Bool
    @Binding var editingName: String
    let onOpen: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onDelete: () -> Void
    let onDropItems: ([UUID]) -> Void
    @State private var isTargeted: Bool = false
    @FocusState private var isNameFocused: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Color(hex: "#3A3A3C"))
            if isEditing {
                TextField("Folder name", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#1C1C1E"))
                    .focused($isNameFocused)
                    .onSubmit(onCommitRename)
            } else {
                Text(folder.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#1C1C1E"))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Button {
                onBeginRename()
            } label: {
                Image(systemName: "ellipsis.vertical")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#3A3A3C"))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Rename", action: onBeginRename)
                Button("Delete Folder", role: .destructive, action: onDelete)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.selection)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isTargeted ? Theme.accent : Color.clear, lineWidth: isTargeted ? 1.5 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                onOpen()
            }
        }
        .contextMenu {
            Button("Rename", action: onBeginRename)
            Button("Delete Folder", role: .destructive, action: onDelete)
        }
        .onDrop(of: [UTType.hetpasteFolderItemIDs], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            loadClipboardItemIDs(from: provider)
            return true
        }
        .onAppear {
            if isEditing {
                isNameFocused = true
            }
        }
        .onChange(of: isEditing) { _, newValue in
            isNameFocused = newValue
        }
    }
    private func loadClipboardItemIDs(from provider: NSItemProvider) {
        let identifiers = [UTType.hetpasteFolderItemIDs.identifier, UTType.utf8PlainText.identifier, UTType.text.identifier]
        guard let identifier = identifiers.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
            return
        }
        provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
            let raw: String?
            if let data = item as? Data {
                raw = String(data: data, encoding: .utf8)
            } else if let string = item as? String {
                raw = string
            } else if let string = item as? NSString {
                raw = string as String
            } else {
                raw = nil
            }
            let ids = (raw ?? "")
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
            guard !ids.isEmpty else { return }
            DispatchQueue.main.async {
                onDropItems(ids)
            }
        }
    }
}
struct NewFolderCardView: View {
    let onCreate: () -> Void
    var body: some View {
        Button(action: onCreate) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color(hex: "#3A3A3C"))
                Text("New Folder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#1C1C1E"))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.selection)
            )
        }
        .buttonStyle(.plain)
    }
}
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(Theme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.leading, 2)
    }
}
#Preview {
    ContentView(viewModel: ClipboardHistoryViewModel())
}