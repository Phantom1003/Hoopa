import SwiftUI

/// The time ring's bands: a week, a day, an hour, ten minutes, five minutes, one minute; each band is one full lap, colours from cool to warm.
/// When the remaining time crosses into the next band the ring changes colour and starts a full lap again: a task three weeks out first runs a blue lap (down to one week), then cyan, mint, green, yellow, orange, and red in the last minute;
/// a one-hour timer starts with the green lap and goes on through yellow, orange and red. The first lap starts at the moment the time was set (full then); later laps follow the fixed band lengths.
/// A colour means the same on every row: two to-dos with 40 minutes left share a colour; beyond an hour everything is cool and does not nag.
enum Ladder {
    /// The lower bound of each band, farthest first.
    static let steps: [TimeInterval] = [7 * 86400, 86400, 3600, 600, 300, 60]
    /// Each band's colour: beyond a week blue, a week cyan, a day mint, an hour green, ten minutes yellow, five minutes orange, the last minute red.
    static let colors: [Color] = [.blue, .cyan, .mint, CompactView.green, .yellow, .orange, .red]

    struct State {
        var band: Int          // the current band (0 = beyond a week … 6 = the last minute)
        var fraction: Double   // how much of this lap is left (0…1)
        var color: Color { Ladder.colors[band] }
        /// The next band's colour (what shows once this lap has run down); none for the last band.
        var next: Color? { band + 1 < Ladder.colors.count ? Ladder.colors[band + 1] : nil }
    }

    private static func band(_ remaining: TimeInterval) -> Int { steps.firstIndex { remaining >= $0 } ?? steps.count }

    /// remaining: how much is left; span: the total length when set (a countdown's length; for a date the time from setting to due).
    static func state(remaining: TimeInterval, span: TimeInterval) -> State {
        let span = max(span, 1)
        var first = band(span)
        // A first lap that is too short (under 15% of the band's normal lap, say 1 day and 2 minutes) merges into the next band, so a lap does not flash by right after setting.
        if first < steps.count {
            let normal = first == 0 ? steps[0] : steps[first - 1] - steps[first]
            if span - steps[first] < normal * 0.15 { first += 1 }
        }
        let r = max(0, min(remaining, span))
        let b = max(band(r), first)
        let hi = b == first ? span : steps[b - 1]
        let lo = b < steps.count ? steps[b] : 0
        return State(band: b, fraction: max(0, min(1, (r - lo) / max(hi - lo, 1))))
    }
}

extension TodoItem {
    /// The time ring's state: a countdown's total is its minutes; a date counts from the moment it was set (old data has none, uses the creation moment). nil without a time.
    func ring(now: Date) -> Ladder.State? {
        guard let due else { return nil }
        let end = TimeFormat.end(due)
        let span: TimeInterval
        switch due {
        case .countdown(_, let minutes): span = Double(max(minutes, 1) * 60)
        case .date, .dateTime: span = end.timeIntervalSince(dueSetAt ?? createdAt)
        }
        return Ladder.state(remaining: end.timeIntervalSince(now), span: span)
    }
}

/// The time ring on the ball's edge. The track is the next band's colour (translucent): like a boss's stacked health bars in a game, as this lap runs down the next one shows through;
/// under the last band there is nothing, the track is only a faint shade of the same colour. The solid arc is what is left of this lap, clockwise from 12. A full red lap once overdue.
struct TimeRing: View {
    let state: Ladder.State
    let overdue: Bool
    var width: CGFloat = 2

    var body: some View {
        ZStack {
            if overdue {
                Circle().stroke(Style.overdue, lineWidth: width)
            } else {
                Circle().stroke((state.next ?? state.color).opacity(state.next == nil ? 0.22 : 0.45), lineWidth: width)
                Circle().trim(from: 0, to: state.fraction)
                    .stroke(state.color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(width / 2)
    }
}

extension TimeFormat.DueLabel {
    /// The countdown text's warning colour, matching the time ring: red in the last minute and once overdue, orange in the last ten minutes, otherwise nil (each place's default colour).
    var alert: Color? { overdue || critical ? Style.overdue : (urgent ? Style.urgent : nil) }
}
