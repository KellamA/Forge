import Foundation
import SwiftData

/// Ready-made splits users can start from.
struct SplitTemplate: Identifiable {
    struct Lift {
        let id: String
        let sets: Int
        let low: Int
        let high: Int
        let rest: Int
        var seconds: Int = 30
    }

    struct Day {
        let name: String
        var kind: DayKind = .workout
        var weekdays: [Int] = []
        var lifts: [Lift] = []
        var cardio: (CardioType, Double)? = nil
    }

    let id: String
    let name: String
    let summary: String
    let icon: String
    let mode: ScheduleMode
    let days: [Day]

    var daysPerWeek: String {
        switch mode {
        case .weekly:
            let count = Set(days.flatMap(\.weekdays)).count
            return "\(count) days / week"
        case .rotation:
            return "\(days.filter { $0.kind != .rest }.count)-day rotation"
        }
    }

    @MainActor
    @discardableResult
    func instantiate(in context: ModelContext, library: ExerciseLibrary, activate: Bool) -> WorkoutSplit {
        let split = WorkoutSplit(name: name, mode: mode)
        context.insert(split)
        for (i, dayTemplate) in days.enumerated() {
            let day = SplitDay(name: dayTemplate.name, kind: dayTemplate.kind, order: i)
            context.insert(day)
            day.weekdays = dayTemplate.weekdays
            if let (type, distance) = dayTemplate.cardio {
                day.cardioType = type
                day.cardioDistance = distance
                if dayTemplate.kind == .workout { day.includesCardio = true }
            }
            day.split = split
            for (j, lift) in dayTemplate.lifts.enumerated() {
                guard let info = library.exercise(id: lift.id) else { continue }
                let planned = PlannedExercise(exercise: info, order: j)
                context.insert(planned)
                planned.targetSets = lift.sets
                planned.repLow = lift.low
                planned.repHigh = lift.high
                planned.restSeconds = lift.rest
                planned.targetSeconds = lift.seconds
                planned.day = day
            }
        }
        if activate {
            SplitService.activate(split, context: context)
        }
        try? context.save()
        return split
    }

    // Calendar weekdays: 1 Sun, 2 Mon, 3 Tue, 4 Wed, 5 Thu, 6 Fri, 7 Sat
    static let all: [SplitTemplate] = [pushPullLegs, upperLower, fullBody, broSplit]

    static let pushPullLegs = SplitTemplate(
        id: "ppl", name: "Push Pull Legs",
        summary: "The classic hypertrophy rotation. Train as often as you like; it picks up where you left off.",
        icon: "arrow.triangle.2.circlepath", mode: .rotation,
        days: [
            Day(name: "Push", lifts: [
                Lift(id: "Barbell_Bench_Press_-_Medium_Grip", sets: 4, low: 6, high: 8, rest: 180),
                Lift(id: "Incline_Dumbbell_Press", sets: 3, low: 8, high: 10, rest: 120),
                Lift(id: "Seated_Dumbbell_Press", sets: 3, low: 8, high: 10, rest: 120),
                Lift(id: "Side_Lateral_Raise", sets: 3, low: 12, high: 15, rest: 60),
                Lift(id: "Triceps_Pushdown_-_Rope_Attachment", sets: 3, low: 10, high: 12, rest: 60),
                Lift(id: "Cable_Rope_Overhead_Triceps_Extension", sets: 3, low: 10, high: 12, rest: 60),
            ]),
            Day(name: "Pull", lifts: [
                Lift(id: "Pullups", sets: 3, low: 6, high: 10, rest: 150),
                Lift(id: "Bent_Over_Barbell_Row", sets: 4, low: 6, high: 8, rest: 150),
                Lift(id: "Wide-Grip_Lat_Pulldown", sets: 3, low: 8, high: 12, rest: 90),
                Lift(id: "Seated_Cable_Rows", sets: 3, low: 10, high: 12, rest: 90),
                Lift(id: "Face_Pull", sets: 3, low: 12, high: 15, rest: 60),
                Lift(id: "Barbell_Curl", sets: 3, low: 8, high: 12, rest: 60),
                Lift(id: "Hammer_Curls", sets: 3, low: 10, high: 12, rest: 60),
            ]),
            Day(name: "Legs", lifts: [
                Lift(id: "Barbell_Squat", sets: 4, low: 6, high: 8, rest: 180),
                Lift(id: "Romanian_Deadlift", sets: 3, low: 8, high: 10, rest: 150),
                Lift(id: "Leg_Press", sets: 3, low: 10, high: 12, rest: 120),
                Lift(id: "Lying_Leg_Curls", sets: 3, low: 10, high: 12, rest: 90),
                Lift(id: "Leg_Extensions", sets: 3, low: 12, high: 15, rest: 60),
                Lift(id: "Standing_Calf_Raises", sets: 4, low: 10, high: 15, rest: 60),
            ]),
        ]
    )

