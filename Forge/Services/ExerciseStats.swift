import Foundation

/// Value-type summary of one exercise's history, for charts and stats.
struct ExerciseStats {
    struct Point: Identifiable, Hashable {
        let id: UUID
        let date: Date
        /// Estimated 1RM (weighted), max reps (bodyweight) or longest hold (seconds).
        let value: Double
        let topWeight: Double
        let topReps: Int
        let volume: Double
        let sets: Int
    }

    struct Session: Identifiable {
        let id: UUID
        let date: Date
        let sessionName: String
        let sets: [SetSnapshot]
        let prSetIndex: Int?
    }

    let tracking: TrackingType
    let points: [Point]
    let sessions: [Session]
    let best: Point?
    let heaviest: Double
    let totalSets: Int
    let totalReps: Int
    let totalVolume: Double

    init(entries: [SessionExercise], tracking: TrackingType, formula: OneRepMaxFormula) {
        self.tracking = tracking
        let done: [SessionExercise] = entries.filter { entry in
            entry.session?.endedAt != nil && !entry.completedSets.isEmpty
        }
        let finished: [SessionExercise] = done.sorted { a, b in
            let da: Date = a.session?.startedAt ?? .distantPast
            let db: Date = b.session?.startedAt ?? .distantPast
            return da < db
        }
        var points: [Point] = []
        var sessions: [Session] = []
        var heaviest = 0.0
        var totalSets = 0
        var totalReps = 0
        var totalVolume = 0.0
        for entry in finished {
            guard let session = entry.session else { continue }
            let working = entry.completedSets.filter { !$0.isWarmup }
            var bestValue = 0.0
            var bestSet: SetLog?
            for set in working {
                if let m = PRService.metric(set, tracking: tracking, formula: formula), m > bestValue {
                    bestValue = m
                    bestSet = set
                }
                heaviest = max(heaviest, set.weight)
                totalReps += set.reps
            }
            totalSets += working.count
            totalVolume += entry.volume
            if let bestSet {
                points.append(Point(id: entry.id, date: session.startedAt, value: bestValue,
                                    topWeight: bestSet.weight, topReps: bestSet.reps,
                                    volume: entry.volume, sets: working.count))
            }
            let snapshots = entry.completedSets.map {
                SetSnapshot(weight: $0.weight, reps: $0.reps, seconds: $0.seconds, isWarmup: $0.isWarmup)
            }
            sessions.append(Session(id: entry.id, date: session.startedAt, sessionName: session.name,
                                    sets: snapshots, prSetIndex: entry.completedSets.firstIndex { $0.prKind != nil }))
        }
        self.points = points
        self.sessions = sessions.reversed()
        self.best = points.max { $0.value < $1.value }
        self.heaviest = heaviest
        self.totalSets = totalSets
        self.totalReps = totalReps
        self.totalVolume = totalVolume
    }

    var latest: Point? { points.last }

    /// Change in the tracked value over the last ~30 days.
    var recentChange: Double? {
        guard let latest, let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: latest.date) else { return nil }
        guard let baseline = points.last(where: { $0.date <= monthAgo }) ?? points.first, baseline.id != latest.id else { return nil }
        return latest.value - baseline.value
    }

    var valueUnit: String {
        switch tracking {
        case .weightReps: "lb"
        case .bodyweight: "reps"
        case .duration: "sec"
        }
    }

    var valueTitle: String {
        switch tracking {
        case .weightReps: "Estimated 1RM"
        case .bodyweight: "Best Reps"
        case .duration: "Longest Hold"
        }
    }

    static func setText(_ set: SetSnapshot, tracking: TrackingType) -> String {
        switch tracking {
        case .weightReps: "\(Fmt.weight(set.weight)) × \(set.reps)"
        case .bodyweight: set.weight > 0 ? "+\(Fmt.weight(set.weight)) × \(set.reps)" : "\(set.reps) reps"
        case .duration: "\(set.seconds)s"
        }
    }
}
