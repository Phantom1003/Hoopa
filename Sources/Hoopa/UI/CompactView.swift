import SwiftUI

/// Collapsed: a mini list on a glass slab. One row per to-do: the ball (the to-do's head: the bound app's icon, a green fluffy ball when unbound; timed ones ringed by the time ring),
/// the title, the countdown at the right end (orange when nearly due, red once overdue). The ball's icon is the only cue to what is bound, no page name: that is on the chip in the details. With no to-dos at all the only row is "+ Add" (expands the panel and opens the composer); with to-dos it takes no row, creating goes through the expanded panel.
/// Same order as the panel (manual order; time order while sort by time is on). The slab shows `rows` rows (a setting, Rows When Collapsed in the ⋯ menu and the menu bar menu, 3 unless set);
/// a longer list scrolls inside that height with the wheel / trackpad (see WheelScroller: one row per wheel notch, settling on whole rows), the slab itself does not grow.
/// Clicking the ball of a bound to-do jumps to the bound page; clicking anywhere else on a row expands the panel and opens that to-do's details; pointing at a row, the countdown at the right end gives way to ○, click it to mark done.
/// Fixed width, independent of the content. Expanding is the ear outside the slab's left edge (see EarToggle). The glass is drawn by RootView's plate (collapsed, the plate is the slab), only the content lives here.
struct CompactView: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var coordinator: AppCoordinator
    @AppStorage("sortByTime") private var sortByTime = false
    /// How many rows the slab shows before the list scrolls (see rowsKey / rowChoices).
    @AppStorage(CompactView.rowsKey) private var rows = CompactView.defaultRows
    /// The row pointed at: highlighted, ○ at the right end.
    @State private var hovered: UUID?
    /// Scrolls the list while it is longer than the slab (the wheel events over the list come here, not to an NSScrollView).
    @StateObject private var wheel = WheelScroller()
    static let radius: CGFloat = 18       // same as the panel: the window mask has only one corner radius
    static let green = Color(red: 0.62, green: 0.80, blue: 0.30)   // the default green: the unbound fluffy ball, also the time ring's one-hour band
    /// The preference holding the number of rows shown while collapsed; the choices offered by the menus; the default.
    static let rowsKey = "compactRows"
    static let rowChoices = [3, 5, 8, 12]
    static let defaultRows = 3
    /// The number of rows in the preferences (for the AppKit menu, which cannot read @AppStorage): the default when unset or not one of the choices.
    static var storedRows: Int {
        let n = UserDefaults.standard.integer(forKey: rowsKey)
        return rowChoices.contains(n) ? n : defaultRows
    }
    private let width: CGFloat = 200          // content width (220 with the 10 inset on each side, much narrower than the panel)
    private let inset: CGFloat = 10           // the slab's horizontal inset
    private let insetV: CGFloat = 8           // vertical inset
    private let rowHeight: CGFloat = 22       // row height = the ball's diameter + 1 above and below; rows are only rowGap apart
    private let rowGap: CGFloat = 2
    private let ball: CGFloat = 20
    private let ringWidth: CGFloat = 2        // the time ring's width; the core is two ring widths smaller than the ball, sitting right inside the ring
    private let gap: CGFloat = 6
    /// The slab is at least this tall: the ear (Ear.top…Ear.top+Ear.height) has to land on the straight part of the left edge, above the bottom corner.
    private static let minHeight = Ear.top + Ear.height + CompactView.radius

    private var items: [TodoItem] { sortByTime ? store.byUrgency : store.active }

    var body: some View {
        let items = items
        let rows = Self.rowChoices.contains(rows) ? rows : Self.defaultRows
        let step = rowHeight + rowGap
        let scrolls = items.count > rows
        let contentHeight = CGFloat(items.count) * rowHeight + CGFloat(max(items.count - 1, 0)) * rowGap
        let visibleHeight = scrolls ? CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowGap : contentHeight
        // The scroller's range for this layout (its offset is only read here; a change of range settles the offset in onChange below).
        let range = max(contentHeight - visibleHeight, 0)
        let _ = wheel.configure(step: step, maxOffset: range)
        let offset = scrolls ? wheel.offset : 0
        let list = VStack(alignment: .leading, spacing: rowGap) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, t in
                // A row scrolled out of the visible rows is clipped, not gone: it must not take the hover or a click through the slab's margin either.
                let top = CGFloat(i) * step
                row(t).allowsHitTesting(top + rowHeight > offset + 0.5 && top < offset + visibleHeight - 0.5)
            }
            if items.isEmpty { addRow }
        }
        Group {
            if scrolls {
                // More to-dos than rows: the list is moved up by the scroller's offset inside the height of `rows` rows and clipped; the window is sized to the content (fitWindow), so the height is explicit.
                list
                    .offset(y: -offset)
                    .frame(height: visibleHeight, alignment: .top)
                    .clipped()
                    .overlay(alignment: .topTrailing) { indicator(visible: visibleHeight, content: contentHeight) }
                    // Where the list is in the window: the scroller takes the wheel events over this rect (SwiftUI's global space is the window's content view, see WheelScroller).
                    .background(GeometryReader { g in
                        Color.clear.onChange(of: g.frame(in: .global), initial: true) { _, f in wheel.frame = f }
                    })
            } else {
                list
            }
        }
        .onChange(of: range) { wheel.settle() }   // fewer to-dos, or fewer / more rows: back within range, on a whole row
        .frame(width: width, alignment: .leading)
        .padding(.horizontal, inset).padding(.vertical, insetV)
        // A list shorter than the slab (one row, or only "+ Add") sits in the middle, level with the ear, not at the top over a blank strip.
        .frame(minHeight: Self.minHeight, alignment: .center)
        .contentShape(Rectangle())        // the whole slab drags the window, the room around a short list included
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Style.text)
        .background(GeometryReader { g in
            // The slab proper (without the ear) is reported to RootView (root view coordinates): collapsed, the plate sits here; expanding, it grows out of here.
            Color.clear.preference(key: FrontGeometryKey.self,
                                   value: FrontGeometry(rect: g.frame(in: .named("root")), radius: Self.radius))
        })
        // Leave the ear's column on the left, or on the right when docked at the left edge (the slab's glass, ear included, is drawn by RootView's plate).
        .padding(coordinator.dockSide == .left ? .trailing : .leading, Ear.width)
        .windowDraggable()
        .contextMenu {
            Button("Expand") { coordinator.isCompact = false }
            Divider()
            Button("Quit Hoopa") { coordinator.onQuit?() }
        }
    }

    /// The scroll indicator: a thin pill in the slab's right margin (beside the countdowns, not over them), as long as the visible share of the list, shown for a moment after each scroll.
    private func indicator(visible: CGFloat, content: CGFloat) -> some View {
        let height = max(visible * visible / max(content, 1), 12)
        let y = (visible - height) * (wheel.offset / max(wheel.maxOffset, 1))
        return Capsule().fill(Style.tertiary)
            .frame(width: 3, height: height)
            .offset(x: 6, y: y)
            .opacity(wheel.active ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: wheel.active)
            .allowsHitTesting(false)
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

    /// A row: ball, title …… countdown. A click on the ball of a bound to-do jumps to the bound page; a click anywhere else expands the panel to the details.
    /// Pointing at the row, the countdown at the right end fades out and ○ takes its place (like a mail list where the date turns into action buttons); click ○ to mark done.
    /// ○ takes the countdown's slot, no extra column, the insets on both sides stay equal; untimed rows reserve the same width for ○, so the title does not shift on hover.
    private func row(_ t: TodoItem) -> some View {
        let isHovered = hovered == t.id
        return HStack(spacing: gap) {
            // The ball of a bound to-do jumps to the bound page (a spinner while it runs); an unbound ball has nothing to jump to and opens the details like the rest of the row.
            // A tap gesture, not a Button, like the row: the slab can still be dragged by the ball.
            ballView(t)
                .contentShape(Rectangle())
                .onTapGesture {
                    if t.binding != nil { coordinator.jump(t) } else { coordinator.expand(showing: t.id) }
                }
                .help(t.binding != nil ? Text("Jump to Bound Page") : Text("Show details"))
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
            Button("Copy") { coordinator.copy(t) }
            Button("Duplicate") { store.duplicate(t.id) }
            Divider()
            Button("Expand") { coordinator.isCompact = false }
            Button("Quit Hoopa") { coordinator.onQuit?() }
        }
    }

    /// The ball: the app icon for a bound page (a spinner while jumping), a fluffy ball with the title's first character when unbound.
    /// Timed ones carry the time ring on the edge (see TimeRing: bands of a week, a day, an hour, ten minutes, one minute, one lap each, colours from cool to warm,
    /// the track showing the next band's colour); the core steps in by one ring, the fluffy ball's colour follows the ring, the icon's background stays grey.
    /// Once overdue the ring is gold and the core is a hyperspace hole (see Hole): the icon or letter is pulled into it (Hole.Pull) and stays sunk, small and dim.
    private func ballView(_ t: TodoItem) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let label = t.due.map { TimeFormat.label($0, now: ctx.date) }
            let overdue = label?.overdue == true
            let ring = t.ring(now: ctx.date)
            let tint = Self.tint(ring)
            let core = t.due == nil ? ball : ball - ringWidth * 2
            ZStack {
                if overdue {
                    HoleView().frame(width: core, height: core)
                } else {
                    Circle().fill(t.binding == nil ? tint.opacity(0.35) : Style.chip)
                        .frame(width: core, height: core)
                }
                Group {
                    if coordinator.jumpingID == t.id {
                        ProgressView().controlSize(.mini)
                    } else if let b = t.binding {
                        AppIcon(binding: b, size: ball * 0.6)
                    } else {
                        Text(String(trimmed(t).prefix(1)))
                            .font(.system(size: ball * 0.42, weight: .semibold, design: .rounded))
                    }
                }
                .modifier(Sinking(overdue: overdue))
                if let ring {
                    TimeRing(state: ring, overdue: overdue, width: ringWidth)
                }
            }
            .frame(width: ball, height: ball)
        }
    }

    /// The pull into the hole (Hole.Pull) applied to the icon: the shrink and the fade. The hole's bulge is on the same animator: the hole is drawn under the icon here and scaled with it. A to-do that is already overdue when its row appears starts sunk, without the pull.
    private struct Sinking: ViewModifier {
        let overdue: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            content
                .keyframeAnimator(initialValue: overdue ? Hole.Pull.sunk : Hole.Pull.idle, trigger: overdue) { content, v in
                    content
                        .scaleEffect(v.scale)
                        .opacity(v.opacity)
                        .background {
                            if overdue { HoleView().scaleEffect(v.hole) }
                        }
                } keyframes: { _ in
                    Hole.Pull.keyframes(sinking: overdue, animated: !reduceMotion)
                }
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

    /// The fluffy ball's core follows the time ring: the current band's colour; the default green without a time. (Overdue, the core is the hole, see ballView.)
    private static func tint(_ ring: Ladder.State?) -> Color { ring?.color ?? green }
}

