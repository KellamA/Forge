import SwiftUI

/// Muscles as drawn on the body map and used for filtering and volume analytics.
enum Muscle: String, CaseIterable, Codable, Identifiable, Hashable {
    case chest, shoulders, biceps, triceps, forearms, abs, traps, lats, upperBack, lowerBack
    case glutes, quads, hamstrings, adductors, abductors, calves, neck

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "Chest"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .abs: "Abs"
        case .traps: "Traps"
        case .lats: "Lats"
        case .upperBack: "Upper Back"
        case .lowerBack: "Lower Back"
        case .glutes: "Glutes"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .adductors: "Adductors"
        case .abductors: "Abductors"
        case .calves: "Calves"
        case .neck: "Neck"
        }
    }

    var group: MuscleGroup {
        switch self {
        case .chest: .chest
        case .lats, .upperBack, .lowerBack, .traps: .back
        case .shoulders, .neck: .shoulders
        case .biceps, .triceps, .forearms: .arms
        case .abs: .core
        case .glutes, .quads, .hamstrings, .adductors, .abductors, .calves: .legs
        }
    }

    /// Which side of the body map best shows this muscle.
    var preferredSide: BodySide {
        switch self {
        case .chest, .shoulders, .biceps, .forearms, .abs, .quads, .adductors, .neck: .front
        case .triceps, .traps, .lats, .upperBack, .lowerBack, .glutes, .hamstrings, .calves, .abductors: .back
        }
    }

    /// Order used in filter chips and volume tables (roughly top to bottom).
    static let displayOrder: [Muscle] = [
        .chest, .shoulders, .traps, .lats, .upperBack, .lowerBack, .biceps, .triceps, .forearms,
        .abs, .glutes, .quads, .hamstrings, .adductors, .abductors, .calves, .neck,
    ]
}

enum MuscleGroup: String, CaseIterable, Identifiable {
    case chest, back, shoulders, arms, core, legs
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .arms: "Arms"
        case .core: "Core"
        case .legs: "Legs"
        }
    }

    var color: Color {
        switch self {
        case .chest: Color(red: 1.0, green: 0.42, blue: 0.10)
        case .back: Color(red: 0.33, green: 0.56, blue: 1.0)
        case .shoulders: Color(red: 0.69, green: 0.45, blue: 1.0)
        case .arms: Color(red: 1.0, green: 0.30, blue: 0.48)
        case .core: Color(red: 1.0, green: 0.78, blue: 0.20)
        case .legs: Color(red: 0.20, green: 0.80, blue: 0.55)
        }
    }
}

enum BodySide: String, CaseIterable, Identifiable {
    case front, back
    var id: String { rawValue }
}

enum BodyModel: String, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var displayName: String { self == .male ? "Masculine" : "Feminine" }
}

enum Equipment: String, CaseIterable, Codable, Identifiable {
    case barbell, dumbbell, cable, machine, smithMachine, bodyweight, kettlebell, band, ezBar
    case medicineBall, exerciseBall, foamRoll, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .cable: "Cable"
        case .machine: "Machine"
        case .smithMachine: "Smith Machine"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .band: "Band"
        case .ezBar: "EZ Bar"
        case .medicineBall: "Medicine Ball"
        case .exerciseBall: "Exercise Ball"
        case .foamRoll: "Foam Roller"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .barbell, .ezBar, .smithMachine: "figure.strengthtraining.traditional"
        case .dumbbell: "dumbbell.fill"
        case .cable: "cable.connector"
        case .machine: "gearshape.2.fill"
        case .bodyweight: "figure.core.training"
        case .kettlebell: "figure.cross.training"
        case .band: "figure.flexibility"
        case .medicineBall, .exerciseBall: "circle.circle.fill"
        case .foamRoll: "capsule.fill"
        case .other: "square.grid.2x2.fill"
        }
    }
}

enum ExerciseCategory: String, CaseIterable, Codable, Identifiable {
    case strength, powerlifting, olympic, strongman, plyometrics, stretching, cardio
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength: "Strength"
        case .powerlifting: "Powerlifting"
        case .olympic: "Olympic"
        case .strongman: "Strongman"
        case .plyometrics: "Plyometrics"
        case .stretching: "Stretching"
        case .cardio: "Cardio"
        }
    }
}

/// How sets of an exercise are recorded.
enum TrackingType: String, CaseIterable, Codable, Identifiable {
    case weightReps, bodyweight, duration
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weightReps: "Weight & Reps"
        case .bodyweight: "Bodyweight Reps"
        case .duration: "Timed Hold"
        }
    }
}

enum ScheduleMode: String, CaseIterable, Codable, Identifiable {
    case weekly, rotation
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: "Weekly"
        case .rotation: "Rotation"
        }
    }

    var explanation: String {
        switch self {
        case .weekly: "Each workout is pinned to days of the week."
        case .rotation: "Workouts repeat in order. Up next is whatever follows your last completed day."
        }
    }
}

enum DayKind: String, CaseIterable, Codable, Identifiable {
    case workout, cardio, rest
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .workout: "Workout"
        case .cardio: "Cardio"
        case .rest: "Rest"
        }
    }

    var symbol: String {
        switch self {
        case .workout: "dumbbell.fill"
        case .cardio: "figure.run"
        case .rest: "moon.zzz.fill"
        }
    }
}

enum CardioType: String, CaseIterable, Codable, Identifiable {
    case outdoor, track, treadmill
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .outdoor: "Outdoor"
        case .track: "Track"
        case .treadmill: "Treadmill"
        }
    }

    var symbol: String {
        switch self {
        case .outdoor: "figure.run"
        case .track: "figure.track.and.field"
        case .treadmill: "figure.run.treadmill"
        }
    }

    /// One standard 400m lap in miles.
    static let milesPerLap = 0.2485
}

enum OneRepMaxFormula: String, CaseIterable, Identifiable {
    case brzycki, epley, blended, lombardi
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .brzycki: "Brzycki"
        case .epley: "Epley"
        case .blended: "Blended (Epley + Brzycki)"
        case .lombardi: "Lombardi"
        }
    }

    var summary: String {
        switch self {
        case .brzycki: "weight × 36 ÷ (37 − reps). Conservative and the most widely used."
        case .epley: "weight × (1 + reps ÷ 30). Slightly more optimistic at higher reps."
        case .blended: "The average of Epley and Brzycki."
        case .lombardi: "weight × reps^0.10. Flatter curve across rep ranges."
        }
    }
}

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum PRKind: String, Codable {
    case estimatedMax, reps, duration

    var label: String {
        switch self {
        case .estimatedMax: "Est. 1RM"
        case .reps: "Rep PR"
        case .duration: "Longest Hold"
        }
    }
}
