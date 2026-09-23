import SwiftUI

/// A self-drawn month calendar of fixed size: click the year for the year grid (pageable to any year), the month for the month grid.
struct CalendarGrid: View {
    @Binding var selected: Date
    var onPick: (() -> Void)? = nil

    private enum Mode { case days, months, years }
    @State private var mode: Mode = .days
    @State private var shownMonth: Date = Date()
    @State private var yearPageStart = 0
    private let cal = Calendar.current
    private let cell: CGFloat = 28
    private let gridHeight: CGFloat = 6 * 30      // the height of 6 rows of days, shared by all three modes so the window does not change

    var body: some View {
        VStack(spacing: 8) {
            header
            switch mode {
            case .days:
                weekdays
                days
            case .months:
                months
            case .years:
                years
            }
        }
        .padding(10)
        .frame(width: 7 * cell + 20)
        .onAppear { shownMonth = cal.startOfMonth(selected) }
        .onChange(of: selected) { _, d in shownMonth = cal.startOfMonth(d) }
    }

    // MARK: Header

    private var shownYear: Int { cal.component(.year, from: shownMonth) }
    private var shownMonthNumber: Int { cal.component(.month, from: shownMonth) }

    private var header: some View {
        HStack(spacing: 4) {
            Button { page(-1) } label: { Image(systemName: "chevron.left") }
                .glassButton().controlSize(.mini)
            Spacer()
            // String(...) on purpose: SwiftUI's Text interpolation adds a thousands separator to numbers (2,026).
            Button(String(shownYear)) { toggle(.years) }
                .buttonStyle(.plain).monospacedDigit()
                .foregroundStyle(mode == .years ? Style.accent : Color.primary)
            Button(String(shownMonthNumber)) { toggle(.months) }
                .buttonStyle(.plain).monospacedDigit()
                .foregroundStyle(mode == .months ? Style.accent : Color.primary)
            Spacer()
            Button { page(1) } label: { Image(systemName: "chevron.right") }
                .glassButton().controlSize(.mini)
        }
        .font(.system(size: 12, weight: .semibold))
    }

    private func toggle(_ m: Mode) {
        if mode == m { mode = .days; return }
        mode = m
        if m == .years { yearPageStart = shownYear - shownYear % 12 }
    }

    /// The arrows: months in day mode, years in month mode, 12 years in year mode.
    private func page(_ dir: Int) {
        switch mode {
        case .days: shownMonth = cal.date(byAdding: .month, value: dir, to: shownMonth) ?? shownMonth
        case .months: set(year: shownYear + dir)
        case .years: yearPageStart += dir * 12
        }
    }

    // MARK: Days

    private var weekdays: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols   // the system's first weekday
        let start = cal.firstWeekday - 1
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                Text(symbols[(start + i) % 7])
                    .font(.system(size: 10)).foregroundStyle(Style.secondary)
                    .frame(width: cell)
            }
        }
    }

    private var days: some View {
        let first = cal.startOfMonth(shownMonth)
        let count = cal.range(of: .day, in: .month, for: first)!.count
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        return VStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { r in     // always 6 rows, the height does not change with the month
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        let idx = r * 7 + c - lead
                        if idx >= 0 && idx < count, let d = cal.date(byAdding: .day, value: idx, to: first) {
                            dayCell(d, number: idx + 1)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .frame(height: gridHeight - 18, alignment: .top)
    }

    private func dayCell(_ d: Date, number: Int) -> some View {
        let isSelected = cal.isDate(d, inSameDayAs: selected)
        let isToday = cal.isDateInToday(d)
        return Button {
            selected = cal.startOfDay(for: d)
            onPick?()
        } label: {
            Text(String(number))
                .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular)).monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : (isToday ? Style.accent : Color.primary))
                .frame(width: cell - 4, height: cell - 4)
                .background {
                    if isSelected {
                        Circle().fill(Color.clear).tintedGlass(Circle())
                    } else if isToday {
                        Circle().stroke(Style.accent.opacity(0.6), lineWidth: 1)
                    }
                }
                .frame(width: cell, height: cell)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Month / year grid (4 × 3, filling the same height as the day area, styled like the day cells)

    private var months: some View {
        let now = cal.component(.month, from: Date())
        let sameYear = shownYear == cal.component(.year, from: Date())
        return grid(items: Array(1...12), label: { String($0) },
                    selected: shownMonthNumber, today: sameYear ? now : nil) { m in
            set(month: m); mode = .days
        }
    }

    private var years: some View {
        grid(items: Array(yearPageStart..<(yearPageStart + 12)), label: { String($0) },
             selected: shownYear, today: cal.component(.year, from: Date())) { y in
            set(year: y); mode = .months
        }
    }

    private func grid(items: [Int], label: @escaping (Int) -> String, selected: Int, today: Int?,
                      pick: @escaping (Int) -> Void) -> some View {
        let rowHeight = (gridHeight - 3 * 6) / 4
        return VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { c in
                        let v = items[r * 3 + c]
                        let isSelected = v == selected
                        let isToday = v == today
                        Button { pick(v) } label: {
                            Text(label(v))
                                .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular)).monospacedDigit()
                                .foregroundStyle(isSelected ? Color.white : (isToday ? Style.accent : Color.primary))
                                .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight)
                                .background {
                                    if isSelected {
                                        Capsule().fill(Color.clear).tintedGlass(Capsule())
                                    } else if isToday {
                                        Capsule().stroke(Style.accent.opacity(0.6), lineWidth: 1)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(height: gridHeight)
    }

    private func set(year: Int? = nil, month: Int? = nil) {
        var comps = cal.dateComponents([.year, .month], from: shownMonth)
        if let year { comps.year = year }
        if let month { comps.month = month }
        comps.day = 1
        shownMonth = cal.date(from: comps) ?? shownMonth
    }
}

private extension Calendar {
    func startOfMonth(_ d: Date) -> Date {
        date(from: dateComponents([.year, .month], from: d)) ?? d
    }
}
