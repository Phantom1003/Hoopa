import SwiftUI

/// The second collapsed style: a card stack. The most urgent to-do is in front, the cards behind show a sliver at the bottom;
/// the scroll wheel or a click on a card behind brings it to the front. The cards share the expanded to-do card's format: first row the done box, the binding chip (jump),
/// the time chip and ⌄ expand at the top right; second row the content, one line even when empty.
struct CompactStack: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var front = 0
    @State private var scrollAccum: CGFloat = 0
    private let width: CGFloat = 276      // as wide as a to-do card in the narrowest expanded panel (300)
    private let peek: CGFloat = 9
    private let maxBehind = 2

    var body: some View {
        let items = store.byUrgency
        let n = items.count
        Group {
            if n == 0 {
                Button { coordinator.isCompact = false } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glass(Capsule())
            } else {
                let behind = min(maxBehind, n - 1)
                // Each card keeps its identity by to-do id and only changes its depth in the stack; position / scale / opacity spring-animate together on a switch.
                ZStack(alignment: .top) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        let depth = (idx - front % n + n) % n
                        let shown = depth <= behind
                        card(item, isFront: depth == 0)
                            .scaleEffect(1 - CGFloat(min(depth, maxBehind + 1)) * 0.04, anchor: .top)
                            .offset(y: CGFloat(min(depth, maxBehind + 1)) * peek)
                            .opacity(shown ? 1 - Double(depth) * 0.25 : 0)
                            .zIndex(Double(n - depth))
                            .allowsHitTesting(shown)
                            .onTapGesture { if depth > 0 { front = idx } }
                            .help(depth > 0 ? "Bring to Front" : "")
                    }
                }
                .padding(.bottom, CGFloat(behind) * peek)
                // The scroll wheel switches the front card.
                .background(ScrollWheelCatcher { dy in
                    scrollAccum += dy
                    if abs(scrollAccum) >= 24 {
                        front = (front + (scrollAccum > 0 ? 1 : n - 1)) % n
                        scrollAccum = 0
                    }
                })
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: front)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Style.text)
        .fixedSize()
        .windowDraggable()
        .onChange(of: n) { _, count in if count > 0 { front %= count } else { front = 0 } }
        .contextMenu {
            Button("Expand") { coordinator.isCompact = false }
            Picker("Collapsed Style", selection: $coordinator.compactStyle) {
                ForEach(CompactStyle.allCases) { Text($0.label).tag($0) }
            }
            Divider()
            Button("Quit Hoopa") { coordinator.onQuit?() }
        }
    }

    private func card(_ t: TodoItem, isFront: Bool) -> some View {
        let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { store.toggleDone(t.id) } label: {
                    Image(systemName: "circle").font(.system(size: 16)).foregroundStyle(Style.secondary)
                }
                .buttonStyle(.plain)
                .help("Mark as Done")
                if let b = t.binding {
                    Button { coordinator.jump(t) } label: {
                        BindingChip(binding: b, jumping: coordinator.jumpingID == t.id)
                    }
                    .buttonStyle(.plain)
                    .help("Return to \(b.shortDescription)")
                }
                if let d = t.due { DueChip(due: d, showDetail: false) }
                Spacer(minLength: 0)
                if isFront {
                    Button { coordinator.isCompact = false } label: {
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Style.secondary).frame(width: 16, height: 18).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Expand")
                }
            }
            // The insets match the composer inside the expanded card, so the text lines up.
            Text(title.isEmpty ? " " : title).font(.system(size: 13)).lineLimit(2).truncationMode(.tail)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { coordinator.isCompact = false }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: width)
        .glass(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
