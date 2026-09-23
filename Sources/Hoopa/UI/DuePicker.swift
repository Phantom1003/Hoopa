import SwiftUI

/// The popover for setting a countdown / date-time (buttons and dials in the Liquid Glass style).
/// A chosen countdown only keeps the minutes; ticking starts at the moment of submission.
struct DuePicker: View {
    @Binding var spec: DueSpec?
    var onDone: () -> Void

    private enum Tab: String, CaseIterable { case countdown = "Countdown", dateTime = "Date & time" }
    @State private var tab: Tab = .countdown
    @State private var minutes = 25
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var hour = Calendar.current.component(.hour, from: Date())
    @State private var minute = Calendar.current.component(.minute, from: Date())
    private let presets = [5, 10, 15, 25, 45, 60]
    @State private var showCalendar = false

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab == .countdown {
                CountdownDial(minutes: $minutes)
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { m in
                        Button { minutes = m } label: { Text("\(m)").monospacedDigit().frame(maxWidth: .infinity) }
                            .glassButton(prominent: minutes == m)
                            .controlSize(.small)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Button(["Today", "Tomorrow", "Day after"][i]) { setDay(i) }
                            .glassButton(prominent: isDay(i)).controlSize(.small).fixedSize()
                    }
                    Spacer()
                    // Other days: open the calendar. The text uses a fixed month-day format at a fixed width, so it does not jitter when the day changes.
                    Button { showCalendar = true } label: {
                        Label(TimeFormat.monthDay(day), systemImage: "calendar")
                            .monospacedDigit()
                            .frame(width: 74)
                    }
                    .glassButton(prominent: !(isDay(0) || isDay(1) || isDay(2))).controlSize(.small)
                    .popover(isPresented: $showCalendar) {
                        CalendarGrid(selected: $day) { showCalendar = false }
                    }
                }
                ClockDial(hour: $hour, minute: $minute)
            }

            HStack(spacing: 8) {
                if spec != nil {
                    Button("Remove Time", role: .destructive) { spec = nil; onDone() }
                        .glassButton().controlSize(.small)
                }
                Button("Cancel") { onDone() }.glassButton().controlSize(.small)
                Spacer()
                Button(action: apply) {
                    Text(tab == .countdown ? "Set \(minutes) min" : "Set \(TimeFormat.day(day, now: Date())) \(String(format: "%02d:%02d", hour, minute))")
                        .monospacedDigit()
                }
                .glassButton(prominent: true).controlSize(.small)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(width: 280)
        .onAppear {
            switch spec {
            case .countdown(let m): minutes = m; tab = .countdown
            case .dateTime(let d):
                tab = .dateTime
                day = Calendar.current.startOfDay(for: d)
                hour = Calendar.current.component(.hour, from: d)
                minute = Calendar.current.component(.minute, from: d)
            case nil: break
            }
        }
    }

    private func apply() {
        switch tab {
        case .countdown: spec = .countdown(minutes: minutes)
        case .dateTime: spec = .dateTime(Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day)
        }
        onDone()
    }

    private func setDay(_ offset: Int) {
        day = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
    }

    private func isDay(_ offset: Int) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }
}

/// A time setting not yet submitted (a countdown does not tick, it only shows the minutes).
struct SpecChip: View {
    let spec: DueSpec
    var bare = false
    var body: some View {
        switch spec {
        case .countdown(let m):
            // Not ticking yet, but a due moment is projected as if submitted now (grey) and refreshes with the current time.
            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                HStack(spacing: 4) {
                    Image(systemName: "timer").font(.system(size: 11))
                    Text(TimeFormat.minutes(m))
                    Text("·").foregroundStyle(Style.tertiary)
                    Text(TimeFormat.clockTime(ctx.date.addingTimeInterval(TimeInterval(m * 60))))
                        .monospacedDigit().foregroundStyle(Style.secondary)
                }
                .foregroundStyle(Style.text)
            }
            .modifier(OptionalChip(enabled: !bare))
        case .dateTime(let d):
            DueChip(due: .dateTime(d), bare: bare)
        }
    }
}