    static let upperLower = SplitTemplate(
        id: "upper-lower", name: "Upper / Lower",
        summary: "Four lifting days a week plus a Saturday run. Great balance of strength and size.",
        icon: "square.split.1x2", mode: .weekly,
        days: [
            Day(name: "Upper A", weekdays: [2], lifts: [
                Lift(id: "Barbell_Bench_Press_-_Medium_Grip", sets: 4, low: 6, high: 8, rest: 180),
                Lift(id: "Bent_Over_Barbell_Row", sets: 4, low: 6, high: 8, rest: 150),
                Lift(id: "Standing_Military_Press", sets: 3, low: 8, high: 10, rest: 120),
                Lift(id: "Wide-Grip_Lat_Pulldown", sets: 3, low: 10, high: 12, rest: 90),
                Lift(id: "Side_Lateral_Raise", sets: 3, low: 12, high: 15, rest: 60),
                Lift(id: "Barbell_Curl", sets: 2, low: 10, high: 12, rest: 60),
                Lift(id: "Triceps_Pushdown", sets: 2, low: 10, high: 12, rest: 60),
            ]),
            Day(name: "Lower A", weekdays: [3], lifts: [
                Lift(id: "Barbell_Squat", sets: 4, low: 6, high: 8, rest: 180),
                Lift(id: "Romanian_Deadlift", sets: 3, low: 8, high: 10, rest: 150),
                Lift(id: "Leg_Press", sets: 3, low: 10, high: 12, rest: 120),
                Lift(id: "Seated_Leg_Curl", sets: 3, low: 10, high: 12, rest: 90),
                Lift(id: "Standing_Calf_Raises", sets: 4, low: 10, high: 15, rest: 60),
                Lift(id: "Cable_Crunch", sets: 3, low: 12, high: 15, rest: 60),
            ]),
            Day(name: "Upper B", weekdays: [5], lifts: [
                Lift(id: "Incline_Dumbbell_Press", sets: 4, low: 8, high: 10, rest: 150),
                Lift(id: "One-Arm_Dumbbell_Row", sets: 3, low: 8, high: 12, rest: 90),
                Lift(id: "Seated_Dumbbell_Press", sets: 3, low: 8, high: 10, rest: 120),
                Lift(id: "Cable_Crossover", sets: 3, low: 12, high: 15, rest: 60),
                Lift(id: "Face_Pull", sets: 3, low: 12, high: 15, rest: 60),
                Lift(id: "Hammer_Curls", sets: 3, low: 10, high: 12, rest: 60),
                Lift(id: "Cable_Rope_Overhead_Triceps_Extension", sets: 3, low: 10, high: 12, rest: 60),
            ]),
            Day(name: "Lower B", weekdays: [6], lifts: [
                Lift(id: "Barbell_Deadlift", sets: 3, low: 5, high: 5, rest: 210),
                Lift(id: "forge_bulgarian_split_squat", sets: 3, low: 8, high: 10, rest: 120),
                Lift(id: "Barbell_Hip_Thrust", sets: 3, low: 8, high: 12, rest: 120),
                Lift(id: "Leg_Extensions", sets: 3, low: 12, high: 15, rest: 60),
                Lift(id: "Lying_Leg_Curls", sets: 3, low: 10, high: 12, rest: 60),
                Lift(id: "Seated_Calf_Raise", sets: 4, low: 12, high: 15, rest: 60),
            ]),
            Day(name: "Long Run", kind: .cardio, weekdays: [7], cardio: (.outdoor, 3.0)),
        ]
    )

