import Foundation
import SwiftData

/// What the active split asks for today.
struct TodayPlan {
    var split: WorkoutSplit?
    /// Days to do today (weekly: everything scheduled today; rotation: the slot up next).
    var days: [SplitDay] = []
    var isRestDay = false
    /// Split days already completed today.
    var completedToday: [SplitDay] = []
    /// The next scheduled day after today's work (or after the rest day).
    var nextUp: SplitDay?
    var nextUpDate: Date?

    var pendingDays: [SplitDay] {
        days.filter { day in !completedToday.contains(where: { $0.id == day.id }) }
    }

    var isAllDoneToday: Bool {
        !completedToday.isEmpty && pendingDays.isEmpty
    }
}

@MainActor
enum SplitService {
    /// - Parameter completions: when each finished workout or run happened and which split day it was.
    static func todayPlan(split: WorkoutSplit?, completions: [(date: Date, dayID: UUID?)],
                          now: Date = .now, calendar: Calendar = .current) -> TodayPlan {
        guard let split else { return TodayPlan() }
        var plan = TodayPlan(split: split)
        let days = split.orderedDays
        guard !days.isEmpty else { return plan }

        let dayIDs = Set(days.map(\.id))
        var completedIDs = Set<UUID>()
        for completion in completions where calendar.isDate(completion.date, inSameDayAs: now) {
            if let id = completion.dayID, dayIDs.contains(id) { completedIDs.insert(id) }
        }
        plan.completedToday = days.filter { completedIDs.contains($0.id) }

        switch split.scheduleMode {
        case .weekly:
            let weekdays = days.map(\.weekdays)
            let indices = ScheduleEngine.weeklyIndices(on: now, weekdays: weekdays, calendar: calendar)
            plan.days = indices.map { days[$0] }.filter { $0.kind != .rest }
            plan.isRestDay = plan.days.isEmpty
            if let (date, next) = ScheduleEngine.nextWeeklyDate(after: now, weekdays: weekdays, calendar: calendar),
               let first = next.map({ days[$0] }).first(where: { $0.kind != .rest }) {
                plan.nextUp = first
                plan.nextUpDate = date
            }
        case .rotation:
            let kinds = days.map(\.kind)
            guard let slot = ScheduleEngine.rotationSlot(kinds: kinds, position: split.rotationPosition,
                                                          lastAdvance: split.rotationUpdatedAt, now: now, calendar: calendar) else {
                return plan
            }
            let current = days[slot.index]
            if slot.isRestDay {
                plan.isRestDay = true
                if let next = ScheduleEngine.nextTrainingIndex(kinds: kinds, from: (slot.index + 1) % days.count) {
                    plan.nextUp = days[next]
                }
            } else if current.kind == .rest {
                // Trained today; tomorrow is a rest slot.
                plan.nextUp = current
                plan.nextUpDate = calendar.date(byAdding: .day, value: 1, to: now)
            } else if plan.completedToday.isEmpty {
                plan.days = [current]
                if let next = ScheduleEngine.nextTrainingIndex(kinds: kinds, from: (slot.index + 1) % days.count), next != slot.index {
                    plan.nextUp = days[next]
                }
            } else {
                plan.nextUp = current
            }
        }
        return plan
    }

    /// Moves a rotation forward after a day from it was completed.
    static func recordCompletion(splitID: UUID?, dayID: UUID?, at date: Date, context: ModelContext) {
        guard let splitID, let dayID else { return }
        let descriptor = FetchDescriptor<WorkoutSplit>(predicate: #Predicate { $0.id == splitID })
        guard let split = try? context.fetch(descriptor).first, split.scheduleMode == .rotation else { return }
        let days = split.orderedDays
        guard let index = days.firstIndex(where: { $0.id == dayID }) else { return }
        split.rotationPosition = ScheduleEngine.position(afterCompleting: index, count: days.count)
        split.rotationUpdatedAt = date
    }

    /// Makes `split` the only active split.
    static func activate(_ split: WorkoutSplit, context: ModelContext) {
        let descriptor = FetchDescriptor<WorkoutSplit>()
        for other in (try? context.fetch(descriptor)) ?? [] where other.isActive && other.id != split.id {
            other.isActive = false
        }
        split.isActive = true
        split.rotationUpdatedAt = .now
        try? context.save()
    }

    /// Points a rotation at a specific slot ("do this one next").
    static func setNext(_ day: SplitDay, in split: WorkoutSplit) {
        guard let index = split.orderedDays.firstIndex(where: { $0.id == day.id }) else { return }
        split.rotationPosition = index
        split.rotationUpdatedAt = .now
    }

    /// Skips the current rotation slot.
    static func skip(in split: WorkoutSplit, current: SplitDay) {
        let days = split.orderedDays
        guard let index = days.firstIndex(where: { $0.id == current.id }) else { return }
        split.rotationPosition = ScheduleEngine.position(afterCompleting: index, count: days.count)
        split.rotationUpdatedAt = .now
    }

    static func renumber(_ days: [SplitDay]) {
        for (i, day) in days.enumerated() where day.order != i { day.order = i }
    }

    @discardableResult
    static func duplicate(_ split: WorkoutSplit, context: ModelContext) -> WorkoutSplit {
        let copy = WorkoutSplit(name: "\(split.name) Copy", mode: split.scheduleMode)
        context.insert(copy)
        for day in split.orderedDays {
            let d = SplitDay(name: day.name, kind: day.kind, order: day.order)
            context.insert(d)
            d.weekdays = day.weekdays
            d.includesCardio = day.includesCardio
            d.cardioTypeRaw = day.cardioTypeRaw
            d.cardioDistance = day.cardioDistance
            d.split = copy
            for ex in day.orderedExercises {
                let p = PlannedExercise(exerciseID: ex.exerciseID, name: ex.exerciseName, order: ex.order)
                context.insert(p)
                p.targetSets = ex.targetSets
                p.repLow = ex.repLow
                p.repHigh = ex.repHigh
                p.targetSeconds = ex.targetSeconds
                p.restSeconds = ex.restSeconds
                p.notes = ex.notes
                p.day = d
            }
        }
        return copy
    }
}

@MainActor
extension SplitDay {
    /// Body-map shading for the day's exercises: primary muscles full, secondary partial.
    func muscleIntensities(in library: ExerciseLibrary) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for ex in orderedExercises {
            guard let info = library.exercise(id: ex.exerciseID) else { continue }
            for m in info.secondary where result[m] == nil { result[m] = 0.45 }
            for m in info.primary { result[m] = 1 }
        }
        return result
    }

    /// Primary muscles in the order the day's exercises first work them.
    func primaryMuscles(in library: ExerciseLibrary) -> [Muscle] {
        var seen = Set<Muscle>()
        return orderedExercises
            .flatMap { library.exercise(id: $0.exerciseID)?.primary ?? [] }
            .filter { seen.insert($0).inserted }
    }
}

extension PlannedExercise {
    convenience init(exerciseID: String, name: String, order: Int) {
        self.init(exercise: ExerciseInfo.placeholder(id: exerciseID, name: name), order: order)
    }
}

extension ExerciseInfo {
    /// Used when an exercise can't be resolved (e.g. a deleted custom exercise).
    static func placeholder(id: String, name: String) -> ExerciseInfo {
        ExerciseInfo(id: id, name: name, primary: [], secondary: [], equipment: .other, category: .strength,
                     tracking: .weightReps, instructions: [], level: nil, mechanic: nil, aliases: [],
                     isPopular: false, isCustom: id.hasPrefix("custom_"))
    }
}
