import ActivityKit
import Foundation

/// Live Activity shown on the Lock Screen and Dynamic Island during a workout.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exerciseName: String
        /// e.g. "Set 2 of 4"
        var setLabel: String
        /// e.g. "185 lb × 8"
        var detail: String
        var restEndsAt: Date?
        var restTotal: Double
        var completedSets: Int
        var totalSets: Int
    }

    var workoutName: String
    var startedAt: Date
}
