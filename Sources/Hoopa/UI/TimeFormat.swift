import Foundation

/// The time chip's text: countdown + absolute time, the same for both kinds of to-do time.
enum TimeFormat {
    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    // Dates follow the interface language: "Sep 25" / "Sep 25, 2027" in English, the localized forms otherwise.
    private static let monthDay = formatter { $0.setLocalizedDateFormatFromTemplate("MMMd") }
    private static let yearMonthDay = formatter { $0.setLocalizedDateFormatFromTemplate("yMMMd") }
    // The system's own relative words: compared with the result without them; a difference means one exists (Today, Tomorrow, Yesterday…).
    private static let relative = formatter { $0.dateStyle = .medium; $0.doesRelativeDateFormatting = true }
    private static let plain = formatter { $0.dateStyle = .medium }

    private static func formatter(_ setup: (DateFormatter) -> Void) -> DateFormatter {
        let f = DateFormatter(); f.locale = AppLanguage.locale; setup(f); return f
    }

    /// A duration: only the two largest units, more precise the closer it gets: "1d 03h" / "20h 00m" / "4m 10s" / "59s".
    /// A leading zero unit is dropped, the second unit is padded to two digits (0 shows too), so the width does not change as the digits tick.
    static func duration(_ seconds: Int) -> String {
        let u = [(seconds / 86400, "d"), (seconds % 86400 / 3600, "h"), (seconds % 3600 / 60, "m"), (seconds % 60, "s")]
        let first = u.firstIndex { $0.0 > 0 } ?? u.count - 1
        return u[first...].prefix(2).enumerated().map { i, p in
            i == 0 ? "\(p.0)\(p.1)" : String(format: "%02d", p.0) + p.1
        }.joined(separator: " ")
    }

    /// Remaining time, formatted like duration; stops at 0 once past, never negative.
    static func remaining(until end: Date, now: Date) -> String {
        duration(max(0, Int(end.timeIntervalSince(now).rounded())))
    }

    /// The countdown column: the remaining time until due; past due it does not show 0 but says "Overdue" (one word for timers and date-times alike), in red, with the absolute time following as usual.
    private static func countdown(until end: Date, now: Date) -> String {
        end > now ? remaining(until: end, now: now) : String(localized: "Overdue")
    }

    static func clockTime(_ d: Date) -> String { clock.string(from: d) }

    /// The difference in calendar days (by calendar date, ignoring the time of day).
    static func dayOffset(_ d: Date, now: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
    }

    /// The interface language's relative words (Yesterday…Tomorrow in English, the localized forms otherwise), else the date: Sep 25
    static func day(_ d: Date, now: Date) -> String {
        let offset = dayOffset(d, now: now)
        if abs(offset) <= 2, let same = Calendar.current.date(byAdding: .day, value: offset, to: Date()) {
            let word = relative.string(from: same)
            if word != plain.string(from: same) { return word }
        }
        return monthDay(d, now: now)
    }

    /// The absolute time: today just the time "14:30", other days with the date "Tomorrow 14:30" / "Sep 30 14:30".
    static func absolute(_ d: Date, now: Date) -> String {
        dayOffset(d, now: now) == 0 ? clockTime(d) : "\(day(d, now: now)) \(clockTime(d))"
    }

    /// Sep 25; with the year when not this year: Sep 25, 2027
    static func monthDay(_ d: Date, now: Date = Date()) -> String {
        Calendar.current.isDate(d, equalTo: now, toGranularity: .year) ? monthDay.string(from: d) : yearMonthDay.string(from: d)
    }

    /// The full date, always with the year: Sep 28, 2026 (the date field of the time popover).
    static func fullDate(_ d: Date) -> String { yearMonthDay.string(from: d) }

    struct DueLabel {
        let text: String       // the chip's main text (countdown; "Overdue" once past due)
        let detail: String     // the secondary text (absolute time)
        let overdue: Bool
        let urgent: Bool       // the last 10 minutes (matching the time ring's yellow and orange bands, timers and dates alike)
        let critical: Bool     // the last minute (the time ring's red lap)
    }

    /// The due moment: the moment itself for countdowns and date-times; a plain date from old data counts until the end of that day.
    static func end(_ due: Due) -> Date {
        switch due {
        case .countdown(let end, _), .dateTime(let end): return end
        case .date(let d):
            let cal = Calendar.current
            return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: d)) ?? d
        }
    }

    static func label(_ due: Due, now: Date) -> DueLabel {
        let at = end(due)
        let left = at.timeIntervalSince(now)
        let detail: String
        switch due {
        case .countdown, .dateTime: detail = absolute(at, now: now)
        case .date(let d): detail = day(d, now: now)      // a plain date from old data: the absolute time is the date only
        }
        return DueLabel(text: countdown(until: at, now: now), detail: detail,
                        overdue: left < 0, urgent: left >= 0 && left < 600, critical: left >= 0 && left < 60)
    }
}
