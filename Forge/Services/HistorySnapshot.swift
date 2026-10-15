import Foundation
import SwiftData

/// Immutable, value-type copy of finished training history used by Today and Progress.
/// Rebuilt after saves so screens never walk SwiftData relationships while rendering.
struct HistorySnapshot {
    struct SetEntry {
        let weight: Double
        let reps: Int
        let seconds: Int
        let isWarmup: Bool
        let isPR: Bool
    }

    struct ExerciseEntry {
        let exerciseID: String
        let name: String
        let tracking: TrackingType
        let primary: [Muscle]
        let secondary: [Muscle]
        let sets: [SetEntry]

        var workingSets: [SetEntry] { sets.filter { !$0.isWarmup } }
        var volume: Double {
            tracking == .weightReps ? workingSets.reduce(0) { $0 + $1.weight * Double($1.reps) } : 0
        }
    }

    struct SessionEntry: Identifiable {
        let id: UUID
        let modelID: PersistentIdentifier
        let name: String
        let start: Date
        let end: Date
        let splitDayID: UUID?
        let rating: Int
        let exercises: [ExerciseEntry]
        let cardioMiles: Double

        var duration: TimeInterval { end.timeIntervalSince(start) }
        var volume: Double { exercises.reduce(0) { $0 + $1.volume } }
        var workingSets: Int { exercises.reduce(0) { $0 + $1.workingSets.count } }
        var prCount: Int { exercises.reduce(0) { $0 + $1.sets.filter(\.isPR).count } }
        var muscles: [Muscle] {
            var seen = Set<Muscle>()
            return exercises.flatMap(\.primary).filter { seen.insert($0).inserted }
        }
    }

    struct CardioEntry: Identifiable {
        let id: UUID
        let date: Date
        let type: CardioType
        let distance: Double
        let duration: TimeInterval
        let splitDayID: UUID?
        let isPartOfWorkout: Bool

        var pace: Double? { distance > 0 && duration > 0 ? duration / distance : nil }
    }

    struct PREvent: Identifiable {
        let id = UUID()
        let date: Date
        let exerciseID: String
        let exerciseName: String
        let detail: String
        let value: Double
        let unit: String
    }

    struct Record: Identifiable {
        var id: String { exerciseID }
        let exerciseID: String
        let name: String
        let tracking: TrackingType
        let value: Double
        let detail: String
        let date: Date
        let sessions: Int
    }

    struct WeekBucket: Identifiable {
        var id: Date { start }
        let start: Date
        var workouts: Int = 0
        var volume: Double = 0
        var miles: Double = 0
        var minutes: Double = 0
    }

    let sessions: [SessionEntry]
    let cardio: [CardioEntry]
    let formula: OneRepMaxFormula

    static let empty = HistorySnapshot(entries: [], runs: [], formula: .brzycki)

    private init(entries: [SessionEntry], runs: [CardioEntry], formula: OneRepMaxFormula) {
        self.sessions = entries
        self.cardio = runs
        self.formula = formula
    }

    @MainActor
    init(sessions models: [WorkoutSession], cardio cardioModels: [CardioLog], formula: OneRepMaxFormula) {
        self.formula = formula
        self.sessions = models.compactMap { s in
            guard let end = s.endedAt else { return nil }
            let exercises = s.orderedExercises.map { ex in
                ExerciseEntry(
                    exerciseID: ex.exerciseID, name: ex.exerciseName, tracking: ex.tracking,
                    primary: ex.primaryMuscles, secondary: ex.secondaryMuscles,
                    sets: ex.completedSets.map {
                        SetEntry(weight: $0.weight, reps: $0.reps, seconds: $0.seconds, isWarmup: $0.isWarmup, isPR: $0.prKind != nil)
                    }
                )
            }
            return SessionEntry(id: s.id, modelID: s.persistentModelID, name: s.name, start: s.startedAt, end: end,
                                splitDayID: s.splitDayID, rating: s.rating, exercises: exercises,
                                cardioMiles: (s.cardio ?? []).reduce(0) { $0 + $1.distance })
        }
        .sorted { $0.start > $1.start }
        self.cardio = cardioModels.map {
            CardioEntry(id: $0.id, date: $0.date, type: $0.type, distance: $0.distance, duration: $0.durationSeconds,
                        splitDayID: $0.splitDayID, isPartOfWorkout: $0.session != nil)
        }
        .sorted { $0.date > $1.date }
    }

