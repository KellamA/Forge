import Foundation
import SwiftData

/// Generates realistic sample history for previewing the app.
@MainActor
enum DemoData {
    /// Launch arguments: `-seedDemoData` fills an empty store; `-skipOnboarding` skips the welcome flow.
    static func seedIfRequested(context: ModelContext) async {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-skipOnboarding") || args.contains("-seedDemoData") {
            UserDefaults.standard.set(true, forKey: SettingsKey.hasOnboarded)
        }
        guard args.contains("-seedDemoData") else { return }
        let count = (try? context.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
        guard count == 0 else { return }
        generate(context: context, library: ExerciseLibrary())
    }

    private struct SeededRandom: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    /// Starting working weight for demo lifts (lb).
    private static let startWeights: [String: Double] = [
        "Barbell_Bench_Press_-_Medium_Grip": 165, "Incline_Dumbbell_Press": 55, "Seated_Dumbbell_Press": 45,
        "Side_Lateral_Raise": 17.5, "Triceps_Pushdown_-_Rope_Attachment": 45, "Cable_Rope_Overhead_Triceps_Extension": 40,
        "Pullups": 0, "Bent_Over_Barbell_Row": 135, "Wide-Grip_Lat_Pulldown": 120, "Seated_Cable_Rows": 120,
        "Face_Pull": 40, "Barbell_Curl": 65, "Hammer_Curls": 30, "Barbell_Squat": 205, "Romanian_Deadlift": 165,
        "Leg_Press": 290, "Lying_Leg_Curls": 90, "Leg_Extensions": 100, "Standing_Calf_Raises": 160,
    ]

    static func generate(context: ModelContext, library: ExerciseLibrary) {
        var rng = SeededRandom(state: 42)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        let split = SplitTemplate.pushPullLegs.instantiate(in: context, library: library, activate: true)
        SplitTemplate.upperLower.instantiate(in: context, library: library, activate: false)
        let days = split.orderedDays

        // 12 weeks of training, ~4 sessions a week, rotating Push/Pull/Legs.
        let weeks = 12
        let trainingOffsets = [0, 1, 3, 5] // Mon, Tue, Thu, Sat relative to week start
        var rotationIndex = 0
        guard let firstWeek = calendar.date(byAdding: .weekOfYear, value: -weeks, to: calendar.startOfWeek(for: today)) else { return }
        var lastSession: WorkoutSession?
        var lastDayIndex = 0

        for week in 0...weeks {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: week, to: firstWeek) else { continue }
            for offset in trainingOffsets {
                guard let dayDate = calendar.date(byAdding: .day, value: offset + 1, to: weekStart), dayDate < today else { continue }
                if Double.random(in: 0...1, using: &rng) < 0.08 { continue } // the occasional missed day
                let day = days[rotationIndex % days.count]
                let hour = Int.random(in: 6...18, using: &rng)
                let start = calendar.date(bySettingHour: hour, minute: Int.random(in: 0...50, using: &rng), second: 0, of: dayDate)!
                let session = WorkoutSession(name: day.displayName, startedAt: start)
                context.insert(session)
                session.splitID = split.id
                session.splitDayID = day.id
                session.rating = Int.random(in: 3...5, using: &rng)

                var clock = start.addingTimeInterval(240)
                let progress = Double(week) + Double(offset) / 7
                for (i, planned) in day.orderedExercises.enumerated() {
                    guard let info = library.exercise(id: planned.exerciseID) else { continue }
                    let ex = SessionExercise(exercise: info, order: i)
                    context.insert(ex)
                    ex.session = session
                    ex.targetSets = planned.targetSets
                    ex.repLow = planned.repLow
                    ex.repHigh = planned.repHigh
                    ex.restSeconds = planned.restSeconds
                    let base = startWeights[planned.exerciseID] ?? 50
                    let step: Double = base >= 100 ? 5 : 2.5
                    let raw = base * (1 + 0.011 * progress)
                    let weight = (raw / step).rounded() * step
                    for s in 0..<planned.targetSets {
                        let set = SetLog(order: s)
                        context.insert(set)
                        set.exercise = ex
                        if info.tracking == .bodyweight {
                            set.reps = min(15, 6 + Int(progress / 3) - s / 2 + Int.random(in: -1...1, using: &rng))
                        } else {
                            set.weight = weight
                            let fatigue = s >= 2 ? Int.random(in: 0...2, using: &rng) : 0
                            set.reps = max(planned.repLow - 1, min(planned.repHigh, planned.repLow + Int.random(in: 0...3, using: &rng) - fatigue))
                        }
                        clock = clock.addingTimeInterval(Double(planned.restSeconds) + 45)
                        set.isCompleted = true
                        set.completedAt = clock
                    }
                }
                session.endedAt = clock.addingTimeInterval(120)
                lastSession = session
                lastDayIndex = rotationIndex % days.count
                rotationIndex += 1
            }

            // Sunday run
            if let sunday = calendar.date(byAdding: .day, value: 7, to: weekStart), sunday < today {
                let miles = [3.0, 3.1, 3.5, 4.0][Int.random(in: 0...3, using: &rng)]
                let pace = 560 - Double(week) * 4 + Double.random(in: -12...12, using: &rng)
                let date = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: sunday)!
                let log = CardioLog(type: week % 3 == 0 ? .track : .outdoor, distance: miles, duration: miles * pace, date: date)
                context.insert(log)
            }
        }

        if let lastSession, let end = lastSession.endedAt {
            split.rotationPosition = ScheduleEngine.position(afterCompleting: lastDayIndex, count: days.count)
            split.rotationUpdatedAt = end
        }

        // Body weight: near-daily weigh-ins trending down with daily noise.
        let totalDays = weeks * 7 + 5
        for d in stride(from: totalDays, through: 0, by: -1) {
            if Double.random(in: 0...1, using: &rng) < 0.18 { continue }
            guard let date = calendar.date(byAdding: .day, value: -d, to: today),
                  let morning = calendar.date(bySettingHour: 7, minute: Int.random(in: 0...40, using: &rng), second: 0, of: date) else { continue }
            let trend = 192.0 - 7.5 * (Double(totalDays - d) / Double(totalDays))
            let weight = ((trend + Double.random(in: -0.9...0.9, using: &rng)) * 10).rounded() / 10
            let entry = BodyWeightEntry(weight: weight, date: morning)
            context.insert(entry)
        }

        UserDefaults.standard.set(180.0, forKey: SettingsKey.goalWeight)
        PRService.recomputeAll(context: context)
        try? context.save()
    }

    /// Deletes every record in the store.
    static func eraseAll(context: ModelContext) {
        try? context.delete(model: SetLog.self)
        try? context.delete(model: SessionExercise.self)
        try? context.delete(model: CardioLog.self)
        try? context.delete(model: WorkoutSession.self)
        try? context.delete(model: PlannedExercise.self)
        try? context.delete(model: SplitDay.self)
        try? context.delete(model: WorkoutSplit.self)
        try? context.delete(model: BodyWeightEntry.self)
        try? context.delete(model: CustomExercise.self)
        try? context.delete(model: FavoriteExercise.self)
        try? context.save()
    }
}
