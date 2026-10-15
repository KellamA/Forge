import Foundation
import SwiftData

// All models are CloudKit-compatible: every attribute has a default value,
// every relationship is optional, and nothing is marked unique.

// MARK: - Plan

@Model
final class WorkoutSplit {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var isActive: Bool = false
    var scheduleModeRaw: String = ScheduleMode.weekly.rawValue
    /// Rotation mode: index of the slot that comes next.
    var rotationPosition: Int = 0
    /// Rotation mode: when the position last changed. Rest slots elapse relative to this date.
    var rotationUpdatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \SplitDay.split)
    var days: [SplitDay]? = []

    init(name: String, mode: ScheduleMode) {
        self.name = name
        self.scheduleModeRaw = mode.rawValue
    }

    var scheduleMode: ScheduleMode {
        get { ScheduleMode(rawValue: scheduleModeRaw) ?? .weekly }
        set { scheduleModeRaw = newValue.rawValue }
    }

    var orderedDays: [SplitDay] {
        (days ?? []).sorted { $0.order < $1.order }
    }

    var trainingDays: [SplitDay] {
        orderedDays.filter { $0.kind != .rest }
    }
}

@Model
final class SplitDay {
    var id: UUID = UUID()
    var name: String = ""
    var order: Int = 0
    /// Weekly mode: Calendar weekdays (1 = Sunday … 7 = Saturday).
    var weekdays: [Int] = []
    var kindRaw: String = DayKind.workout.rawValue
    /// Cardio-day details, or a cardio finisher when `includesCardio` is set on a workout day.
    var includesCardio: Bool = false
    var cardioTypeRaw: String = CardioType.outdoor.rawValue
    var cardioDistance: Double = 2.0

    var split: WorkoutSplit?

    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.day)
    var exercises: [PlannedExercise]? = []

    init(name: String, kind: DayKind, order: Int) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.order = order
    }

    var kind: DayKind {
        get { DayKind(rawValue: kindRaw) ?? .workout }
        set { kindRaw = newValue.rawValue }
    }

    var cardioType: CardioType {
        get { CardioType(rawValue: cardioTypeRaw) ?? .outdoor }
        set { cardioTypeRaw = newValue.rawValue }
    }

    var orderedExercises: [PlannedExercise] {
        (exercises ?? []).sorted { $0.order < $1.order }
    }

    /// True when this day asks for a run (cardio day, or workout day with a finisher).
    var hasCardio: Bool {
        kind == .cardio || (kind == .workout && includesCardio)
    }

    var displayName: String {
        if !name.isEmpty { return name }
        switch kind {
        case .workout: return "Workout"
        case .cardio: return "\(cardioType.displayName) Run"
        case .rest: return "Rest"
        }
    }

    /// Rough duration estimate: ~40s of work per set plus the prescribed rest.
    var estimatedMinutes: Int {
        let lifting = orderedExercises.reduce(0.0) { total, ex in
            total + Double(ex.targetSets) * (40 + Double(ex.restSeconds))
        }
        let running = hasCardio ? cardioDistance * 9 * 60 : 0
        return max(5, Int(((lifting + running) / 60).rounded()))
    }
}

@Model
final class PlannedExercise {
    var id: UUID = UUID()
    var order: Int = 0
    var exerciseID: String = ""
    var exerciseName: String = ""
    var targetSets: Int = 3
    var repLow: Int = 8
    var repHigh: Int = 12
    /// Target seconds for timed holds.
    var targetSeconds: Int = 30
    var restSeconds: Int = 120
    var notes: String = ""

    var day: SplitDay?

    init(exercise: ExerciseInfo, order: Int) {
        self.exerciseID = exercise.id
        self.exerciseName = exercise.name
        self.order = order
        let defaults = PlannedExercise.defaults(for: exercise)
        self.targetSets = defaults.sets
        self.repLow = defaults.low
        self.repHigh = defaults.high
        self.restSeconds = defaults.rest
    }