    var isEmpty: Bool { sessions.isEmpty && cardio.isEmpty }

    // MARK: - Schedule helpers

    /// (date, split day) pairs for everything completed, used to resolve today's plan.
    var completions: [(date: Date, dayID: UUID?)] {
        sessions.map { ($0.start, $0.splitDayID) } + cardio.map { ($0.date, $0.splitDayID) }
    }

    // MARK: - Aggregates

    func sessions(since date: Date) -> [SessionEntry] {
        sessions.filter { $0.start >= date }
    }

    /// Workouts plus standalone runs, the unit the weekly goal counts.
    func trainingCount(in interval: DateInterval) -> Int {
        sessions.filter { interval.contains($0.start) }.count
            + cardio.filter { !$0.isPartOfWorkout && interval.contains($0.date) }.count
    }

    func weeks(_ count: Int, calendar: Calendar = .current, now: Date = .now) -> [WeekBucket] {
        let thisWeek = calendar.startOfWeek(for: now)
        var buckets: [Date: WeekBucket] = [:]
        var starts: [Date] = []
        for i in stride(from: count - 1, through: 0, by: -1) {
            if let start = calendar.date(byAdding: .weekOfYear, value: -i, to: thisWeek) {
                buckets[start] = WeekBucket(start: start)
                starts.append(start)
            }
        }
        guard let earliest = starts.first else { return [] }
        for s in sessions where s.start >= earliest {
            let key = calendar.startOfWeek(for: s.start)
            buckets[key]?.workouts += 1
            buckets[key]?.volume += s.volume
            buckets[key]?.minutes += s.duration / 60
        }
        for c in cardio where c.date >= earliest {
            let key = calendar.startOfWeek(for: c.date)
            buckets[key]?.miles += c.distance
            if !c.isPartOfWorkout {
                buckets[key]?.workouts += 1
                buckets[key]?.minutes += c.duration / 60
            }
        }
        return starts.compactMap { buckets[$0] }
    }

