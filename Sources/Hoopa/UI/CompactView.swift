import SwiftUI

/// Collapsed: normally a pill (the front to-do). On hover the pill first becomes a card (the same card re-laid out: the glass outline's size and corner radius
/// morph continuously, the content cross-fades), then the cards behind it appear from behind; moving away reverses it (timing in AppCoordinator.stage).
/// In the card stack the scroll wheel or a click on a card behind brings it to the front; folded up, the pill shows that one.
struct CompactView: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var front = 0
    @State private var scrollAccum: CGFloat = 0
    @State private var hoverWork: DispatchWorkItem?
    @State private var hovering = false
    static let cardWidth: CGFloat = 276       // as wide as a to-do card in the narrowest expanded panel (300); the pill is never wider
    private let pillRadius: CGFloat = 17
    private let peek: CGFloat = 9
    private let maxBehind = 2

    private var stage: CompactStage { coordinator.stage }

    var body: some View {
        let items = store.byUrgency
        let n = items.count
        Group {
            if n == 0 { addButton } else { stack(items) }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Style.text)
        // No fixedSize: it would centre the content in the frame that is growing / shrinking, and the card would pop out of the middle and slide to the top left when the pill becomes a card.
        // Each card sizes itself (MorphLayout ignores the size proposed from outside), top-left aligned all the way.
        .onHover(perform: hover)
        .windowDraggable()
        .onChange(of: n) { _, count in
            if count > 0 { front %= count } else { front = 0; coordinator.hoverCompact(false) }
        }
        .contextMenu {
            Button("Expand") { coordinator.isCompact = false }
            if n > 0 {
                let t = items[front % n]
                if t.binding != nil { Button("Jump to Bound Page") { coordinator.jump(t) } }
                Button("Mark as Done") { store.toggleDone(t.id) }
            }
            Divider()
            Button("Quit Hoopa") { coordinator.onQuit?() }
        }
    }

    /// Wait a little before expanding on enter (a mouse merely passing over does not expand) and before folding on exit (brushing the edge does not flicker).
    /// The system may report "entered" again when the window grows; the same state is not handled twice.
    private func hover(_ inside: Bool) {
        guard inside != hovering else { return }
        hovering = inside
        hoverWork?.cancel()
        guard !store.byUrgency.isEmpty else { return }
        let work = DispatchWorkItem { [coordinator] in coordinator.hoverCompact(inside) }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.08 : 0.3), execute: work)
    }

    // MARK: Card stack

    private func stack(_ items: [TodoItem]) -> some View {
        let n = items.count
        let behind = stage == .stack ? min(maxBehind, n - 1) : 0
        // Each card keeps its identity by to-do id and only changes its depth in the stack; position / scale / opacity spring-animate together on a switch.
        // Deeper cards first, the front card last (later ZStack children draw on top): no zIndex reordering, so the front card is not rebuilt and jerks when the cards behind appear.
        let depthOf = { (idx: Int) in (idx - front % n + n) % n }
        let ordered = Array(items.enumerated()).filter { depthOf($0.offset) <= behind }.sorted { depthOf($0.offset) > depthOf($1.offset) }
        // The strip of the cards behind uses ReserveBottom for room, not padding: SwiftUI animates a padding change as "scale about the centre" and the front card would move up and down.
        return ReserveBottom(extra: CGFloat(behind) * peek) {
          ZStack(alignment: .topLeading) {
            ForEach(ordered, id: \.element.id) { idx, item in
                let depth = depthOf(idx)
                    card(item, isFront: depth == 0, count: n)
                        .scaleEffect(1 - CGFloat(depth) * 0.04, anchor: .top)
                        .offset(y: CGFloat(depth) * peek)
                        .opacity(1 - Double(depth) * 0.25)
                        .onTapGesture { if depth > 0 { front = idx } }
                        .help(depth > 0 ? "Bring to front" : "")
                        // Appear from behind the front card / fold back behind it.
                        .transition(.opacity.combined(with: .offset(y: -CGFloat(depth) * peek)))
            }
          }
        }
        // The overall size of each collapsed stage (pill / card / stack): reported to the window, which grows to the end size as soon as the morph starts.
        .transformPreference(CompactSizesKey.self) { sizes in
            if let card = sizes.card {
                sizes.stack = CGSize(width: card.width, height: card.height + CGFloat(min(maxBehind, n - 1)) * peek)
            }
        }
        // The scroll wheel switches the front card (only once expanded into the card stack).
        .background(ScrollWheelCatcher { dy in
            guard stage == .stack else { return }
            scrollAccum += dy
            if abs(scrollAccum) >= 24 {
                front = (front + (scrollAccum > 0 ? 1 : n - 1)) % n
                scrollAccum = 0
            }
        })
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: front)
    }

    /// One card: the pill and card layouts stacked, sized by the current one; the other is transparent and clipped to the outline.
    /// On a switch the outline (size, corner radius) morphs continuously and the two contents cross-fade.
    private func card(_ t: TodoItem, isFront: Bool, count: Int) -> some View {
        let pill = isFront && stage == .pill
        let shape = RoundedRectangle(cornerRadius: pill ? pillRadius : 12, style: .continuous)
        return MorphLayout(progress: pill ? 0 : 1, maxWidth: Self.cardWidth) {
            pillContent(t, count: count)
                .opacity(pill ? 1 : 0)
                .allowsHitTesting(pill)
                .background(GeometryReader { g in
                    Color.clear.preference(key: CompactSizesKey.self, value: isFront ? CompactSizes(pill: g.size) : CompactSizes())
                })
            cardContent(t, isFront: isFront)
                .opacity(pill ? 0 : 1)
                .allowsHitTesting(!pill)
                .background(GeometryReader { g in
                    Color.clear.preference(key: CompactSizesKey.self, value: isFront ? CompactSizes(card: g.size) : CompactSizes())
                })
        }
        .clipShape(shape)
        .glass(shape)
        .background(GeometryReader { g in
            // The front card reports its rect to RootView: expanding, the panel plate grows out of here.
            Color.clear.preference(key: FrontGeometryKey.self,
                                   value: isFront ? FrontGeometry(rect: g.frame(in: .global), radius: pill ? pillRadius : 12)
                                                  : FrontGeometryKey.defaultValue)
        })
    }

    /// The pill: app icon, content (one line, truncated), countdown, how many more.
    private func pillContent(_ t: TodoItem, count: Int) -> some View {
        let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 6) {
            if let b = t.binding {
                BindingChip(binding: b, jumping: coordinator.jumpingID == t.id, compact: true)
            }
            if !title.isEmpty {
                Text(title).lineLimit(1).truncationMode(.tail)
            }
            if let d = t.due { DueChip(due: d, showDetail: false) }
            if count > 1 {
                Text("+\(count - 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Style.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: pillRadius * 2)
    }

    /// The card: the first row starts with ⌄ expand (at the same spot as the expanded panel's collapse button, see CompactToggle), then the binding chip (jump) and the time chip;
    /// the second row is like Reminders: the done box right next to the content, in the same column as ⌄. An empty content still keeps one line.
    private func cardContent(_ t: TodoItem, isFront: Bool) -> some View {
        let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                // Only the front card is clickable; the cards behind keep the slot too, so the layout does not jump when one comes to the front.
                CompactToggle(collapse: false)
                    .opacity(isFront ? 1 : 0)
                    .allowsHitTesting(isFront)
                if let b = t.binding {
                    Button { coordinator.jump(t) } label: {
                        BindingChip(binding: b, jumping: coordinator.jumpingID == t.id)
                    }
                    .buttonStyle(.plain)
                    .help("Back to \(b.shortDescription)")
                }
                if let d = t.due { DueChip(due: d, showDetail: false) }
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button { store.toggleDone(t.id) } label: {
                    // As wide as ⌄, so the two buttons line up vertically.
                    Image(systemName: "circle").font(.system(size: 16)).foregroundStyle(Style.secondary).frame(width: 16)
                }
                .buttonStyle(.plain)
                .help("Mark as done")
                Text(title.isEmpty ? " " : title).font(.system(size: 13)).lineLimit(2).truncationMode(.tail)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.isCompact = false }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: Self.cardWidth)
    }

    /// No to-dos: a + sign, click to open the panel and add one.
    private var addButton: some View {
        Button { coordinator.isCompact = false } label: {
            Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help("Add a to-do")
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glass(Capsule())
        .background(GeometryReader { g in
            Color.clear
                .preference(key: FrontGeometryKey.self,
                            value: FrontGeometry(rect: g.frame(in: .global), radius: g.size.height / 2))
                .preference(key: CompactSizesKey.self, value: CompactSizes(pill: g.size, card: g.size, stack: g.size))
        })
    }
}

