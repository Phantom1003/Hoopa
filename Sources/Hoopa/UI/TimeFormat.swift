import Foundation

/// The time chip's text: countdown + absolute time, the same for both kinds of to-do time.
enum TimeFormat {
    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let monthDay: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM d"; return f
    }()
    private static let yearMonthDay: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM d, yyyy"; return f
    }()

    /// A duration: only the two largest units, more precise the closer it gets: "1d 03h" / "20h 00m" / "4m 10s" / "59s".
    /// A leading zero unit is dropped, the second unit is padded to two digits (0 shows too), so the width does not change as the digits tick.
    static func duration(_ seconds: Int) -> String {
        let u = [(seconds / 86400, "d"), (seconds % 86400 / 3600, "h"), (seconds % 3600 / 60, "m"), (seconds % 60, "s")]
        let first = u.firstIndex { $0.0 > 0 } ?? u.count - 1
        return u[first...].prefix(2).enumerated().map { i, p in
            i == 0 ? "\(p.0)\(p.1)" : String(format: "%02d", p.0) + p.1
        }.joined(separator: " ")
    }

    /// Remaining time, formatted like duration; stops at 0 once past, never negative (the colour and the card tint signal overdue).
    static func remaining(until end: Date, now: Date) -> String {
        duration(max(0, Int(end.timeIntervalSince(now).rounded())))
    }

    static func clockTime(_ d: Date) -> String { clock.string(from: d) }

    /// The difference in calendar days (by calendar date, ignoring the time of day).
    static func dayOffset(_ d: Date, now: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
    }

    /// Today / Tomorrow / Day after / Yesterday / Sep 25
    static func day(_ d: Date, now: Date) -> String {
        switch dayOffset(d, now: now) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2: return "Day after"
        case -1: return "Yesterday"
        default: return monthDay(d, now: now)
        }
    }

    /// The absolute time: today just the time "14:30", other days with the date "Tomorrow 14:30" / "Sep 30 14:30".
    static func absolute(_ d: Date, now: Date) -> String {
        dayOffset(d, now: now) == 0 ? clockTime(d) : "\(day(d, now: now)) \(clockTime(d))"
    }

    /// Sep 25; with the year when not this year: Sep 25, 2027
    static func monthDay(_ d: Date, now: Date = Date()) -> String {
        Calendar.current.isDate(d, equalTo: now, toGranularity: .year) ? monthDay.string(from: d) : yearMonthDay.string(from: d)
    }

    struct DueLabel {
        let text: String       // the chip's main text (countdown)
        let detail: String     // the secondary text (absolute time)
        let overdue: Bool
        let urgent: Bool       // within 10 minutes
    }

    static func label(_ due: Due, now: Date) -> DueLabel {
        switch due {
        case .countdown(let end, _):
            let left = end.timeIntervalSince(now)
            return DueLabel(text: remaining(until: end, now: now),
                            detail: absolute(end, now: now), overdue: left < 0, urgent: left >= 0 && left < 600)
        case .date(let d):
            // A plain date from old data: the countdown runs to the end of that day, the absolute time is the date only.
            let cal = Calendar.current
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: d)) ?? d
            return DueLabel(text: remaining(until: end, now: now),
                            detail: day(d, now: now), overdue: end < now, urgent: cal.isDate(d, inSameDayAs: now))
        case .dateTime(let d):
            let left = d.timeIntervalSince(now)
            return DueLabel(text: remaining(until: d, now: now),
                            detail: absolute(d, now: now), overdue: left < 0, urgent: left >= 0 && left < 3600)
        }
    }
}