    /// Weighted working sets per muscle: primary = 1, secondary = 0.5.
    func muscleSets(since date: Date) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for s in sessions where s.start >= date {
            for ex in s.exercises {
                let n = Double(ex.workingSets.count)
                guard n > 0 else { continue }
                for m in ex.primary { result[m, default: 0] += n }
                for m in ex.secondary { result[m, default: 0] += n * 0.5 }
            }
        }
        return result
    }

    func trainedDays(calendar: Calendar = .current) -> Set<Date> {
        Set(sessions.map { calendar.startOfDay(for: $0.start) } + cardio.map { calendar.startOfDay(for: $0.date) })
    }

    /// Consecutive weeks (ending this week, or last week if this one isn't done yet) meeting the goal.
    func weeklyStreak(goal: Int, calendar: Calendar = .current, now: Date = .now) -> Int {
        guard goal > 0 else { return 0 }
        let buckets = weeks(104, calendar: calendar, now: now)
        var streak = 0
        for (offset, bucket) in buckets.reversed().enumerated() {
            if bucket.workouts >= goal {
                streak += 1
            } else if offset == 0 {
                continue // the current week is still in progress
            } else {
                break
            }
        }
        return streak
    }

    func recentPRs(limit: Int) -> [PREvent] {
        var events: [PREvent] = []
        for s in sessions {
            for ex in s.exercises {
                for set in ex.sets where set.isPR {
                    let value = PRService.metric(weight: set.weight, reps: set.reps, seconds: set.seconds, tracking: ex.tracking, formula: formula) ?? 0
                    events.append(PREvent(date: s.start, exerciseID: ex.exerciseID, exerciseName: ex.name,
                                          detail: Self.setText(set, tracking: ex.tracking), value: value,
                                          unit: Self.unit(for: ex.tracking)))
                }
            }
            if events.count >= limit { break }
        }
        return Array(events.prefix(limit))
    }

    func records() -> [Record] {
        var best: [String: Record] = [:]
        var counts: [String: Int] = [:]
        for s in sessions {
            for ex in s.exercises {
                counts[ex.exerciseID, default: 0] += 1
                for set in ex.workingSets {
                    guard let value = PRService.metric(weight: set.weight, reps: set.reps, seconds: set.seconds, tracking: ex.tracking, formula: formula) else { continue }
                    if value > (best[ex.exerciseID]?.value ?? 0) {
                        best[ex.exerciseID] = Record(exerciseID: ex.exerciseID, name: ex.name, tracking: ex.tracking, value: value,
                                                     detail: Self.setText(set, tracking: ex.tracking), date: s.start, sessions: 0)
                    }
                }
            }
        }
        return best.values.map {
            Record(exerciseID: $0.exerciseID, name: $0.name, tracking: $0.tracking, value: $0.value,
                   detail: $0.detail, date: $0.date, sessions: counts[$0.exerciseID] ?? 0)
        }
        .sorted { $0.sessions > $1.sessions }
    }

    /// Exercises you've logged, most frequent first.
    func loggedExercises() -> [(id: String, name: String, tracking: TrackingType, count: Int)] {
        var info: [String: (String, TrackingType, Int)] = [:]
        for s in sessions {
            for ex in s.exercises where !ex.workingSets.isEmpty {
                let current = info[ex.exerciseID]
                info[ex.exerciseID] = (ex.name, ex.tracking, (current?.2 ?? 0) + 1)
            }
        }
        return info.map { (id: $0.key, name: $0.value.0, tracking: $0.value.1, count: $0.value.2) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    /// Best value per session for one exercise.
    func trend(for exerciseID: String) -> [TrendPoint] {
        var points: [TrendPoint] = []
        for s in sessions.reversed() {
            for ex in s.exercises where ex.exerciseID == exerciseID {
                var bestValue = 0.0
                var bestSet: SetEntry?
                for set in ex.workingSets {
                    if let v = PRService.metric(weight: set.weight, reps: set.reps, seconds: set.seconds, tracking: ex.tracking, formula: formula), v > bestValue {
                        bestValue = v
                        bestSet = set
                    }
                }
                if let bestSet {
                    points.append(TrendPoint(id: UUID(), date: s.start, value: bestValue,
                                             label: "\(Self.setText(bestSet, tracking: ex.tracking)) · \(s.start.formatted(.dateTime.month(.abbreviated).day()))"))
                }
            }
        }
        return points
    }

    static func setText(_ set: SetEntry, tracking: TrackingType) -> String {
        switch tracking {
        case .weightReps: "\(Fmt.weight(set.weight)) × \(set.reps)"
        case .bodyweight: set.weight > 0 ? "+\(Fmt.weight(set.weight)) × \(set.reps)" : "\(set.reps) reps"
        case .duration: "\(set.seconds)s"
        }
    }

    static func unit(for tracking: TrackingType) -> String {
        switch tracking {
        case .weightReps: "lb"
        case .bodyweight: "reps"
        case .duration: "sec"
        }
    }
}

@MainActor
@Observable
final class HistoryStore {
    private(set) var snapshot = HistorySnapshot.empty
    private(set) var hasLoaded = false

    func rebuild(context: ModelContext) {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt != nil }))) ?? []
        let cardio = (try? context.fetch(FetchDescriptor<CardioLog>())) ?? []
        snapshot = HistorySnapshot(sessions: sessions, cardio: cardio, formula: .current)
        hasLoaded = true
    }
}
