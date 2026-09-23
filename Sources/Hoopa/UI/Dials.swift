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

/// The countdown dial: drag to set 1–120 minutes, the scroll wheel fine-tunes; the minutes show in the middle.
struct CountdownDial: View {
    @Binding var minutes: Int
    let maxMinutes = 120
    private let size: CGFloat = 170

    var body: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = min(geo.size.width, geo.size.height) / 2 - 10
            let angle = Double(minutes) / Double(maxMinutes) * 360
            ZStack {
                Circle().stroke(Style.chip, lineWidth: 6).frame(width: r * 2, height: r * 2)
                Circle()
                    .trim(from: 0, to: CGFloat(minutes) / CGFloat(maxMinutes))
                    .stroke(Style.accent.opacity(0.55), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: r * 2, height: r * 2)
                ForEach(1...12, id: \.self) { i in
                    let a = Double(i) / 12 * 360
                    Text("\(i * 10)")
                        .font(.system(size: 9)).foregroundStyle(Style.tertiary)
                        .position(DialGeometry.point(angle: a, radius: r - 16, center: c))
                }
                Circle().fill(Color.clear).frame(width: 18, height: 18).tintedGlass(Circle())
                    .position(DialGeometry.point(angle: angle, radius: r, center: c))
                VStack(spacing: 0) {
                    Text("\(minutes)").font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("min").font(.system(size: 11)).foregroundStyle(Style.secondary)
                }
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let a = DialGeometry.angle(of: g.location, center: c)
                minutes = max(1, min(maxMinutes, Int((a / 360 * Double(maxMinutes)).rounded())))
            })
        }
        .frame(width: size, height: size)
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
