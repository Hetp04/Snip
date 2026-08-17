import Foundation

enum ClipboardDateFilter: String, CaseIterable, Identifiable {
    case today = "Today", yesterday = "Yesterday", lastHour = "Last Hour", last24Hours = "Last 24 Hours"
    case last7Days = "Last 7 Days", lastWeek = "Last Week", last30Days = "Last 30 Days", lastMonth = "Last Month"
    case thisWeek = "This Week", thisMonth = "This Month"
    var id: String { rawValue }
    var icon: String { switch self { case .today: "sun.max"; case .lastHour: "clock"; case .last24Hours: "clock.arrow.circlepath"; default: "calendar" } }
    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today: return date >= today && date <= now
        case .yesterday:
            let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            return date >= start && date < today
        case .lastHour: return date >= now.addingTimeInterval(-3_600) && date <= now
        case .last24Hours: return date >= now.addingTimeInterval(-86_400) && date <= now
        case .last7Days: return date >= now.addingTimeInterval(-7 * 86_400) && date <= now
        case .last30Days: return date >= now.addingTimeInterval(-30 * 86_400) && date <= now
        case .thisWeek: return calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) == true
        case .lastWeek:
            guard let current = calendar.dateInterval(of: .weekOfYear, for: now) else { return false }
            return calendar.dateInterval(of: .weekOfYear, for: current.start.addingTimeInterval(-1))?.contains(date) == true
        case .thisMonth: return calendar.dateInterval(of: .month, for: now)?.contains(date) == true
        case .lastMonth:
            guard let current = calendar.dateInterval(of: .month, for: now) else { return false }
            return calendar.dateInterval(of: .month, for: current.start.addingTimeInterval(-1))?.contains(date) == true
        }
    }
}

enum ClipboardStatusFilter: String, CaseIterable, Identifiable {
    case pinned = "Pinned", unfiled = "Unfiled", recentlyAdded = "Recently Added"
    var id: String { rawValue }
    var icon: String { switch self { case .pinned: "pin"; case .unfiled: "tray"; case .recentlyAdded: "sparkles" } }
}

enum ClipboardSearchToken: Hashable, Identifiable {
    case category(ContentCategory), date(ClipboardDateFilter), sourceApp(name: String, bundleID: String?)
    case folder(id: UUID, name: String), status(ClipboardStatusFilter)
    var id: String { switch self { case .category(let v): "category:\(v.rawValue)"; case .date(let v): "date:\(v.rawValue)"; case .sourceApp(let n, let b): "app:\(b ?? n.lowercased())"; case .folder(let id, _): "folder:\(id)"; case .status(let v): "status:\(v.rawValue)" } }
    var label: String { switch self { case .category(let v): v.searchFilterTitle; case .date(let v): v.rawValue; case .sourceApp(let n, _): n; case .folder(_, let n): n; case .status(let v): v.rawValue } }
    var icon: String {
        switch self {
        case .category(.code): "chevron.left.forwardslash.chevron.right"
        case .category(let value): value.iconName
        case .date(let value): value.icon
        case .sourceApp: "app.fill"
        case .folder: "folder"
        case .status(let value): value.icon
        }
    }
    var bundleID: String? { if case .sourceApp(_, let value) = self { value } else { nil } }
    var category: String { switch self { case .category: "Type"; case .date: "Date"; case .sourceApp: "App"; case .folder: "Folder"; case .status: "Status" } }
}

extension ContentCategory {
    var searchFilterTitle: String {
        switch self {
        case .text: "Text"
        case .url: "Links"
        case .image: "Images"
        case .code: "Code"
        case .color: "Color"
        case .file: "Files"
        case .richText: "Rich Text"
        case .email: "Email"
        case .phone: "Phone Number"
        case .video: "Videos"
        default: rawValue.capitalized
        }
    }
}

struct ClipboardSearchQuery {
    var text = ""
    var tokens: [ClipboardSearchToken] = []
    var isActive: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !tokens.isEmpty }
    func matches(_ item: ClipboardItem) -> Bool {
        let terms = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard terms.allSatisfy({ item.searchableText.localizedCaseInsensitiveContains($0) }) else { return false }
        let categories = tokens.compactMap { if case .category(let v) = $0 { v } else { nil } }
        let dates = tokens.compactMap { if case .date(let v) = $0 { v } else { nil } }
        let apps = tokens.compactMap { if case .sourceApp(let n, _) = $0 { n } else { nil } }
        let folders = tokens.compactMap { if case .folder(let id, _) = $0 { id } else { nil } }
        if !categories.isEmpty && !categories.contains(ContentCategory.detect(from: item)) { return false }
        if !dates.isEmpty && !dates.contains(where: { $0.contains(item.createdAt) }) { return false }
        if !apps.isEmpty && !apps.contains(where: { $0.caseInsensitiveCompare(item.sourceAppName) == .orderedSame }) { return false }
        if !folders.isEmpty && !folders.contains(where: item.folderIDs.contains) { return false }
        for status in tokens.compactMap({ if case .status(let v) = $0 { v } else { nil } }) {
            switch status { case .pinned: if !item.isPinned { return false }; case .unfiled: if !item.folderIDs.isEmpty { return false }; case .recentlyAdded: if item.createdAt < Date().addingTimeInterval(-86_400) { return false } }
        }
        return true
    }
}

struct SearchSuggestion: Identifiable { let token: ClipboardSearchToken; let score: Int; var id: String { token.id } }
