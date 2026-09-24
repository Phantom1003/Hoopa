import SwiftUI

/// Collapse ↔ expand: the panel's glass is a separate "plate". Expanding, it grows from the front card's (or the pill's) rect to the whole panel
/// while the card content fades out, and the panel content appears once it has grown; collapsing reverses it: the panel content fades out first, the plate shrinks back to the card's rect, the card appears and the plate gives way to the card's own glass.
/// The cards stacked behind do not move; they only fade in and out.
/// The window grows first and shrinks once the animation is over (see FirstMouseHostingView.fitWindow); the content stays glued to the top left.
struct RootView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    /// The rect and corner radius of the collapsed front card (or the pill), reported by CompactView: the plate grows out of here / shrinks back here.
    @State private var front = FrontGeometry(rect: CGRect(x: 0, y: 0, width: CompactView.cardWidth, height: 80), radius: 12)
    /// Collapsed, the panel content moves off-window but stays alive: expanding does not rebuild the composer and the list (a rebuild stalls 100ms and the animation skips its start).
    @State private var parked: Bool

    init(startCompact: Bool) { _parked = State(initialValue: startCompact) }

    /// When the plate's rect animates: at the moment of expanding / collapsing, and when the collapsed front card's rect changes; while expanded, the window being dragged larger or smaller is followed directly, not animated.
    private struct PlateKey: Equatable { var expanded: Bool; var front: FrontGeometry? }

    var body: some View {
        // The panel size comes from the window (coordinator.panelSize), not GeometryReader: that reports the root view's ideal size as 10×10 and the collapsed window would shrink to nothing.
        let expanded = !coordinator.isCompact
        let plate = expanded ? FrontGeometry(rect: CGRect(origin: .zero, size: coordinator.panelSize), radius: 18) : front
        ZStack(alignment: .topLeading) {
                Color.clear
                    .glass(RoundedRectangle(cornerRadius: plate.radius, style: .continuous))
                    .frame(width: plate.rect.width, height: plate.rect.height)
                    .offset(x: plate.rect.minX, y: plate.rect.minY)
                    .animation(expanded ? Motion.panelGrow : Motion.panelShrink,
                               value: PlateKey(expanded: expanded, front: expanded ? nil : front))
                    .opacity(expanded ? 1 : 0)
                    .animation(expanded ? Motion.plateIn : Motion.plateOut, value: expanded)
                    .allowsHitTesting(false)
                if coordinator.isCompact {
                    CompactView()
                        .zIndex(1)
                        .transition(.asymmetric(insertion: .opacity.animation(Motion.compactIn),
                                                removal: .opacity.animation(Motion.compactOut)))
                }
                // The panel content is laid out at its final size (not re-laid out as the plate grows); its layout placeholder matches the plate and animates with it
                // (the ZStack's size never jumps; a jump would be treated by SwiftUI as a geometry animation about the centre and drag the plate off),
                // then it is clipped to the plate: expanding, the content is uncovered by the growing glass; collapsing, it is covered again, and the panel is never empty.
                // clipShape also applies to the AppKit-hosted list / text fields (clipped to the rect).
                ExpandedView()
                    .frame(width: coordinator.panelSize.width, height: coordinator.panelSize.height, alignment: .topLeading)
                    .frame(width: plate.rect.width, height: plate.rect.height, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: plate.radius, style: .continuous))
                    .animation(expanded ? Motion.panelGrow : Motion.panelShrink,
                               value: PlateKey(expanded: expanded, front: expanded ? nil : front))
                    .offset(x: parked ? -4000 : 0)
                    .animation(nil, value: parked)        // moving in and out is not animated
                    .opacity(expanded ? 1 : 0)
                    .allowsHitTesting(expanded)
                    .animation(expanded ? Motion.panelContentIn : Motion.panelContentOut, value: expanded)
                    .zIndex(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onPreferenceChange(FrontGeometryKey.self) { f in if f.rect.width > 1 { front = f } }
        .onPreferenceChange(CompactSizesKey.self) { coordinator.compactSizes = $0 }
        .onChange(of: coordinator.isCompact) { _, compact in
            if compact {
                // Move away only after the panel content has faded out and the plate has shrunk back.
                DispatchQueue.main.asyncAfter(deadline: .now() + Motion.parkAfter) { if coordinator.isCompact { parked = true } }
            } else {
                parked = false
            }
        }
        .animation(Motion.panelShrink, value: coordinator.isCompact)
        .animation(Motion.step, value: coordinator.stage)
    }
}

