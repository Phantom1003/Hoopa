import SwiftUI

/// The popover for setting a countdown / date.
struct DuePicker: View {
    @Binding var due: Due?
    var onDone: () -> Void

    @State private var minutes = 25
    @State private var day = Date()
    private let presets = [5, 10, 15, 25, 45, 60, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Countdown").font(.caption).foregroundStyle(Style.secondary)
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { m in
                    Button(TimeFormat.minutes(m)) { setCountdown(m) }
                        .buttonStyle(.plain)
                        .chip(isCurrent(m) ? Style.accent.opacity(0.3) : Style.chip)
                }
            }
            HStack(spacing: 8) {
                Stepper(value: $minutes, in: 1...999, step: 1) {
                    Text("\(minutes) min").monospacedDigit()
                }
                Button("Start") { setCountdown(minutes) }.controlSize(.small)
            }

            Divider()
            Text("Date").font(.caption).foregroundStyle(Style.secondary)
            HStack(spacing: 6) {
                Button("Today") { setDate(0) }.buttonStyle(.plain).chip()
                Button("Tomorrow") { setDate(1) }.buttonStyle(.plain).chip()
                Button("Day after") { setDate(2) }.buttonStyle(.plain).chip()
                DatePicker("", selection: $day, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .onChange(of: day) { _, d in due = .date(Calendar.current.startOfDay(for: d)) }
            }

            if due != nil {
                Divider()
                Button("Clear Time", role: .destructive) { due = nil; onDone() }.controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            if case .countdown(_, let m) = due { minutes = m }
            if case .date(let d) = due { day = d }
        }
    }

    private func isCurrent(_ m: Int) -> Bool {
        if case .countdown(_, let cur) = due { return cur == m }
        return false
    }

    private func setCountdown(_ m: Int) {
        due = .countdown(end: Date().addingTimeInterval(TimeInterval(m * 60)), minutes: m)
        onDone()
    }

    private func setDate(_ offset: Int) {
        let d = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
        due = .date(d)
        onDone()
    }
}
