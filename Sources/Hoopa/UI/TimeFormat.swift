import Foundation

/// The text of a countdown / date.
enum TimeFormat {
    private static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let monthDay: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM d"; return f
    }()

    /// Remaining time: "04:23" under an hour, otherwise "1h 05m"; negative once past.
    static func remaining(until end: Date, now: Date) -> String {
        let total = Int(end.timeIntervalSince(now).rounded())
        let sign = total < 0 ? "-" : ""
        let t = abs(total)
        if t < 3600 { return String(format: "%@%02d:%02d", sign, t / 60, t % 60) }
        return String(format: "%@%dh %02dm", sign, t / 3600, (t % 3600) / 60)
    }

    static func clockTime(_ d: Date) -> String { clock.string(from: d) }

    /// Today / Tomorrow / Day after / Yesterday / Sep 25
    static func day(_ d: Date, now: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2: return "Day after"
        case -1: return "Yesterday"
        default: return monthDay.string(from: d)
        }
    }

    struct DueLabel {
        let text: String       // the chip's main text
        let detail: String?    // the secondary text (the due moment)
        let overdue: Bool
        let urgent: Bool       // within 10 minutes
    }

    static func label(_ due: Due, now: Date) -> DueLabel {
        switch due {
        case .countdown(let end, _):
            let left = end.timeIntervalSince(now)
            return DueLabel(text: remaining(until: end, now: now), detail: clockTime(end),
                            overdue: left < 0, urgent: left >= 0 && left < 600)
        case .date(let d):
            let overdue = Calendar.current.startOfDay(for: d) < Calendar.current.startOfDay(for: now)
            return DueLabel(text: day(d, now: now), detail: nil, overdue: overdue,
                            urgent: Calendar.current.isDate(d, inSameDayAs: now))
        }
    }

    static func minutes(_ m: Int) -> String { m >= 60 && m % 60 == 0 ? "\(m / 60) h" : "\(m) min" }
}