    static func defaults(for exercise: ExerciseInfo) -> (sets: Int, low: Int, high: Int, rest: Int) {
        if exercise.tracking == .duration { return (3, 30, 30, 60) }
        if exercise.isCompound { return (3, 6, 10, 150) }
        return (3, 10, 15, 75)
    }

    var repRangeText: String {
        repLow == repHigh ? "\(repLow)" : "\(repLow)–\(repHigh)"
    }
}

// MARK: - Logging

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var name: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?
    var splitID: UUID?
    var splitDayID: UUID?
    var notes: String = ""
    /// 1–5 "how did it feel", 0 when unrated.
    var rating: Int = 0
    var savedToHealth: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
    var exercises: [SessionExercise]? = []

    @Relationship(deleteRule: .cascade, inverse: \CardioLog.session)
    var cardio: [CardioLog]? = []

    init(name: String, startedAt: Date = .now) {
        self.name = name
        self.startedAt = startedAt
    }

    var isActive: Bool { endedAt == nil }

    var orderedExercises: [SessionExercise] {
        (exercises ?? []).sorted { $0.order < $1.order }
    }

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }

    var completedSets: [SetLog] {
        orderedExercises.flatMap { $0.completedSets }
    }

    var workingSetCount: Int {
        orderedExercises.reduce(0) { $0 + $1.completedSets.filter { !$0.isWarmup }.count }
    }

    var totalVolume: Double {
        orderedExercises.reduce(0) { $0 + $1.volume }
    }

    var prCount: Int {
        completedSets.filter { $0.prKind != nil }.count
    }

    var muscles: [Muscle] {
        var seen = Set<Muscle>()
        return orderedExercises.flatMap(\.primaryMuscles).filter { seen.insert($0).inserted }
    }
}

@Model
final class SessionExercise {
    var id: UUID = UUID()
    var order: Int = 0
    var exerciseID: String = ""
    var exerciseName: String = ""
    var primaryMusclesRaw: [String] = []
    var secondaryMusclesRaw: [String] = []
    var trackingRaw: String = TrackingType.weightReps.rawValue
    var targetSets: Int = 3
    var repLow: Int = 8
    var repHigh: Int = 12
    var targetSeconds: Int = 30
    var restSeconds: Int = 120
    var notes: String = ""

    var session: WorkoutSession?

    @Relationship(deleteRule: .cascade, inverse: \SetLog.exercise)
    var sets: [SetLog]? = []

    init(exercise: ExerciseInfo, order: Int) {
        self.exerciseID = exercise.id
        self.exerciseName = exercise.name
        self.primaryMusclesRaw = exercise.primary.map(\.rawValue)
        self.secondaryMusclesRaw = exercise.secondary.map(\.rawValue)
        self.trackingRaw = exercise.tracking.rawValue
        self.order = order
        let defaults = PlannedExercise.defaults(for: exercise)
        self.targetSets = defaults.sets
        self.repLow = defaults.low
        self.repHigh = defaults.high
        self.targetSeconds = exercise.tracking == .duration ? 30 : 0
        self.restSeconds = defaults.rest
    }

    var tracking: TrackingType {
        TrackingType(rawValue: trackingRaw) ?? .weightReps
    }

    var primaryMuscles: [Muscle] { primaryMusclesRaw.compactMap(Muscle.init(rawValue:)) }
    var secondaryMuscles: [Muscle] { secondaryMusclesRaw.compactMap(Muscle.init(rawValue:)) }

    var orderedSets: [SetLog] {
        (sets ?? []).sorted { $0.order < $1.order }
    }

    var completedSets: [SetLog] {
        orderedSets.filter(\.isCompleted)
    }

    var volume: Double {
        guard tracking == .weightReps else { return 0 }
        return completedSets.filter { !$0.isWarmup }.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    var targetText: String {
        if tracking == .duration { return "\(targetSets) × \(targetSeconds)s" }
        let range = repLow == repHigh ? "\(repLow)" : "\(repLow)–\(repHigh)"
        return "\(targetSets) × \(range)"
    }
}

@Model
final class SetLog {
    var id: UUID = UUID()
    var order: Int = 0
    /// Pounds. For bodyweight movements this is added load.
    var weight: Double = 0
    var reps: Int = 0
    var seconds: Int = 0
    var isWarmup: Bool = false
    var isCompleted: Bool = false
    var completedAt: Date?
    var prKindRaw: String = ""