/// Reserves extra height under the child (animatable): every frame lays out with the interpolated extra, the child stays glued to the top left.
struct ReserveBottom: Layout {
    var extra: CGFloat
    var animatableData: CGFloat {
        get { extra }
        set { extra = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let s = subviews.first else { return .zero }
        let size = s.sizeThatFits(proposal)
        return CGSize(width: size.width, height: size.height + max(extra, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let s = subviews.first else { return }
        s.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
    }
}

/// The overall size of each collapsed stage: pill / single card / card stack.
struct CompactSizes: Equatable {
    var pill: CGSize? = nil
    var card: CGSize? = nil
    var stack: CGSize? = nil

    func size(for stage: CompactStage) -> CGSize? {
        switch stage {
        case .pill: return pill
        case .card: return card
        case .stack: return stack ?? card
        }
    }
}

struct CompactSizesKey: PreferenceKey {
    static let defaultValue = CompactSizes()
    /// The pill and card sizes come from different children and are merged.
    static func reduce(value: inout CompactSizes, nextValue: () -> CompactSizes) {
        let next = nextValue()
        value.pill = next.pill ?? value.pill
        value.card = next.card ?? value.card
        value.stack = next.stack ?? value.stack
    }
}

/// Two children (pill layout, card layout) stacked at the top left, each at its own size; the container size interpolates between them by progress (0 pill, 1 card).
/// progress is animatable: SwiftUI lays out every frame with the interpolated progress, so the container grows / shrinks glued to the top left.
/// (Merely switching "which child sets the size" makes SwiftUI treat the size change as a geometry animation, a scale about the end centre, and the pill would first jump to the card's centre and grow from there.)
/// A child that is too wide is re-laid out at maxWidth (text truncated).
struct MorphLayout: Layout {
    var progress: CGFloat
    var maxWidth: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private func fit(_ s: LayoutSubview) -> CGSize {
        let ideal = s.sizeThatFits(.unspecified)
        return ideal.width <= maxWidth ? ideal : s.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return subviews.first.map(fit) ?? .zero }
        let a = fit(subviews[0]), b = fit(subviews[1])
        let t = min(max(progress, 0), 1)
        return CGSize(width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for s in subviews {
            s.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(fit(s)))
        }
    }
}

/// Captures the scroll wheel events landing on this window (SwiftUI has no scroll wheel gesture).
struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.attach(to: v)
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onScroll = onScroll }
    func makeCoordinator() -> Coordinator { Coordinator(onScroll: onScroll) }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.detach() }

    final class Coordinator {
        var onScroll: (CGFloat) -> Void
        private var monitor: Any?
        private weak var view: NSView?
        init(onScroll: @escaping (CGFloat) -> Void) { self.onScroll = onScroll }

        func attach(to v: NSView) {
            view = v
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let self, let w = self.view?.window, e.window === w else { return e }
                self.onScroll(e.scrollingDeltaY)
                return e
            }
        }
        func detach() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
        }
    }
}
