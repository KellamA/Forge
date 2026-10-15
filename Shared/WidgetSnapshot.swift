import Foundation

/// Small summary the app writes to the App Group container for the Home and Lock Screen widgets.
/// The widget extension can't open the SwiftData store, so this is everything it knows.
struct WidgetSnapshot: Codable, Equatable {
    /// What the widgets show from `date` on. The app precomputes today plus the next week of midnights,
    /// assuming no new training, so rest days and week rollovers update without the app running.
    struct Entry: Codable, Equatable {
        var date: Date
        var status: PlanStatus
        /// The day to feature: today's workout, or the next one after a rest day or finished training.
        var day: Day?
        /// When `day` is scheduled, if that's not today.
        var dayDate: Date?
        var sessionsThisWeek: Int
        var streak: Int
    }

    enum PlanStatus: String, Codable {
        case noSplit, emptySplit, today, upNext, rest, doneToday
    }

    struct Day: Codable, Equatable {
        var id: UUID
        var name: String
        var splitName: String
        /// `DayKind` raw value: workout, cardio or rest.
        var kind: String
        var symbol: String
        var exerciseCount: Int
        var estimatedMinutes: Int
        /// Primary muscles in the order the exercises work them.
        var muscles: [String]
        var cardioMiles: Double?
        var cardioType: String?
        /// File in the App Group container with this day's body-map highlight, rendered by the app.
        var bodyMapFile: String?
    }

    var weeklyGoal: Int
    var entries: [Entry]

    /// The entry in effect at `date`.
    func entry(at date: Date) -> Entry? {
        entries.last { $0.date <= date } ?? entries.first
    }
}

enum WidgetShared {
    static let appGroup = "group.com.kellamadams.forge"
    static let todayURL = URL(string: "forge://today")!
    static let upNextKind = "UpNextWidget"
    static let thisWeekKind = "ThisWeekWidget"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var snapshotURL: URL? {
        containerURL?.appending(path: "widget-snapshot.json")
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
