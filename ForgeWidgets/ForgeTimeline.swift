import SwiftUI
import WidgetKit

/// Colors from the app's Theme (the widget extension doesn't compile Forge/Design).
enum WidgetTheme {
    static let ember = Color(red: 1.0, green: 0.42, blue: 0.10)
    static let flame = Color(red: 0.96, green: 0.24, blue: 0.19)
    static let gold = Color(red: 1.0, green: 0.74, blue: 0.24)

    static let accentGradient = LinearGradient(
        colors: [gold, ember, flame], startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let ringGradient = AngularGradient(colors: [gold, ember, flame, gold], center: .center)

    static let cardioGradient = LinearGradient(
        colors: [Color(red: 0.35, green: 0.85, blue: 1.0), Color(red: 0.16, green: 0.72, blue: 0.98), Color(red: 0.20, green: 0.45, blue: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let restGradient = LinearGradient(
        colors: [Color(red: 0.55, green: 0.60, blue: 1.0), Color(red: 0.40, green: 0.32, blue: 0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

struct ForgeEntry: TimelineEntry {
    let date: Date
    /// Nil until the app has written its first snapshot.
    let state: WidgetSnapshot.Entry?
    let weeklyGoal: Int

    static let sample = ForgeEntry(
        date: .now,
        state: WidgetSnapshot.Entry(
            date: .now, status: .upNext,
            day: WidgetSnapshot.Day(id: UUID(), name: "Push", splitName: "Push Pull Legs", kind: "workout",
                                    symbol: "dumbbell.fill", exerciseCount: 6, estimatedMinutes: 55,
                                    muscles: ["Chest", "Shoulders", "Triceps"], cardioMiles: nil, cardioType: nil,
                                    bodyMapFile: nil),
            dayDate: nil, sessionsThisWeek: 3, streak: 5
        ),
        weeklyGoal: 4
    )
}

/// Reads the snapshot the app keeps in the App Group container. The app precomputes an entry for each
/// upcoming midnight, so the timeline is just those entries; the app reloads it whenever its data changes.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> ForgeEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (ForgeEntry) -> Void) {
        guard let snapshot = WidgetShared.load() else {
            completion(context.isPreview ? .sample : ForgeEntry(date: .now, state: nil, weeklyGoal: 0))
            return
        }
        completion(ForgeEntry(date: .now, state: snapshot.entry(at: .now), weeklyGoal: snapshot.weeklyGoal))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ForgeEntry>) -> Void) {
        let now = Date.now
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        guard let snapshot = WidgetShared.load() else {
            completion(Timeline(entries: [ForgeEntry(date: now, state: nil, weeklyGoal: 0)], policy: .after(tomorrow)))
            return
        }
        let upcoming = snapshot.entries.filter { $0.date > now }
        let entries = [ForgeEntry(date: now, state: snapshot.entry(at: now), weeklyGoal: snapshot.weeklyGoal)]
            + upcoming.map { ForgeEntry(date: $0.date, state: $0, weeklyGoal: snapshot.weeklyGoal) }
        completion(Timeline(entries: entries, policy: upcoming.isEmpty ? .after(tomorrow) : .atEnd))
    }
}
