import Foundation

enum Fmt {
    /// "185", "182.5"
    static func weight(_ lb: Double) -> String {
        if lb.rounded() == lb { return String(Int(lb)) }
        return lb.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func weightUnit(_ lb: Double) -> String { "\(weight(lb)) lb" }

    /// "12,450 lb" or "1.2M lb"
    static func volume(_ lb: Double) -> String {
        if lb >= 1_000_000 { return (lb / 1_000_000).formatted(.number.precision(.fractionLength(1))) + "M" }
        if lb >= 100_000 { return (lb / 1000).formatted(.number.precision(.fractionLength(0))) + "k" }
        return Int(lb.rounded()).formatted()
    }

    /// "1h 05m", "45m", "38s"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }

    /// "1:05:12" or "45:12"
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// "3.1"
    static func miles(_ miles: Double) -> String {
        miles.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "8:15 /mi"
    static func pace(_ secondsPerMile: Double) -> String {
        let total = Int(secondsPerMile.rounded())
        return String(format: "%d:%02d /mi", total / 60, total % 60)
    }

    /// "Today", "Yesterday", "Monday", "Oct 3", "Oct 3, 2025"
    static func relativeDay(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day,
           days > 0, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func signed(_ value: Double, digits: Int = 1) -> String {
        let s = abs(value).formatted(.number.precision(.fractionLength(0...digits)))
        if value > 0.0001 { return "+\(s)" }
        if value < -0.0001 { return "−\(s)" }
        return "0"
    }

    static func restLabel(_ seconds: Int) -> String {
        if seconds >= 60 {
            let m = seconds / 60, s = seconds % 60
            return s == 0 ? "\(m):00" : String(format: "%d:%02d", m, s)
        }
        return "\(seconds)s"
    }
}

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}
