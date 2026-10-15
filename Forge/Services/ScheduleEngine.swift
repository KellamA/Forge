import Foundation

/// Pure scheduling rules for weekly and rotation splits.
enum ScheduleEngine {
    struct RotationResult: Equatable {
        /// Index of the slot that is up next (or today's rest slot).
        let index: Int
        /// True when today falls on a rest slot.
        let isRestDay: Bool
    }

    /// Works out which rotation slot is current.
    ///
    /// The rotation only advances when you complete a workout. Rest slots are the exception:
    /// each one is "used up" by a calendar day passing. If you finished Legs on Monday and the
    /// next slot is Rest, Tuesday shows a rest day and Wednesday moves on to the slot after it.
    static func rotationSlot(kinds: [DayKind], position: Int, lastAdvance: Date, now: Date,
                             calendar: Calendar = .current) -> RotationResult? {
        guard !kinds.isEmpty else { return nil }
        let count = kinds.count
        var index = ((position % count) + count) % count
        guard kinds.contains(where: { $0 != .rest }) else {
            return RotationResult(index: index, isRestDay: true)
        }
        let elapsedDays = calendar.dateComponents([.day],
                                                  from: calendar.startOfDay(for: lastAdvance),
                                                  to: calendar.startOfDay(for: now)).day ?? 0
        // Days strictly between the last advance and today have already been "spent" resting.
        var restDaysAvailable = max(0, elapsedDays - 1)
        while kinds[index] == .rest && restDaysAvailable > 0 {
            index = (index + 1) % count
            restDaysAvailable -= 1
        }
        // Today itself can be a rest day only if at least one full day has passed since training.
        let isRest = kinds[index] == .rest && elapsedDays >= 1
        if kinds[index] == .rest && elapsedDays == 0 {
            // Trained today; the rest slot starts tomorrow. Report the rest slot as up next.
            return RotationResult(index: index, isRestDay: false)
        }
        return RotationResult(index: index, isRestDay: isRest)
    }

    /// The position after completing slot `index`.
    static func position(afterCompleting index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index + 1) % count
    }

    /// The first training slot at or after `index`, skipping rest slots.
    static func nextTrainingIndex(kinds: [DayKind], from index: Int) -> Int? {
        guard !kinds.isEmpty else { return nil }
        for offset in 0..<kinds.count {
            let i = (index + offset) % kinds.count
            if kinds[i] != .rest { return i }
        }
        return nil
    }

    /// Indices of days scheduled on the weekday of `date` in a weekly split.
    static func weeklyIndices(on date: Date, weekdays: [[Int]], calendar: Calendar = .current) -> [Int] {
        let weekday = calendar.component(.weekday, from: date)
        return weekdays.indices.filter { weekdays[$0].contains(weekday) }
    }

    /// The next date (after `date`) that has something scheduled, with the scheduled indices.
    static func nextWeeklyDate(after date: Date, weekdays: [[Int]], calendar: Calendar = .current) -> (Date, [Int])? {
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            let indices = weeklyIndices(on: day, weekdays: weekdays, calendar: calendar)
            if !indices.isEmpty { return (day, indices) }
        }
        return nil
    }

    /// Weekdays ordered from the calendar's first weekday (e.g. Sun…Sat or Mon…Sun).
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { ((calendar.firstWeekday - 1 + $0) % 7) + 1 }
    }

    static func shortName(forWeekday weekday: Int, calendar: Calendar = .current) -> String {
        calendar.shortWeekdaySymbols[(weekday - 1) % 7]
    }

    static func letter(forWeekday weekday: Int, calendar: Calendar = .current) -> String {
        calendar.veryShortWeekdaySymbols[(weekday - 1) % 7]
    }
}
