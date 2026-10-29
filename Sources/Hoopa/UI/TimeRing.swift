import SwiftUI

/// The time ring's bands: a month, a week, a day, an hour, ten minutes, one minute; each band is one full lap of fixed length, colours from cool to warm.
/// When the remaining time crosses into the next band the ring changes colour and starts a full lap again: a task three weeks out starts two thirds into the blue lap (a month down to a week), then runs cyan, mint, green, orange, and red in the last minute;
/// a one-hour timer starts with a full green lap and goes on through orange and red. Beyond a month the blue ring is full.
/// The ring reads the same on every row: two to-dos with 40 minutes left show the same colour and the same arc, whenever each was set; beyond an hour everything is cool and does not nag.
/// Yellow is not a band: once the time has passed the ring turns into Hoopa's gold ring with a hyperspace hole inside (see Hole).
enum Ladder {
    /// The lower bound of each band, farthest first; the first band's lap runs from `top` down to its lower bound.
    static let steps: [TimeInterval] = [7 * 86400, 86400, 3600, 600, 60]
    static let top: TimeInterval = 30 * 86400
    /// Each band's colour: beyond a week blue, a week cyan, a day mint, an hour green, ten minutes orange, the last minute red.
    static let colors: [Color] = [.blue, .cyan, .mint, CompactView.green, .orange, .red]

    struct State {
        var band: Int          // the current band (0 = beyond a week … 5 = the last minute)
        var fraction: Double   // how much of this lap is left (0…1)
        var color: Color { Ladder.colors[band] }
        /// The next band's colour (what shows once this lap has run down); none for the last band.
        var next: Color? { band + 1 < Ladder.colors.count ? Ladder.colors[band + 1] : nil }
        /// Where the time left falls on the edge bar's ruler (0…1, see TimeBar): every band is an equal stretch of it, the last minute nearest zero, and within a stretch the time runs evenly.
        var ruler: Double { (Double(Ladder.colors.count - 1 - band) + fraction) / Double(Ladder.colors.count) }
    }

    private static func band(_ remaining: TimeInterval) -> Int { steps.firstIndex { remaining >= $0 } ?? steps.count }

    /// The state for the time left: the band it falls in and how much of that band's lap is left.
    static func state(remaining: TimeInterval) -> State {
        let r = max(0, remaining)
        let b = band(r)
        let hi = b == 0 ? top : steps[b - 1]
        let lo = b < steps.count ? steps[b] : 0
        return State(band: b, fraction: max(0, min(1, (r - lo) / (hi - lo))))
    }
}

extension TodoItem {
    /// The time ring's state for the time left until the to-do's moment; nil without a time.
    func ring(now: Date) -> Ladder.State? {
        guard let due else { return nil }
        return Ladder.state(remaining: TimeFormat.end(due).timeIntervalSince(now))
    }
}

/// Once the time has passed the to-do falls through one of Hoopa's rings: the time ring turns gold and the ball's disc opens into a hyperspace hole, purple deepening to near black
/// at the centre, with bright lilac eddies forever being drawn from the rim into the centre, more and more turbulent on the way in, while the centre breathes. The icon (or the fluffy
/// ball's letter) is pulled in the moment the time passes (see Pull) and stays sunk, small and dim. With Reduce Motion on the hole stands still and the pull is skipped.
/// Gold is amber with light and shade, so that the closed gold ring is not read as another band: the bands never use yellow and are never a closed ring over a grey disc.
enum Hole {
    static let goldLight = Color(red: 1.0, green: 0.886, blue: 0.541)
    static let gold = Color(red: 0.902, green: 0.706, blue: 0.133)
    static let goldDark = Color(red: 0.659, green: 0.478, blue: 0.063)
    static let rim = Color(red: 0.6, green: 0.47, blue: 0.9)            // the purple edge of the hole
    static let deep = Color(red: 0.24, green: 0.12, blue: 0.46)
    static let center = Color(red: 0.06, green: 0.02, blue: 0.14)
    /// The eddies' highlights, one hue per eddy: lilac, periwinkle blue, violet.
    static let glows: [Color] = [Color(red: 0.85, green: 0.78, blue: 1.0), Color(red: 0.55, green: 0.72, blue: 1.0), Color(red: 0.78, green: 0.5, blue: 1.0)]
    /// An eddy takes `travel` seconds from the rim to the centre; `eddies` of them are on the way at once, evenly staggered, so the flow never stops; the centre breathes once per `breath`.
    static let travel: TimeInterval = 1.6
    static let eddies = 3
    static let breath: TimeInterval = 3
    /// Where the icon ends up once sunk: small and dim at the bottom of the hole.
    static let sunkScale: CGFloat = 0.7
    static let sunkOpacity: Double = 0.55