/// The rect (window coordinates) and corner radius of the collapsed front card (or the pill).
struct FrontGeometry: Equatable {
    var rect: CGRect
    var radius: CGFloat
}

struct FrontGeometryKey: PreferenceKey {
    static let defaultValue = FrontGeometry(rect: .zero, radius: 12)
    /// Only the front card reports a non-empty rect; the rest are ignored.
    static func reduce(value: inout FrontGeometry, nextValue: () -> FrontGeometry) {
        let next = nextValue()
        if next.rect.width > 0 { value = next }
    }
}

/// Expanded: the input pill + the list of sticky-note cards.
struct ExpandedView: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var permissions: PermissionState
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showDone = false
    /// Sort by time (remembered). Only the display order: switched off, the list returns to its own order.
    @AppStorage("sortByTime") private var sortByTime = false
    private static let reorder = Animation.smooth(duration: 0.3)

    var body: some View {
        VStack(spacing: 0) {
            header
            if !permissions.accessibility { permissionBanner }
            InputPill().padding(.horizontal, 12)
            list
        }
        .frame(minWidth: 300, minHeight: 320)
        // The NSScrollView under the list is square and would show sharp corners outside the rounding: clip it round. The glass is a separate layer in RootView.
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .windowDraggable()
        .overlay(alignment: .bottom) { toast }
    }

    private var header: some View {
        HStack(spacing: 8) {
            CompactToggle(collapse: true)
            Text("Hoopa").font(.system(size: 13, weight: .semibold)).foregroundStyle(Style.text)
            Spacer()
            if !store.active.isEmpty {
                Text("\(store.active.count) items").font(.caption).foregroundStyle(Style.secondary)
            }
            sortButton
            Menu {
                Toggle("Keep Panel on Top", isOn: Binding(
                    get: { coordinator.alwaysOnTop },
                    set: { coordinator.alwaysOnTop = $0; coordinator.onAlwaysOnTopChanged?($0) }))
                Toggle("Show Completed", isOn: $showDone)
                // Switching the language relaunches the app. Language names are not translated.
                Picker("Language", selection: Binding(get: { AppLanguage.current }, set: { AppLanguage.switchTo($0) })) {
                    ForEach(AppLanguage.allCases) { Text(verbatim: $0.name).tag($0) }
                }
                Divider()
                Button(permissions.accessibility ? "Accessibility Access: Granted" : "Grant Accessibility Access…") { permissions.request() }
                    .disabled(permissions.accessibility)
                Button("Clear Completed") { store.clearDone() }.disabled(store.done.isEmpty)
                Divider()
                Text("Press ⌃⌥T to show / hide the panel")
                Button("Quit Hoopa") { coordinator.onQuit?() }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(Style.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        // The left and top insets match the collapsed card: the collapse button lands exactly where the card's expand button is (see CompactToggle).
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .windowDraggable()
    }

    /// The sort-by-time toggle: timed to-dos first, soonest first (overdue at the very top), untimed ones after them in their own order;
    /// while it is on, new to-dos and changed times fall into place. A round icon the size of ⋯, filled with the accent colour while on; the same size in both states, so it does not shift after a click.
    private var sortButton: some View {
        Button { sortByTime.toggle() } label: {
            Image(systemName: sortByTime ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                .foregroundStyle(sortByTime ? Style.accent : Style.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sortByTime ? "Sorted by time · click for manual order" : "Sort by time (soonest first)")
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Accessibility access is needed to detect windows and jump back").font(.caption).foregroundStyle(Style.text)
            Spacer()
            Button("Grant") { permissions.request() }.controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.18)))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var list: some View {
        let items = sortByTime ? store.byUrgency : store.active
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if items.isEmpty && (!showDone || store.done.isEmpty) {
                        emptyState
                    }
                    ForEach(items) { todo in
                        TodoCard(todo: todo)
                            .reorderable(todo.id) { dragged, after in move(dragged, relativeTo: todo.id, after: after) }
                    }
                    if showDone && !store.done.isEmpty {
                        HStack {
                            Text("Completed · \(store.done.count)").font(.caption).foregroundStyle(Style.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        ForEach(store.done) { todo in
                            TodoCard(todo: todo)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                // While sorted by time (including the click on the toggle itself) every order change animates, so it is visible where a card went; manual order stays as it is.
                .animation(Self.reorder, value: sortByTime ? items.map(\.id) : nil)
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            // A new to-do sorted by time may land out of view: scroll just enough to show it (no movement when it is already visible).
            .onChange(of: store.todos.map(\.id)) { old, new in
                guard let added = new.first(where: { !old.contains($0) }) else { return }
                DispatchQueue.main.async { withAnimation(Self.reorder) { proxy.scrollTo(added) } }
            }
        }
    }

    /// Drag to reorder. Dragging out of time order while sorted by time switches back to manual order as dragged, with a toast.
    private func move(_ dragged: UUID, relativeTo target: UUID, after: Bool) {
        guard sortByTime else { store.move(dragged, relativeTo: target, after: after); return }
        if !store.moveByUrgency(dragged, relativeTo: target, after: after) {
            sortByTime = false
            coordinator.showToast(String(localized: "Sort by time turned off to keep your order"))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "scope").font(.system(size: 28)).foregroundStyle(Style.secondary)
            Text("No to-dos yet").font(.subheadline).foregroundStyle(Style.secondary)
            Text("Pick a window / page with ⌖ and set a timer or date with ◔, then type and press ⌘Return.\nLater, click the chip to jump straight back to that page.")
                .font(.caption).foregroundStyle(Style.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var toast: some View {
        if let t = coordinator.toast {
            Text(t)
                .font(.caption)
                .foregroundStyle(Style.text)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(.ultraThickMaterial))
                .shadow(radius: 4)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: coordinator.toast)
        }
    }
}

/// The collapse / expand button: "collapse" (arrow up) is leftmost in the expanded panel's title bar, "expand" (arrow down) leftmost in the collapsed card's first row.
/// The window's top left corner does not move when switching, both sit at the top left with the same insets, so they land on the same spot: after a click the same button is still under the mouse, repeated clicks only toggle,
/// never hitting the done box or another button. As tall as a chip (25), so its row is the same height in both shapes and the button sits at the same vertical position.
struct CompactToggle: View {
    let collapse: Bool
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        Button { coordinator.isCompact = collapse } label: {
            Image(systemName: collapse ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
                .foregroundStyle(Style.secondary).frame(width: 16, height: 25).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapse ? "Collapse" : "Expand")
    }
}

/// Drag to reorder: dropping on the upper half of another card inserts before it, on the lower half after it (onMove(the dragged card, whether to insert after)).
private struct Reorderable: ViewModifier {
    let id: UUID
    let onMove: (UUID, Bool) -> Void
    @State private var height: CGFloat = 60
    @State private var targeted = false
    @State private var insertAfter = false

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in Color.clear.onAppear { height = g.size.height }
                .onChange(of: g.size.height) { _, h in height = h } })
            .overlay(alignment: insertAfter ? .bottom : .top) {
                if targeted {
                    Capsule().fill(Style.accent).frame(height: 2).padding(.horizontal, 6)
                }
            }
            .draggable(id.uuidString)
            .dropDestination(for: String.self) { items, location in
                guard let s = items.first, let dragged = UUID(uuidString: s), dragged != id else { return false }
                onMove(dragged, location.y > height / 2)
                return true
            } isTargeted: { targeted = $0 }
            .onContinuousHover { phase in
                if case .active(let p) = phase, targeted { insertAfter = p.y > height / 2 }
            }
    }
}

extension View {
    func reorderable(_ id: UUID, onMove: @escaping (UUID, Bool) -> Void) -> some View { modifier(Reorderable(id: id, onMove: onMove)) }
}