    var exercise: SessionExercise?

    init(order: Int, weight: Double = 0, reps: Int = 0, seconds: Int = 0) {
        self.order = order
        self.weight = weight
        self.reps = reps
        self.seconds = seconds
    }

    var prKind: PRKind? {
        get { PRKind(rawValue: prKindRaw) }
        set { prKindRaw = newValue?.rawValue ?? "" }
    }
}

@Model
final class CardioLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var typeRaw: String = CardioType.outdoor.rawValue
    /// Miles.
    var distance: Double = 0
    var durationSeconds: Double = 0
    var notes: String = ""
    var splitID: UUID?
    var splitDayID: UUID?
    var savedToHealth: Bool = false

    var session: WorkoutSession?

    init(type: CardioType, distance: Double, duration: TimeInterval, date: Date = .now) {
        self.typeRaw = type.rawValue
        self.distance = distance
        self.durationSeconds = duration
        self.date = date
    }

    var type: CardioType {
        get { CardioType(rawValue: typeRaw) ?? .outdoor }
        set { typeRaw = newValue.rawValue }
    }

    /// Seconds per mile, when both distance and time were logged.
    var pace: Double? {
        guard distance > 0, durationSeconds > 0 else { return nil }
        return durationSeconds / distance
    }
}

// MARK: - Body

@Model
final class BodyWeightEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    /// Pounds.
    var weight: Double = 0
    /// Percent, 0 when not recorded.
    var bodyFat: Double = 0
    var note: String = ""
    @Attribute(.externalStorage) var photo: Data?
    /// Set when the entry was imported from Apple Health.
    var healthKitUUID: String = ""
    var savedToHealth: Bool = false

    init(weight: Double, date: Date = .now) {
        self.weight = weight
        self.date = date
    }
}

// MARK: - Library

@Model
final class CustomExercise {
    var id: UUID = UUID()
    var name: String = ""
    var primaryMusclesRaw: [String] = []
    var secondaryMusclesRaw: [String] = []
    var equipmentRaw: String = Equipment.other.rawValue
    var trackingRaw: String = TrackingType.weightReps.rawValue
    var isCompound: Bool = false
    var instructions: String = ""
    var createdAt: Date = Date()

    init(name: String) {
        self.name = name
    }

    var exerciseID: String { "custom_\(id.uuidString)" }

    var info: ExerciseInfo {
        ExerciseInfo(
            id: exerciseID,
            name: name.isEmpty ? "Untitled Exercise" : name,
            primary: primaryMusclesRaw.compactMap(Muscle.init(rawValue:)),
            secondary: secondaryMusclesRaw.compactMap(Muscle.init(rawValue:)),
            equipment: Equipment(rawValue: equipmentRaw) ?? .other,
            category: .strength,
            tracking: TrackingType(rawValue: trackingRaw) ?? .weightReps,
            instructions: instructions.split(separator: "\n").map(String.init).filter { !$0.isEmpty },
            level: nil,
            mechanic: isCompound ? "compound" : "isolation",
            aliases: [],
            isPopular: false,
            isCustom: true
        )
    }
}

@Model
final class FavoriteExercise {
    var exerciseID: String = ""
    var createdAt: Date = Date()

    init(exerciseID: String) {
        self.exerciseID = exerciseID
    }
}

enum ForgeSchema {
    static let models: [any PersistentModel.Type] = [
        WorkoutSplit.self, SplitDay.self, PlannedExercise.self,
        WorkoutSession.self, SessionExercise.self, SetLog.self, CardioLog.self,
        BodyWeightEntry.self, CustomExercise.self, FavoriteExercise.self,
    ]
}