    /// The pull into the hole, animated with keyframes (see CompactView's ball): the icon swells for an instant, then shrinks into the centre, faster and faster, and is gone;
    /// the hole bulges as it swallows; after a beat the icon surfaces again, small and dim, as if seen at the bottom. No turning: about a second in all.
    /// Going the other way (the time moved into the future again) everything eases back in a third of a second. With Reduce Motion on both jump straight to the end state.
    struct Pull: Equatable {
        var scale: CGFloat = 1
        var opacity: Double = 1
        var hole: CGFloat = 1         // the hole's scale (bulges while swallowing)

        static let idle = Pull()
        static let sunk = Pull(scale: sunkScale, opacity: sunkOpacity, hole: 1)

        @KeyframesBuilder<Pull>
        static func keyframes(sinking: Bool, animated: Bool) -> some Keyframes<Pull> {
            // Reduce Motion: the same path run in a millisecond, so that the end state is the same.
            let k = animated ? 1.0 : 0.001
            KeyframeTrack(\.scale) {
                if sinking {
                    CubicKeyframe(1.12, duration: 0.12 * k)
                    CubicKeyframe(0.03, duration: 0.45 * k)
                    LinearKeyframe(0.03, duration: 0.15 * k)
                    SpringKeyframe(sunkScale, duration: 0.35 * k, spring: .smooth)
                } else {
                    CubicKeyframe(1, duration: 0.3 * k)
                }
            }
            KeyframeTrack(\.opacity) {
                if sinking {
                    LinearKeyframe(1, duration: 0.3 * k)
                    LinearKeyframe(0.2, duration: 0.27 * k)
                    LinearKeyframe(0.2, duration: 0.15 * k)
                    LinearKeyframe(sunkOpacity, duration: 0.35 * k)
                } else {
                    CubicKeyframe(1, duration: 0.3 * k)
                }
            }
            KeyframeTrack(\.hole) {
                if sinking {
                    LinearKeyframe(1, duration: 0.4 * k)
                    CubicKeyframe(1.2, duration: 0.17 * k)
                    SpringKeyframe(1, duration: 0.4 * k, spring: .bouncy)
                } else {
                    CubicKeyframe(1, duration: 0.3 * k)
                }
            }
        }
    }

    /// The gold of the ring and the bar: lit from the top left.
    static var goldGradient: LinearGradient {
        LinearGradient(colors: [goldLight, gold, goldDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// The hole across a bar's thickness: purple edges, black in the middle.
    static func barGradient(vertical: Bool) -> LinearGradient {
        LinearGradient(colors: [rim, center, rim], startPoint: vertical ? .leading : .top, endPoint: vertical ? .trailing : .bottom)
    }
}

/// The hole in the ball's disc: a radial gradient, near black at the centre, purple at the edge, the dark centre slowly breathing. Over it the inflow: `Hole.eddies` bright rings
/// forever travelling from the rim into the centre, one setting off as another arrives, each in its own hue (lilac, blue, violet). A ring is not a circle but a churning loop: five waves
/// around it, each drifting at its own speed, the slowest of them pulling the whole loop off centre; the churn grows as it goes in, from a slight waver at the rim to a tumbling blob at the drain. Drawn at the display's rate, driven by the clock, so the per-second refresh around
/// it cannot restart it. Fills its frame with a circle.
struct HoleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { ctx in
            Canvas { g, size in
                let r = min(size.width, size.height) / 2
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let t = ctx.date.timeIntervalSinceReferenceDate
                let breath = reduceMotion ? 0 : sin(t * 2 * .pi / Hole.breath)
                let depth = 0.55 + 0.12 * breath
                g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .radialGradient(Gradient(stops: [.init(color: Hole.center, location: 0), .init(color: Hole.deep, location: depth), .init(color: Hole.rim, location: 1)]),
                                             center: c, startRadius: 0, endRadius: r))
                if reduceMotion { return }
                let n = 48
                for k in 0..<Hole.eddies {
                    // p: how far in this eddy is (0 at the rim, 1 at the centre).
                    let p = (t / Hole.travel + Double(k) / Double(Hole.eddies)).truncatingRemainder(dividingBy: 1)
                    let ease = p * p * (3 - 2 * p)
                    let base = r * (0.95 - 0.88 * ease)
                    let amp = 0.06 + 0.34 * p * p                      // a waver at the rim, tumbling near the drain
                    let a = pow(1 - ease, 2) * (p < 0.12 ? p / 0.12 : 1) // fades in as it sets off, and out well before it arrives: the drain stays dark
                    let phase = Double(k) * 2.1                          // each eddy's waves sit differently
                    var path = Path()
                    for i in 0...n {
                        let th = Double(i) / Double(n) * 2 * .pi
                        let w = 0.35 * sin(th + t * 1.3 + phase) + 0.3 * sin(2 * th - t * 1.9 + phase * 0.6) + 0.25 * sin(3 * th + t * 2.7 + phase)
                            + 0.2 * sin(5 * th - t * 3.4 + phase * 1.7) + 0.15 * sin(8 * th + t * 5.1 - phase)
                        let rad = base * (1 + amp * w)
                        let pt = CGPoint(x: c.x + rad * cos(th), y: c.y + rad * sin(th))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    path.closeSubpath()
                    g.stroke(path, with: .color(Hole.glows[k % Hole.glows.count].opacity(0.85 * a)), style: StrokeStyle(lineWidth: max(0.6, r * 0.1 * (1 - 0.5 * p)), lineJoin: .round))
                }
            }
        }
    }
}

/// The time ring on the ball's edge. The track is the next band's colour (translucent): like a boss's stacked health bars in a game, as this lap runs down the next one shows through;
/// under the last band there is nothing, the track is only a faint shade of the same colour. The solid arc is what is left of this lap, clockwise from 12.
/// Once overdue the ring is Hoopa's: a closed gold ring (the hole under it is the disc's business, see HoleView).
struct TimeRing: View {
    let state: Ladder.State
    let overdue: Bool
    var width: CGFloat = 2