/// Wheel / trackpad scrolling of the collapsed list, done by Hoopa itself rather than an NSScrollView: with the system's wheel acceleration a single notch throws a three-row list several rows on.
/// A local event monitor takes the scroll wheel events over the list (this app's own events in its own window; nothing is posted) and moves the list one row per notch, however fast the wheel spins, with a short ease.
/// A trackpad moves the list by the distance of the fingers (momentum included), and once they and the momentum stop the list settles on a whole row, so a row is never cut in half at rest. Events anywhere else pass on untouched.
final class WheelScroller: ObservableObject {
    /// How far the list is scrolled up, in points (0 … maxOffset).
    @Published private(set) var offset: CGFloat = 0
    /// Scrolled a moment ago: the indicator shows.
    @Published private(set) var active = false
    /// The list's rect in the window's content view (SwiftUI's global space): events outside it are not ours.
    var frame = CGRect.zero
    private(set) var step: CGFloat = 24
    private(set) var maxOffset: CGFloat = 0
    /// Where the list is heading (ahead of the animated offset while notches arrive faster than the ease plays).
    private var target: CGFloat = 0
    private var monitor: Any?
    private var settleWork: DispatchWorkItem?
    private var fadeWork: DispatchWorkItem?
    private static let ease = Animation.smooth(duration: 0.3)

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, self.handle(e) else { return e }
            return nil
        }
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    /// The row step and the range for the current layout (called from the view's body: only stored, nothing published here; the view settles the offset when the range changes).
    func configure(step: CGFloat, maxOffset: CGFloat) {
        self.step = step
        self.maxOffset = maxOffset
    }

    /// Back within range, on a whole row, with the ease (after the range changed, or once a trackpad scroll has come to rest).
    func settle() {
        target = clamp((target / step).rounded() * step)
        guard target != offset else { return }
        withAnimation(Self.ease) { offset = target }
    }

    /// True when the event was over the list and has been used.
    private func handle(_ e: NSEvent) -> Bool {
        guard maxOffset > 0, e.window is FloatingPanel, let content = e.window?.contentView else { return false }
        guard frame.contains(content.convert(e.locationInWindow, from: nil)) else { return false }
        let dy = e.scrollingDeltaY
        if e.hasPreciseScrollingDeltas {
            // Trackpad: follow the fingers (and the momentum) directly; settle on a row a moment after the last movement.
            target = clamp(target - dy)
            offset = target
            settleWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.settle() }
            settleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        } else if dy != 0 {
            // Wheel: one row per notch in the notch's direction, from the row the list is heading to; the system's acceleration (several lines per notch) is ignored.
            settleWork?.cancel()
            target = clamp(((target / step).rounded() - (dy > 0 ? 1 : -1)) * step)
            withAnimation(Self.ease) { offset = target }
        }
        showIndicator()
        return true
    }

    private func clamp(_ v: CGFloat) -> CGFloat { min(max(v, 0), maxOffset) }

    private func showIndicator() {
        if !active { active = true }
        fadeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.active = false }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}
