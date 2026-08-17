import Foundation

/// A range on the clipboard timeline. `createdAt` is the original copy time;
/// edits, folder moves, favorites, and sync activity do not affect it.
enum ClipboardHistoryRange: Equatable, Identifiable, Sendable {
    case lastHour
    case today
    case last24Hours
    case last7Days
    case last30Days
    case allHistory
    case custom(start: Date, end: Date)

    var id: String {
        switch self {
        case .lastHour: return "last-hour"
        case .today: return "today"
        case .last24Hours: return "last-24-hours"
        case .last7Days: return "last-7-days"
        case .last30Days: return "last-30-days"
        case .allHistory: return "all-history"
        case let .custom(start, end): return "custom-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
        }
    }

    var title: String {
        switch self {
        case .lastHour: return "Last Hour"
        case .today: return "Today"
        case .last24Hours: return "Last 24 Hours"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .allHistory: return "All History"
        case .custom: return "Custom Range"
        }
    }

    var isAllHistory: Bool {
        if case .allHistory = self { return true }
        return false
    }

    /// Inclusive bounds. A nil bound means the range is unbounded on that side.
    func bounds(now: Date = Date(), calendar: Calendar = .current) -> (start: Date?, end: Date?) {
        switch self {
        case .lastHour:
            return (now.addingTimeInterval(-60 * 60), now)
        case .today:
            return (calendar.startOfDay(for: now), now)
        case .last24Hours:
            return (now.addingTimeInterval(-24 * 60 * 60), now)
        case .last7Days:
            return (now.addingTimeInterval(-7 * 24 * 60 * 60), now)
        case .last30Days:
            return (now.addingTimeInterval(-30 * 24 * 60 * 60), now)
        case .allHistory:
            return (nil, nil)
        case let .custom(start, end):
            return (min(start, end), max(start, end))
        }
    }

    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let bounds = bounds(now: now, calendar: calendar)
        if let start = bounds.start, date < start { return false }
        if let end = bounds.end, date > end { return false }
        return true
    }
}