    static let fullBody = SplitTemplate(
        id: "full-body", name: "Full Body 3×",
        summary: "Three full-body sessions plus a track day. Efficient and beginner friendly.",
        icon: "figure.strengthtraining.traditional", mode: .weekly,
        days: [
            Day(name: "Full Body A", weekdays: [2, 6], lifts: [
                Lift(id: "Barbell_Squat", sets: 3, low: 6, high: 8, rest: 180),
                Lift(id: "Barbell_Bench_Press_-_Medium_Grip", sets: 3, low: 6, high: 8, rest: 180),
                Lift(id: "Bent_Over_Barbell_Row", sets: 3, low: 8, high: 10, rest: 120),
                Lift(id: "Side_Lateral_Raise", sets: 3, low: 12, high: 15, rest: 60),
                Lift(id: "Plank", sets: 3, low: 45, high: 45, rest: 60, seconds: 45),
            ]),
            Day(name: "Full Body B", weekdays: [4], lifts: [
                Lift(id: "Barbell_Deadlift", sets: 3, low: 5, high: 5, rest: 210),
                Lift(id: "Standing_Military_Press", sets: 3, low: 6, high: 8, rest: 150),
                Lift(id: "Wide-Grip_Lat_Pulldown", sets: 3, low: 8, high: 12, rest: 90),
                Lift(id: "forge_bulgarian_split_squat", sets: 3, low: 8, high: 10, rest: 120),
                Lift(id: "Hanging_Leg_Raise", sets: 3, low: 10, high: 15, rest: 60),
            ]),
            Day(name: "Track Session", kind: .cardio, weekdays: [3], cardio: (.track, 2.0)),
        ]
    )

    static let broSplit = SplitTemplate(
        id: "bro", name: "Bro Split",
        summary: "One muscle group per day, Monday through Friday. Lots of volume per session.",
        icon: "flame.fill", mode: .weekly,
        days: [
            Day(name: "Chest", weekdays: [2], lifts: [
                Lift(id: "Barbell_Bench_Press_-_Medium_Grip", sets: 4, low: 6, high: 8, rest: 180),
                Lift(id: "Incline_Dumbbell_Press", sets: 3, low: 8, high: 10, rest: 120),
                Lift(id: "Machine_Bench_Press", sets: 3, low: 10, high: 12, rest: 90),
                Lift(id: "Cable_Crossover", sets: 3, low: 12, high: 15, rest: 60),
                Lift(id: "Dips_-_Chest_Version", sets: 3, low: 8, high: 12, rest: 90),
            ]),
            Day(name: "Back", weekdays: [3], lifts: [
                Lift(id: "Barbell_Deadlift", sets: 3, low: 5, high: 5, rest: 210),
                Lift(id: "Pullups", sets: 3, low: 6, high: 10, rest: 150),
                Lift(id: "Bent_Over_Barbell_Row", sets: 3, low: 8, high: 10, rest: 120),
                Lift(id: "Seated_Cable_Rows", sets: 3, low: 10, high: 12, rest: 90),
                Lift(id: "Straight-Arm_Pulldown", sets: 3, low: 12, high: 15, rest: 60),
            ]),
            Day(name: "Shoulders", weekdays: [4], lifts: [
                Lift(id: "Standing_Military_Press", sets: 4, low: 6, high: 8, rest: 150),
                Lift(id: "Side_Lateral_Raise", sets: 4, low: 12, high: 15, rest: 60),
                Lift(id: "forge_cable_lateral_raise", sets: 3, low: 12, high: 15, rest: 60),
                Lift(id: "Reverse_Machine_Flyes", sets: 3, low: 12, high: 15, rest: 60),
                Lift(id: "Dumbbell_Shrug", sets: 3, low: 10, high: 12, rest: 60),
            ]),
            Day(name: "Arms", weekdays: [5], lifts: [
                Lift(id: "Barbell_Curl", sets: 3, low: 8, high: 10, rest: 90),
                Lift(id: "Close-Grip_Barbell_Bench_Press", sets: 3, low: 8, high: 10, rest: 120),
                Lift(id: "Incline_Dumbbell_Curl", sets: 3, low: 10, high: 12, rest: 60),
                Lift(id: "EZ-Bar_Skullcrusher", sets: 3, low: 10, high: 12, rest: 60),
                Lift(id: "Hammer_Curls", sets: 3, low: 10, high: 12, rest: 60),
                Lift(id: "Triceps_Pushdown_-_Rope_Attachment", sets: 3, low: 12, high: 15, rest: 60),
            ]),
            Day(name: "Legs", weekdays: [6], lifts: [
                Lift(id: "Barbell_Squat", sets: 4, low: 6, high: 8, rest: 180),
                Lift(id: "Leg_Press", sets: 3, low: 10, high: 12, rest: 120),
                Lift(id: "Romanian_Deadlift", sets: 3, low: 8, high: 10, rest: 150),
                Lift(id: "Leg_Extensions", sets: 3, low: 12, high: 15, rest: 60),
                Lift(id: "Lying_Leg_Curls", sets: 3, low: 10, high: 12, rest: 60),
                Lift(id: "Standing_Calf_Raises", sets: 4, low: 10, high: 15, rest: 60),
            ]),
        ]
    )
}
