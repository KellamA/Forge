import SwiftData
import SwiftUI
import WidgetKit

/// Writes the widget snapshot (and body-map images) to the App Group container and reloads the
/// widgets when it changes. Runs after every history rebuild, which also follows split edits,
/// because each save bumps `DataVersion`.
@MainActor
enum WidgetSync {
    static func update(history: HistorySnapshot, context: ModelContext, library: ExerciseLibrary, now: Date = .now) {
        guard let container = WidgetShared.containerURL, let snapshotURL = WidgetShared.snapshotURL else { return }
        let split = try? context.fetch(FetchDescriptor<WorkoutSplit>(predicate: #Predicate { $0.isActive })).first
        let defaults = UserDefaults.standard
        let goal = defaults.integer(forKey: SettingsKey.weeklyGoal)
        let model = defaults.string(forKey: SettingsKey.bodyModel) ?? BodyModel.male.rawValue

        var maps: [String: [Muscle: Double]] = [:]
        let snapshot = makeSnapshot(split: split, history: history, goal: goal, library: library, now: now) { day in
            let intensities = day.muscleIntensities(in: library)
            guard day.kind == .workout, !intensities.isEmpty else { return nil }
            let file = "bodymap-\(model)-\(fingerprint(intensities)).png"
            maps[file] = intensities
            return file
        }

        let fm = FileManager.default
        var changed = false
        for (file, intensities) in maps {
            let url = container.appending(path: file)
            guard !fm.fileExists(atPath: url.path), let png = renderBodyMap(intensities) else { continue }
            try? png.write(to: url, options: .atomic)
            changed = true
        }
        let stale = ((try? fm.contentsOfDirectory(atPath: container.path)) ?? [])
            .filter { $0.hasPrefix("bodymap-") && maps[$0] == nil }
        for file in stale {
            try? fm.removeItem(at: container.appending(path: file))
        }

        guard let data = try? WidgetShared.encoder.encode(snapshot) else { return }
        if data != (try? Data(contentsOf: snapshotURL)) {
            try? data.write(to: snapshotURL, options: .atomic)
            changed = true
        }
        if changed {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Today's widget state plus one entry per upcoming midnight for the next week.
    static func makeSnapshot(split: WorkoutSplit?, history: HistorySnapshot, goal: Int, library: ExerciseLibrary,
                             now: Date = .now, calendar: Calendar = .current,
                             bodyMapFile: (SplitDay) -> String? = { _ in nil }) -> WidgetSnapshot {
        let today = calendar.startOfDay(for: now)
        let midnights = (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let completions = history.completions

        let entries = ([now] + midnights).map { date in
            let plan = SplitService.todayPlan(split: split, completions: completions, now: date, calendar: calendar)
            let (status, featured, featuredDate) = feature(plan, split: split)
            let week = calendar.dateInterval(of: .weekOfYear, for: date)
                ?? DateInterval(start: calendar.startOfWeek(for: date), duration: 7 * 86400)
            return WidgetSnapshot.Entry(
                date: calendar.startOfDay(for: date),
                status: status,
                day: featured.flatMap { day in split.map { widgetDay(day, split: $0, library: library, bodyMapFile: bodyMapFile) } },
                dayDate: featuredDate.map { calendar.startOfDay(for: $0) },
                sessionsThisWeek: history.trainingCount(in: week),
                streak: history.weeklyStreak(goal: goal, calendar: calendar, now: date)
            )
        }
        return WidgetSnapshot(weeklyGoal: goal, entries: entries)
    }

    /// Mirrors the Today tab: today's pending day, or what's next after a rest day or finished training.
    private static func feature(_ plan: TodayPlan, split: WorkoutSplit?) -> (WidgetSnapshot.PlanStatus, SplitDay?, Date?) {
        guard let split else { return (.noSplit, nil, nil) }
        guard !split.orderedDays.isEmpty else { return (.emptySplit, nil, nil) }
        if plan.isAllDoneToday || (!plan.completedToday.isEmpty && plan.days.isEmpty && !plan.isRestDay) {
            return (.doneToday, plan.nextUp, plan.nextUpDate)
        }
        if plan.isRestDay {
            return (.rest, plan.nextUp, plan.nextUpDate)
        }
        if let day = plan.pendingDays.first {
            return (split.scheduleMode == .weekly ? .today : .upNext, day, nil)
        }
        if let next = plan.nextUp {
            return (.upNext, next, plan.nextUpDate)
        }
        return (.emptySplit, nil, nil)
    }

    private static func widgetDay(_ day: SplitDay, split: WorkoutSplit, library: ExerciseLibrary,
                                  bodyMapFile: (SplitDay) -> String?) -> WidgetSnapshot.Day {
        WidgetSnapshot.Day(
            id: day.id,
            name: day.displayName,
            splitName: split.name,
            kind: day.kind.rawValue,
            symbol: day.kind == .cardio ? day.cardioType.symbol : day.kind.symbol,
            exerciseCount: day.kind == .workout ? day.orderedExercises.count : 0,
            estimatedMinutes: day.kind == .rest ? 0 : day.estimatedMinutes,
            muscles: day.kind == .workout ? day.primaryMuscles(in: library).map(\.displayName) : [],
            cardioMiles: day.hasCardio ? day.cardioDistance : nil,
            cardioType: day.hasCardio ? day.cardioType.displayName : nil,
            bodyMapFile: bodyMapFile(day)
        )
    }

    /// The same front/back figure the Today card shows, drawn for the ember gradient.
    private static func renderBodyMap(_ intensities: [Muscle: Double]) -> Data? {
        let renderer = ImageRenderer(content:
            BodyMapView(intensities: intensities, tint: .white, spacing: 4, onColor: true)
                .frame(width: 112, height: 108)
        )
        renderer.scale = 3
        renderer.isOpaque = false
        return renderer.uiImage?.pngData()
    }

    /// Stable across launches (unlike `Hasher`), so unchanged highlights reuse their image.
    private static func fingerprint(_ intensities: [Muscle: Double]) -> String {
        let key = intensities.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue):\(Int($0.value * 100))" }
            .joined(separator: ",")
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
