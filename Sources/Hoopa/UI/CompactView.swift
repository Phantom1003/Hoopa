import SwiftUI

/// Collapsed: a mini list on a glass slab. One row per to-do: the ball (the to-do's head: the bound app's icon, a green fluffy ball when unbound; timed ones ringed by the time ring),
/// title · page name, the countdown at the right end (orange when nearly due, red once overdue); the last row is "+ Add" (expands the panel and opens the composer).
/// Same order as the panel (manual order; time order while sort by time is on), at most 6 rows, then "+N more" (opens the panel).
/// Clicking a row: jumps when bound, otherwise expands the panel to its details; pointing at a row shows ○ at the right end, click it to mark done. Fixed width, independent of the content.
/// Expanding is the ear outside the slab's left edge (see EarToggle). The glass is drawn by RootView's plate (collapsed, the plate is the slab), only the content lives here.
struct CompactView: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var coordinator: AppCoordinator
    @AppStorage("sortByTime") private var sortByTime = false
    /// The row pointed at: highlighted, ○ at the right end.
    @State private var hovered: UUID?
    static let radius: CGFloat = 18       // same as the panel: the window mask has only one corner radius
    static let green = Color(red: 0.62, green: 0.80, blue: 0.30)   // the default green: the unbound fluffy ball, also the time ring's one-hour band
    private let width: CGFloat = 236          // content width (260 with the 12 inset on each side, narrower than the panel)
    private let rowHeight: CGFloat = 25       // as tall as ⌄
    private let rowGap: CGFloat = 3
    private let ball: CGFloat = 22
    private let maxRows = 6
    private let gap: CGFloat = 6

    private var items: [TodoItem] { sortByTime ? store.byUrgency : store.active }

    var body: some View {
        let items = items
        let shown = Array(items.prefix(maxRows))
        let extra = items.count - shown.count
        VStack(alignment: .leading, spacing: rowGap) {
            ForEach(shown) { t in row(t) }
            if extra > 0 {
                Button { coordinator.isCompact = false } label: {
                    Text("\(extra) more").font(.system(size: 11)).foregroundStyle(Style.tertiary)
                        .padding(.leading, ball + gap)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            addRow
        }
        .frame(width: width, alignment: .leading)
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 10)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Style.text)
        .background(GeometryReader { g in
            // The slab proper (without the ear) is reported to RootView (root view coordinates): collapsed, the plate sits here; expanding, it grows out of here.
            Color.clear.preference(key: FrontGeometryKey.self,
                                   value: FrontGeometry(rect: g.frame(in: .named("root")), radius: Self.radius))
        })
        // Leave the ear's column on the left (the slab's glass, ear included, is drawn by RootView's plate).
        .padding(.leading, Ear.width)
        .windowDraggable()
        .contextMenu {
            Button("Expand") { coordinator.isCompact = false }
            Divider()
            Button("Quit Hoopa") { coordinator.onQuit?() }
        }
    }

    /// The last row: a green + ball and grey text; a click expands the panel and opens the composer.
    private var addRow: some View {
        Button { coordinator.expandToAdd() } label: {
            HStack(spacing: gap) {
                ZStack {
                    Circle().fill(Self.green.opacity(0.35))
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Style.secondary)
                }
                .frame(width: ball, height: ball)
                Text("Add a to-do").font(.system(size: 12)).foregroundStyle(Style.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add a to-do")
    }

    /// A row: ball, title · page name …… countdown [○]. A click jumps (or shows the details when unbound).
    private func row(_ t: TodoItem) -> some View {
        let isHovered = hovered == t.id
        return HStack(spacing: gap) {
            ballView(t)
            titleLine(t)
            Spacer(minLength: 8)
            if let d = t.due { time(d) }
            // ○ keeps its slot at all times (shown only when pointed at), so the countdown does not shift on hover.
            Button { store.toggleDone(t.id) } label: {
                Image(systemName: "circle").font(.system(size: 14)).foregroundStyle(Style.secondary)
                    .frame(width: 16, height: rowHeight).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Mark as done")
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isHovered ? Style.card : Color.clear))
        .onHover { inside in
            if inside { hovered = t.id } else if hovered == t.id { hovered = nil }
        }
        .onTapGesture { open(t) }
        .help(t.binding.map { String(localized: "Back to \($0.shortDescription)") } ?? String(localized: "Show details"))
        .contextMenu {
            if t.binding != nil { Button("Jump to Bound Page") { coordinator.jump(t) } }
            Button("Show details") { coordinator.expand(showing: t.id) }
            Button("Mark as Done") { store.toggleDone(t.id) }
            Divider()
            Button("Expand") { coordinator.isCompact = false }
            Button("Quit Hoopa") { coordinator.onQuit?() }
        }
    }

    private func open(_ t: TodoItem) {
        if t.binding != nil { coordinator.jump(t) } else { coordinator.expand(showing: t.id) }
    }

    /// The ball: the app icon for a bound page (a spinner while jumping); a green fluffy ball with the title's first character when unbound. Timed ones are ringed by the time ring.
    private func ballView(_ t: TodoItem) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let label = t.due.map { TimeFormat.label($0, now: ctx.date) }
            let tint = Self.tint(label)
            ZStack {
                Circle().fill(t.binding == nil ? Self.green.opacity(0.35) : Style.chip)
                if coordinator.jumpingID == t.id {
                    ProgressView().controlSize(.mini)
                } else if let b = t.binding {
                    AppIcon(binding: b, size: ball * 0.6)
                } else {
                    Text(String(trimmed(t).prefix(1)))
                        .font(.system(size: ball * 0.42, weight: .semibold, design: .rounded))
                }
                if let d = t.due {
                    Circle().trim(from: 0, to: label?.overdue == true ? 1 : Self.fraction(d, now: ctx.date))
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1)
                }
            }
            .frame(width: ball, height: ball)
        }
    }

    private func trimmed(_ t: TodoItem) -> String { t.title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// title · page name: the page name is shown only when both fit, otherwise the title alone (truncated), so the page name is never cut to a character or two.
    /// An empty title falls back to the page name, otherwise the grey placeholder.
    private func titleLine(_ t: TodoItem) -> some View {
        let title = trimmed(t)
        let heading = Group {
            if !title.isEmpty {
                Text(title)
            } else if let b = t.binding {
                Text(b.pageName)
            } else {
                Text("To-do").foregroundStyle(Style.tertiary)
            }
        }
        .lineLimit(1).truncationMode(.tail)
        return ViewThatFits(in: .horizontal) {
            if let b = t.binding, !title.isEmpty {
                HStack(spacing: 4) {
                    heading.fixedSize()
                    Text(verbatim: "·").foregroundStyle(Style.tertiary)
                    Text(b.pageName).font(.system(size: 11)).foregroundStyle(Style.secondary).lineLimit(1).fixedSize()
                }
            }
            heading
        }
    }

    /// The countdown at the right end (refreshed every second; "Overdue" / "Time's up" once past due); hover for the absolute time.
    private func time(_ d: Due) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let l = TimeFormat.label(d, now: ctx.date)
            Text(l.text).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(l.overdue ? Style.overdue : (l.urgent ? Style.urgent : Style.secondary))
                .fixedSize()
                .help(l.detail)
        }
    }

    /// The colour of the time ring / countdown: red once overdue, orange when nearly due, otherwise the default green.
    private static func tint(_ l: TimeFormat.DueLabel?) -> Color {
        guard let l else { return green }
        return l.overdue ? Style.overdue : (l.urgent ? Style.urgent : green)
    }

    /// How much of the time ring is left: a countdown against its set length; a date-time against the last 24 hours.
    private static func fraction(_ due: Due, now: Date) -> Double {
        switch due {
        case .countdown(let end, let minutes):
            return max(0, min(1, end.timeIntervalSince(now) / Double(max(minutes, 1) * 60)))
        case .dateTime(let d), .date(let d):
            return max(0, min(1, d.timeIntervalSince(now) / 86400))
        }
    }
}
