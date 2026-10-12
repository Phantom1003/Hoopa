import SwiftUI

/// Shared dial geometry: angles start at 12 o'clock and grow clockwise.
private enum DialGeometry {
    static func angle(of p: CGPoint, center c: CGPoint) -> Double {
        var a = atan2(p.x - c.x, -(p.y - c.y)) * 180 / .pi
        if a < 0 { a += 360 }
        return a
    }
    static func point(angle: Double, radius: CGFloat, center c: CGPoint) -> CGPoint {
        let r = angle * .pi / 180
        return CGPoint(x: c.x + radius * sin(r), y: c.y - radius * cos(r))
    }
}

/// The countdown dial: "25 : 00" in the middle, click the minutes or the seconds to choose which the dial sets, drag on the ring to choose.
/// Minutes: 0–120, a figure every 10; seconds: 0–59, a figure every 5. The arc is the chosen share of the active ring. At least one second, at most 120 minutes.
struct CountdownDial: View {
    @Binding var seconds: Int       // the whole length, 1…maxSeconds
    @State private var pickingMinutes = true
    static let maxSeconds = 120 * 60
    private let size: CGFloat = 170

    private var minutePart: Int { seconds / 60 }
    private var secondPart: Int { seconds % 60 }

    var body: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = min(geo.size.width, geo.size.height) / 2 - 10
            let share = pickingMinutes ? Double(minutePart) / 120 : Double(secondPart) / 60
            ZStack {
                Circle().stroke(Style.chip, lineWidth: 6).frame(width: r * 2, height: r * 2)
                Circle()
                    .trim(from: 0, to: CGFloat(share))
                    .stroke(Style.accent.opacity(0.55), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: r * 2, height: r * 2)
                ForEach(0..<12, id: \.self) { i in
                    // Minutes: 10 … 120 clockwise from one o'clock (120 at the top); seconds: 00 … 55 from the top.
                    let a = Double(pickingMinutes ? i + 1 : i) / 12 * 360
                    Text(pickingMinutes ? "\((i + 1) * 10)" : String(format: "%02d", i * 5))
                        .font(.system(size: 9)).monospacedDigit().foregroundStyle(Style.tertiary)
                        .position(DialGeometry.point(angle: a, radius: r - 16, center: c))
                }
                Circle().fill(Color.clear).frame(width: 18, height: 18).tintedGlass(Circle())
                    .position(DialGeometry.point(angle: share * 360, radius: r, center: c))
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    digit(String(format: "%02d", minutePart), unit: "min", active: pickingMinutes) { pickingMinutes = true }
                    Text(":").font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(Style.secondary)
                    digit(String(format: "%02d", secondPart), unit: "sec", active: !pickingMinutes) { pickingMinutes = false }
                }
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                // The readout in the middle is for clicking, not for dragging: a click there must not turn the ring to a random angle.
                guard hypot(g.location.x - c.x, g.location.y - c.y) >= r * 0.65 else { return }
                let a = DialGeometry.angle(of: g.location, center: c)
                let chosen = pickingMinutes
                    ? Int((a / 360 * 120).rounded()) * 60 + secondPart
                    : minutePart * 60 + Int((a / 6).rounded()) % 60
                seconds = max(1, min(Self.maxSeconds, chosen))
            })
        }
        .frame(width: size, height: size)
    }

    /// One number of the "25 : 00" readout with its unit under it; the active one is tinted (it is what the ring sets), a click makes it the active one.
    private func digit(_ s: String, unit: LocalizedStringKey, active: Bool, _ tap: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Text(s).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(active ? Style.accent : Color.primary)
            Text(unit).font(.system(size: 10)).foregroundStyle(active ? Style.accent : Style.secondary)
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(active ? Style.accent.opacity(0.12) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
    }
}

/// The clock dial (Material style): "14 : 30" above, click "hours" or "minutes" to switch, drag on the dial to choose.
/// Hours: outer ring 1–12, inner ring 13–24 (24 for midnight); minutes: 0–59, a tick every 5.
struct ClockDial: View {
    @Binding var hour: Int      // 0…23
    @Binding var minute: Int    // 0…59
    @State private var pickingHour = true
    private let size: CGFloat = 170

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                digit(String(format: "%02d", hour), active: pickingHour) { pickingHour = true }
                Text(":").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(Style.secondary)
                digit(String(format: "%02d", minute), active: !pickingHour) { pickingHour = false }
            }
            dial
        }
    }

    private func digit(_ s: String, active: Bool, _ tap: @escaping () -> Void) -> some View {
        Text(s)
            .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
            .foregroundStyle(active ? Style.accent : Color.primary)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 6).fill(active ? Style.accent.opacity(0.12) : .clear))
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
    }

    private var dial: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = min(geo.size.width, geo.size.height) / 2 - 14
            let inner = r * 0.6
            let selectedAngle = pickingHour ? Double(hour % 12) / 12 * 360 : Double(minute) / 60 * 360
            let selectedRadius = pickingHour ? (hour == 0 || hour > 12 ? inner : r) : r
            ZStack {
                Circle().fill(Color.clear).frame(width: (r + 14) * 2, height: (r + 14) * 2).glass(Circle())
                Path { p in
                    p.move(to: c)
                    p.addLine(to: DialGeometry.point(angle: selectedAngle, radius: selectedRadius, center: c))
                }
                .stroke(Style.accent.opacity(0.6), lineWidth: 1.5)
                Circle().fill(Style.accent.opacity(0.6)).frame(width: 4, height: 4).position(c)
                Circle().fill(Color.clear).frame(width: 28, height: 28).tintedGlass(Circle())
                    .position(DialGeometry.point(angle: selectedAngle, radius: selectedRadius, center: c))
                if pickingHour {
                    ForEach(1...12, id: \.self) { h in
                        label("\(h)", angle: Double(h) / 12 * 360, radius: r, center: c, selected: hour == h)
                    }
                    ForEach(13...24, id: \.self) { h in
                        label("\(h == 24 ? 0 : h)", angle: Double(h - 12) / 12 * 360, radius: inner, center: c,
                              selected: hour == (h == 24 ? 0 : h), small: true)
                    }
                } else {
                    ForEach(0..<12, id: \.self) { i in
                        label(String(format: "%02d", i * 5), angle: Double(i) / 12 * 360, radius: r, center: c,
                              selected: minute == i * 5)
                    }
                }
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in pick(g.location, c, r, inner) }
                .onEnded { g in pick(g.location, c, r, inner); if pickingHour { pickingHour = false } })
        }
        .frame(width: size, height: size)
    }

    private func label(_ s: String, angle: Double, radius: CGFloat, center: CGPoint, selected: Bool, small: Bool = false) -> some View {
        Text(s)
            .font(.system(size: small ? 10 : 12, weight: selected ? .semibold : .regular)).monospacedDigit()
            .foregroundStyle(selected ? Color.white : (small ? Style.secondary : Color.primary))
            .position(DialGeometry.point(angle: angle, radius: radius, center: center))
    }

    private func pick(_ p: CGPoint, _ c: CGPoint, _ r: CGFloat, _ inner: CGFloat) {
        let a = DialGeometry.angle(of: p, center: c)
        if pickingHour {
            let idx = Int((a / 30).rounded()) % 12               // 0…11, 0 is 12 o'clock
            let dist = hypot(p.x - c.x, p.y - c.y)
            let outer = dist > (r + inner) / 2
            let h = idx == 0 ? 12 : idx
            hour = outer ? h : (h + 12) % 24
        } else {
            minute = Int((a / 6).rounded()) % 60
        }
    }
}
