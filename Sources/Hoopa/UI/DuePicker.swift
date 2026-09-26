import SwiftUI

/// The popover for setting a countdown / date-time (buttons and dials in the Liquid Glass style).
/// A chosen countdown only keeps the minutes; ticking starts at the moment of submission.
struct DuePicker: View {
    @Binding var spec: DueSpec?
    var onDone: () -> Void

    private enum Tab: CaseIterable {
        case countdown, dateTime
        var title: LocalizedStringKey { self == .countdown ? "Timer" : "Date & Time" }
    }
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
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
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
                // Text lengths change with the interface language (English Tomorrow, Sep 28 are much wider than the Chinese forms), so the buttons neither size to content nor share one row, or they would overflow the panel:
                // Today / tomorrow / the day after are three equal cells filling one row (in the interface language's relative words; English has no word for the day after and shows the date);
                // below it the date field spans the row: the chosen full date (Sep 25, 2026 and the localized equivalent), click to open the calendar for another day.
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in
                            Button { setDay(i) } label: {
                                Text(TimeFormat.day(offsetDay(i), now: Date())).lineLimit(1).frame(maxWidth: .infinity)
                            }
                            .glassButton(prominent: isDay(i)).controlSize(.small)
                        }
                    }
                    Button { showCalendar = true } label: {
                        Label(TimeFormat.fullDate(day), systemImage: "calendar")
                            .monospacedDigit().lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .glassButton(prominent: !(isDay(0) || isDay(1) || isDay(2))).controlSize(.small)
                    .popover(isPresented: $showCalendar) {
                        CalendarGrid(selected: $day) { showCalendar = false }
                    }
                }
                ClockDial(hour: $hour, minute: $minute)
            }

            HStack(spacing: 8) {
                // The buttons on the left size to content; the main button on the right spells it out when there is room (Set Tomorrow 13:03), otherwise just "Set", never truncated or overflowing.
                if spec != nil {
                    Button("Remove Time", role: .destructive) { spec = nil; onDone() }
                        .glassButton().controlSize(.small).fixedSize()
                }
                Button("Cancel") { onDone() }.glassButton().controlSize(.small).fixedSize()
                Spacer()
                Button(action: apply) {
                    ViewThatFits(in: .horizontal) {
                        Text(tab == .countdown ? "Set \(minutes) min" : "Set \(TimeFormat.day(day, now: Date())) \(String(format: "%02d:%02d", hour, minute))")
                        Text("Set")
                    }
                    .monospacedDigit()
                }
                .glassButton(prominent: true).controlSize(.small)
                .keyboardShortcut(.return, modifiers: [])
                .layoutPriority(1)      // give the main button the remaining width first, then decide between the long and the short label
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

    private func offsetDay(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
    }

    private func setDay(_ offset: Int) { day = offsetDay(offset) }

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
                    Text(TimeFormat.duration(m * 60)).monospacedDigit()
                    Text("·").foregroundStyle(Style.tertiary)
                    Text(TimeFormat.absolute(ctx.date.addingTimeInterval(TimeInterval(m * 60)), now: ctx.date))
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
