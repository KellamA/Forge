import Foundation
import SwiftData

/// Personal-record rules. Each exercise tracks one metric:
/// estimated 1RM for weighted lifts, reps for bodyweight moves, seconds for holds.
enum PRService {
    static func kind(for tracking: TrackingType) -> PRKind {
        switch tracking {
        case .weightReps: .estimatedMax
        case .bodyweight: .reps
        case .duration: .duration
        }
    }

    static func metric(weight: Double, reps: Int, seconds: Int, tracking: TrackingType, formula: OneRepMaxFormula) -> Double? {
        switch tracking {
        case .weightReps:
            return OneRepMax.estimate(weight: weight, reps: reps, formula: formula)
        case .bodyweight:
            return reps > 0 ? Double(reps) : nil
        case .duration:
            return seconds > 0 ? Double(seconds) : nil
        }
    }

    static func metric(_ set: SetLog, tracking: TrackingType, formula: OneRepMaxFormula) -> Double? {
        guard set.isCompleted, !set.isWarmup else { return nil }
        return metric(weight: set.weight, reps: set.reps, seconds: set.seconds, tracking: tracking, formula: formula)
    }

    /// Best metric for an exercise across finished sessions, excluding one session.
    @MainActor
    static func baseline(exerciseID: String, tracking: TrackingType, excluding sessionID: UUID?, context: ModelContext) -> Double? {
        let descriptor = FetchDescriptor<SessionExercise>(predicate: #Predicate { $0.exerciseID == exerciseID })
        guard let entries = try? context.fetch(descriptor) else { return nil }
        let formula = OneRepMaxFormula.current
        var best: Double?
        for entry in entries {
            guard let session = entry.session, session.endedAt != nil, session.id != sessionID else { continue }
            for set in entry.sets ?? [] {
                if let m = metric(set, tracking: tracking, formula: formula), m > (best ?? 0) { best = m }
            }
        }
        return best
    }

    /// Flags the best set of `exercise` as a PR if it beats `baseline`. Returns true when a new PR set was flagged.
    @discardableResult
    static func evaluate(_ exercise: SessionExercise, baseline: Double?) -> Bool {
        let formula = OneRepMaxFormula.current
        let tracking = exercise.tracking
        let sets = exercise.orderedSets
        let previouslyFlagged = sets.first(where: { $0.prKind != nil })?.id
        var bestSet: SetLog?
        var bestValue = 0.0
        for set in sets {
            if let m = metric(set, tracking: tracking, formula: formula), m > bestValue {
                bestValue = m
                bestSet = set
            }
        }
        for set in sets { set.prKind = nil }
        guard let baseline, baseline > 0, let bestSet, bestValue > baseline + 0.01 else { return false }
        bestSet.prKind = kind(for: tracking)
        return bestSet.id != previouslyFlagged
    }

    /// Re-derives PR flags for every finished session in chronological order (after edits or imports).
    @MainActor
    static func recomputeAll(context: ModelContext) {
        let descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt)])
        guard let sessions = try? context.fetch(descriptor) else { return }
        let formula = OneRepMaxFormula.current
        var bests: [String: Double] = [:]
        for session in sessions where session.endedAt != nil {
            for exercise in session.orderedExercises {
                let previous = bests[exercise.exerciseID]
                evaluate(exercise, baseline: previous)
                for set in exercise.sets ?? [] {
                    if let m = metric(set, tracking: exercise.tracking, formula: formula), m > (bests[exercise.exerciseID] ?? 0) {
                        bests[exercise.exerciseID] = m
                    }
                }
            }
        }
        try? context.save()
    }
}
