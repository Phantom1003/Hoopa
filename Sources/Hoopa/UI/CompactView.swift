import SwiftUI

/// Collapsed: a mini list on a glass slab. One row per to-do: the ball (the to-do's head: the bound app's icon, a green fluffy ball when unbound; timed ones ringed by the time ring),
/// the title, the countdown at the right end (orange when nearly due, red once overdue). The ball's icon is the only cue to what is bound, no page name: that is on the chip in the details. With no to-dos at all the only row is "+ Add" (expands the panel and opens the composer); with to-dos it takes no row, creating goes through the expanded panel.
/// Same order as the panel (manual order; time order while sort by time is on), at most 6 rows, then "+N more" (opens the panel).
/// Clicking a row: expands the panel and opens that to-do's details (jumping is the chip in the details, or the context menu); pointing at a row, the countdown at the right end gives way to ○, click it to mark done.
/// Fixed width, independent of the content. Expanding is the ear outside the slab's left edge (see EarToggle). The glass is drawn by RootView's plate (collapsed, the plate is the slab), only the content lives here.
struct CompactView: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var coordinator: AppCoordinator
    @AppStorage("sortByTime") private var sortByTime = false
    /// The row pointed at: highlighted, ○ at the right end.
    @State private var hovered: UUID?
    static let radius: CGFloat = 18       // same as the panel: the window mask has only one corner radius
    static let green = Color(red: 0.62, green: 0.80, blue: 0.30)   // the default green: the unbound fluffy ball, also the time ring's one-hour band
    private let width: CGFloat = 200          // content width (220 with the 10 inset on each side, much narrower than the panel)
    private let inset: CGFloat = 10           // the slab's horizontal inset
    private let insetV: CGFloat = 8           // vertical inset
    private let rowHeight: CGFloat = 22       // row height = the ball's diameter + 1 above and below; rows are only rowGap apart
    private let rowGap: CGFloat = 2
    private let ball: CGFloat = 20
    private let ringWidth: CGFloat = 2        // the time ring's width; the core is two ring widths smaller than the ball, sitting right inside the ring
    private let maxRows = 6
    private let gap: CGFloat = 6
    /// The slab is at least this tall: the ear (Ear.top…Ear.top+Ear.height) has to land on the straight part of the left edge, above the bottom corner.
    private static let minHeight = Ear.top + Ear.height + CompactView.radius

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
            if items.isEmpty { addRow }
        }
        .frame(width: width, alignment: .leading)
        .padding(.horizontal, inset).padding(.vertical, insetV)
        .frame(minHeight: Self.minHeight, alignment: .top)
        .contentShape(Rectangle())        // the whole slab drags the window, the room under a short list included
        .font(.system(size: 12, weight: .medium))
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

    /// The only row of an empty list: a green + ball and grey text; a click expands the panel and opens the composer. Hidden while there are to-dos (the expanded panel has a +, this row would only repeat it).
    /// A tap gesture like the to-do rows, not a Button: a button swallows the press, and the slab (which this row fills) could no longer be dragged by it.
    private var addRow: some View {
        HStack(spacing: gap) {
            ZStack {
                Circle().fill(Self.green.opacity(0.35))
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(Style.secondary)
            }
            .frame(width: ball, height: ball)
            Text("Add a to-do").font(.system(size: 11)).foregroundStyle(Style.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .onTapGesture { coordinator.expandToAdd() }
        .help("Add a to-do")
    }

    /// A row: ball, title …… countdown. A click expands the panel to the details (no direct jump: jumping is the chip in the details, or the context menu).
    /// Pointing at the row, the countdown at the right end fades out and ○ takes its place (like a mail list where the date turns into action buttons); click ○ to mark done. The ball stays a ball, never a button.
    /// ○ takes the countdown's slot, no extra column, the insets on both sides stay equal; untimed rows reserve the same width for ○, so the title does not shift on hover.
    private func row(_ t: TodoItem) -> some View {
        let isHovered = hovered == t.id
        return HStack(spacing: gap) {
            ballView(t)
            titleLine(t)
            Spacer(minLength: 6)
            ZStack(alignment: .trailing) {
                if let d = t.due { time(d).opacity(isHovered ? 0 : 1) }
                Button { store.toggleDone(t.id) } label: {
                    // A 16pt circle, right aligned: its right edge coincides with the countdown's (10pt from the slab's right edge, symmetric with the ball on the left); the click area is the whole 20pt cell.
                    Circle().strokeBorder(Style.secondary, lineWidth: 1.5)
                        .frame(width: ball - 4, height: ball - 4)
                        .frame(width: ball, height: ball, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
                .help("Mark as done")
            }
            .animation(.easeOut(duration: 0.1), value: isHovered)
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isHovered ? Style.card : Color.clear))
        .onHover { inside in
            if inside { hovered = t.id } else if hovered == t.id { hovered = nil }
        }
        .onTapGesture { coordinator.expand(showing: t.id) }
        .help("Show details")
        .contextMenu {
            if t.binding != nil { Button("Jump to Bound Page") { coordinator.jump(t) } }
            Button("Mark as Done") { store.toggleDone(t.id) }
            Divider()
            Button("Expand") { coordinator.isCompact = false }
            Button("Quit Hoopa") { coordinator.onQuit?() }
        }
    }

    /// The ball: the app icon for a bound page (a spinner while jumping), a fluffy ball with the title's first character when unbound.
    /// Timed ones carry the time ring on the edge (see TimeRing: bands of a week, a day, an hour, ten minutes, five minutes, one minute, one lap each, colours from cool to warm,
    /// the track showing the next band's colour, a full red lap once overdue); the core steps in by one ring, the fluffy ball's colour follows the ring, the icon's background stays grey.
    private func ballView(_ t: TodoItem) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let label = t.due.map { TimeFormat.label($0, now: ctx.date) }
            let ring = t.ring(now: ctx.date)
            let tint = Self.tint(ring, overdue: label?.overdue == true)
            let core = t.due == nil ? ball : ball - ringWidth * 2
            ZStack {
                Circle().fill(t.binding == nil ? tint.opacity(0.35) : Style.chip)
                    .frame(width: core, height: core)
                if coordinator.jumpingID == t.id {
                    ProgressView().controlSize(.mini)
                } else if let b = t.binding {
                    AppIcon(binding: b, size: ball * 0.6)
                } else {
                    Text(String(trimmed(t).prefix(1)))
                        .font(.system(size: ball * 0.42, weight: .semibold, design: .rounded))
                }
                if let ring {
                    TimeRing(state: ring, overdue: label?.overdue == true, width: ringWidth)
                }
            }
            .frame(width: ball, height: ball)
        }
    }

    private func trimmed(_ t: TodoItem) -> String { t.title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The title, one line (truncated). An empty title falls back to the page name, otherwise the grey placeholder.
    private func titleLine(_ t: TodoItem) -> some View {
        let title = trimmed(t)
        return Group {
            if !title.isEmpty {
                Text(title)
            } else if let b = t.binding {
                Text(b.pageName)
            } else {
                Text("To-do").foregroundStyle(Style.tertiary)
            }
        }
        .lineLimit(1).truncationMode(.tail)
    }

    /// The countdown at the right end (refreshed every second; orange in the last ten minutes, red in the last minute, red "Overdue" once past due).
    /// It gives way to ○ when the row is pointed at, so it carries no absolute-time tooltip: the absolute time is on the time chip in the details.
    private func time(_ d: Due) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let l = TimeFormat.label(d, now: ctx.date)
            Text(l.text).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(l.alert ?? Style.secondary)
                .fixedSize()
        }
    }

    /// The fluffy ball's core follows the time ring: red once overdue, otherwise the current band's colour; the default green without a time.
    private static func tint(_ ring: Ladder.State?, overdue: Bool) -> Color {
        guard let ring else { return green }
        return overdue ? Style.overdue : ring.color
    }
}