    var body: some View {
        ZStack {
            if overdue {
                Circle().stroke(Hole.goldGradient, lineWidth: width)
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

/// A ruler of the time left, a capsule the length given: a month down to zero, the time ring's six bands as six equal stretches of it (see Ladder.State.ruler), from zero
/// red (the last minute), orange (to ten minutes), green (to an hour), mint (to a day), cyan (to a week) and blue (to a month). Notches cut across the bar at the bounds
/// between the stretches, so they always sit at the same places and mean the same time: a minute, ten minutes, an hour, a day and a week from zero.
/// Unlike the ring, which starts a full lap in each band, the bar runs once from full to zero: a bar whose notches meant other times in every colour could not be read at a glance.
/// The track shows each stretch faintly in its band's colour; the solid part, what is left, is in the colour of the band the time is in (the ring's colour).
/// Zero is where the solid part ends up: a vertical bar drains towards its bottom (the solid part sits on the bottom, its top sinking), a horizontal one towards its middle
/// (the solid part stays centred and shrinks from both ends, like a fuse burning in from both sides; the stretches and notches are mirrored about the middle).
/// Once overdue the bar is a warning tape: gold with thin black diagonal stripes that flicker slowly (see HazardBar).
/// Drawn along the strip of a docked panel tucked away at the screen edge, see RootView's EdgeBar.
struct TimeBar: View {
    @Environment(\.displayScale) private var scale
    let state: Ladder.State
    let overdue: Bool
    let vertical: Bool
    let length: CGFloat
    var thickness: CGFloat = 3
    /// A notch's width, and the least length of a stretch: a bar too short for that has no notches.
    private static let notch: CGFloat = 1
    private static let minStretch: CGFloat = 5
    private static let trackOpacity = 0.3

    var body: some View {
        // Under one thickness a capsule is a squashed dot: time nearly up still shows as a dot; nothing once it is up.
        let left = state.ruler > 0 ? max(thickness, length * state.ruler) : 0
        Group {
            if overdue {
                HazardBar()
            } else {
                ZStack(alignment: vertical ? .bottom : .center) {
                    track
                    Capsule().fill(state.color)
                        .frame(width: vertical ? thickness : left, height: vertical ? left : thickness)
                }
                .clipShape(Capsule())
                .mask(Notches(at: notches, vertical: vertical, width: Self.notch).fill(style: FillStyle(eoFill: true)))
            }
        }
        .frame(width: vertical ? thickness : length, height: vertical ? length : thickness)
    }

    /// The length one band takes, from zero towards either end.
    private var stretch: CGFloat { (vertical ? length : length / 2) / CGFloat(Ladder.colors.count) }

    /// The stretches in their bands' colours, faint (the ends are rounded by the clip around it).
    private var track: some View {
        Canvas { g, size in
            let n = Ladder.colors.count, s = stretch
            for k in 0..<n {    // k: the stretch's place from zero, the last band first
                let color = GraphicsContext.Shading.color(Ladder.colors[n - 1 - k].opacity(Self.trackOpacity))
                if vertical {
                    g.fill(Path(CGRect(x: 0, y: size.height - CGFloat(k + 1) * s, width: size.width, height: s)), with: color)
                } else {
                    let mid = size.width / 2
                    g.fill(Path(CGRect(x: mid + CGFloat(k) * s, y: 0, width: s, height: size.height)), with: color)
                    g.fill(Path(CGRect(x: mid - CGFloat(k + 1) * s, y: 0, width: s, height: size.height)), with: color)
                }
            }
        }
    }

    /// The notches' centres along the bar, from its top / left edge, each notch's edges on the pixel grid: at the bounds between the stretches, mirrored about a horizontal bar's middle.
    private var notches: [CGFloat] {
        let s = stretch
        guard s >= Self.minStretch else { return [] }
        let snap = { (x: CGFloat) in ((x - Self.notch / 2) * scale).rounded() / scale + Self.notch / 2 }
        return (1..<Ladder.colors.count).flatMap { k in
            vertical ? [snap(length - CGFloat(k) * s)] : [snap(length / 2 - CGFloat(k) * s), snap(length / 2 + CGFloat(k) * s)]
        }
    }
}

/// TimeBar's mask (filled even-odd): the bar's whole rect with a thin gap across it at each notch.
private struct Notches: Shape {
    let at: [CGFloat]
    let vertical: Bool
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        for c in at {
            p.addRect(vertical ? CGRect(x: rect.minX, y: rect.minY + c - width / 2, width: rect.width, height: width)
                               : CGRect(x: rect.minX + c - width / 2, y: rect.minY, width: width, height: rect.height))
        }
        return p
    }
}

/// The overdue edge bar: warning tape, a gold capsule with thin black diagonal stripes well apart. The stripes do not move; each one flickers slowly, fading between faint and solid
/// and swelling to twice its width as it darkens, on its own slow rhythm (two slow waves per stripe, offset along the bar), so that the tape glimmers without ever flashing. Driven by the clock. With Reduce Motion on the stripes are solid and still.
/// Fills the frame it is given (vertical or horizontal alike: the stripes are at 45° either way).
struct HazardBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let stripe: CGFloat = 3     // the width of a black stripe, measured along the bar
    private static let gap: CGFloat = 11       // the gold between two black stripes

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { ctx in
            Canvas { g, size in
                let thick = min(size.width, size.height)
                let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: thick / 2)
                g.fill(shape, with: .color(Hole.gold))
                g.clip(to: shape)
                let t = ctx.date.timeIntervalSinceReferenceDate
                // Black parallelograms one stripe and one gap apart, leaning by one thickness over the bar's thickness, which makes them 45°.
                let step = Self.stripe + Self.gap
                let vertical = size.height > size.width
                var x: CGFloat = -thick
                var i = 0
                while x < (vertical ? size.height : size.width) + thick {
                    // The flicker: 0.3…1, from two slow waves (periods of about 2.6 and 4.1 seconds) each stripe sees at its own phase. The stripe widens with it, about its own middle.
                    let f = reduceMotion ? 1 : 0.65 + 0.35 * (0.6 * sin(t * 2.4 + Double(i) * 0.9) + 0.4 * sin(t * 1.5 - Double(i) * 1.7))
                    let w = Self.stripe * (reduceMotion ? 1 : 0.6 + 1.4 * f)
                    let x0 = x + (Self.stripe - w) / 2
                    var p = Path()
                    if vertical {
                        p.move(to: CGPoint(x: 0, y: x0)); p.addLine(to: CGPoint(x: thick, y: x0 + thick))
                        p.addLine(to: CGPoint(x: thick, y: x0 + thick + w)); p.addLine(to: CGPoint(x: 0, y: x0 + w))
                    } else {
                        p.move(to: CGPoint(x: x0, y: 0)); p.addLine(to: CGPoint(x: x0 + thick, y: thick))
                        p.addLine(to: CGPoint(x: x0 + thick + w, y: thick)); p.addLine(to: CGPoint(x: x0 + w, y: 0))
                    }
                    p.closeSubpath()
                    g.fill(p, with: .color(.black.opacity(f)))
                    x += step
                    i += 1
                }
            }
        }
    }
}

extension TimeFormat.DueLabel {
    /// The countdown text's warning colour, matching the time ring: red in the last minute and once overdue, orange in the last ten minutes, otherwise nil (each place's default colour).
    var alert: Color? { overdue || critical ? Style.overdue : (urgent ? Style.urgent : nil) }
}
