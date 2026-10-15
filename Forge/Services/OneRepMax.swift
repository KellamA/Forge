import Foundation

/// Estimated one-rep-max math.
enum OneRepMax {
    /// Sets above this rep count are too noisy to estimate a max from.
    static let maxReliableReps = 20

    static func estimate(weight: Double, reps: Int, formula: OneRepMaxFormula) -> Double? {
        guard weight > 0, reps > 0, reps <= maxReliableReps else { return nil }
        if reps == 1 { return weight }
        let r = Double(reps)
        switch formula {
        case .epley:
            return weight * (1 + r / 30)
        case .brzycki:
            return weight * 36 / (37 - r)
        case .blended:
            return (weight * (1 + r / 30) + weight * 36 / (37 - r)) / 2
        case .lombardi:
            return weight * pow(r, 0.10)
        }
    }

    /// The weight you should be able to lift for `reps` given an estimated max.
    static func weight(forReps reps: Int, oneRepMax: Double, formula: OneRepMaxFormula) -> Double {
        guard reps > 1 else { return oneRepMax }
        let r = Double(reps)
        switch formula {
        case .epley:
            return oneRepMax / (1 + r / 30)
        case .brzycki:
            return oneRepMax * (37 - r) / 36
        case .blended:
            // Forward: max = w × (epleyFactor + brzyckiFactor) / 2, so solve for w.
            return 2 * oneRepMax / ((1 + r / 30) + 36 / (37 - r))
        case .lombardi:
            return oneRepMax / pow(r, 0.10)
        }
    }

    /// Percent of 1RM commonly associated with each rep count (Brzycki-based), for the rep-max table.
    static let tableReps = [1, 2, 3, 4, 5, 6, 8, 10, 12, 15]
}

extension OneRepMaxFormula {
    static var current: OneRepMaxFormula {
        OneRepMaxFormula(rawValue: UserDefaults.standard.string(forKey: SettingsKey.oneRepMaxFormula) ?? "") ?? .brzycki
    }
}
