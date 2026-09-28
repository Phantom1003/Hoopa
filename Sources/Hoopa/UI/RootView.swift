import SwiftUI

/// Collapse ↔ expand: the whole window has a single glass "plate". Expanding, it grows from the collapsed slab's rect to the whole panel
/// while the slab's content fades out, and the panel content appears once it has grown; collapsing reverses it: the panel content fades out first, the plate shrinks back to the slab's rect, the slab's content appears.
/// The collapsed list draws no glass of its own: with two pieces of glass stacked, each one's shadow shows through the other. The plate spans the ear's column on the left,
/// and the ear is cut out of its left side by the window's layer mask (see FirstMouseHostingView), so ear and panel are one piece of glass from the start;
/// Liquid Glass only understands standard shapes (it does not redraw custom shapes while they animate, and two pieces do not merge), so the shape is always a rounded rectangle.
/// The plate's left corners are cut by the mask too (the glass itself extends under the ear's column), so the plate's rect every frame and how far the ear is out are reported to the window from here,
/// and the mask follows the plate frame by frame: if the mask clipped to the window size, the plate's bottom left corner would land on the mask's straight edge while it shrinks / grows and turn square.
/// The ear is out only while the mouse is on the window and slides back to the edge when it leaves. The window grows first and shrinks once the animation is over (see FirstMouseHostingView.fitWindow); the content stays glued to the top left.
struct RootView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    /// The collapsed slab's rect (root view coordinates) and corner radius, reported by CompactView: the plate grows out of here / shrinks back here.
    @State private var front = FrontGeometry(rect: CGRect(x: Ear.width, y: 0, width: 260, height: 130), radius: CompactView.radius)
    /// Collapsed, the panel content moves off-window but stays alive: expanding does not rebuild the composer and the list (a rebuild stalls 100ms and the animation skips its start).
    @State private var parked: Bool
    /// The ear is out (the mouse is on the window); it slides back a little after the mouse leaves, so brushing the edge does not flicker.
    @State private var earShown = false
    @State private var earWork: DispatchWorkItem?

    init(startCompact: Bool) { _parked = State(initialValue: startCompact) }

    /// When the plate's rect animates: at the moment of expanding / collapsing, when the collapsed slab's rect changes, and when the plate's right corners square off / round again (docking at the right edge);
    /// while expanded, the window being dragged larger or smaller is followed directly, not animated.
    private struct PlateKey: Equatable { var expanded: Bool; var front: FrontGeometry?; var flush: CGFloat }

    var body: some View {
        // The panel size comes from the window (coordinator.panelSize), not GeometryReader: that reports the root view's ideal size as 10×10 and the collapsed window would shrink to nothing.
        // Leave the ear's width on the left of the window: the panel and the collapsed slab both start right of the ear.
        let expanded = !coordinator.isCompact
        let panelRect = CGRect(x: Ear.width, y: 0, width: coordinator.panelSize.width - Ear.width, height: coordinator.panelSize.height)
        let plate = expanded ? FrontGeometry(rect: panelRect, radius: 18) : front
        // Docked at the right edge of the screen: the plate runs one corner radius past the window's right edge (the window clips it), so the corners against the screen edge are square.
        // Only the glass and the content's clip run on, not the layout: the collapsed window is sized to the content and must not grow by that much.
        let flush: CGFloat = coordinator.flushRight ? plate.radius : 0
        let plateKey = PlateKey(expanded: expanded, front: expanded ? nil : front, flush: flush)
        ZStack(alignment: .topLeading) {
                // The plate: one rounded-rectangle piece of glass spanning the ear's column on the left (the rect starts at the window's left edge, the ear is cut out by the mask). Present in both shapes; collapsed, it is the slab itself.
                // Position and size are set by PlateFrame, which reports the mid-animation rect to the window's mask every frame.
                Color.clear
                    .glass(RoundedRectangle(cornerRadius: plate.radius, style: .continuous))
                    .modifier(PlateFrame(rect: CGRect(x: plate.rect.minX - Ear.width, y: plate.rect.minY,
                                                      width: plate.rect.width + Ear.width + flush, height: plate.rect.height),
                                         overflow: flush,
                                         report: { coordinator.plateFrame = $0 }))
                    .animation(expanded ? Motion.panelGrow : Motion.panelShrink, value: plateKey)
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
                    .frame(width: panelRect.width, height: panelRect.height, alignment: .topLeading)
                    .frame(width: plate.rect.width + flush, height: plate.rect.height, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: plate.radius, style: .continuous))
                    .frame(width: plate.rect.width, height: plate.rect.height, alignment: .topLeading)   // the clip's overflow past the right edge takes no layout room
                    .offset(x: plate.rect.minX, y: plate.rect.minY)
                    .animation(expanded ? Motion.panelGrow : Motion.panelShrink, value: plateKey)
                    .offset(x: parked ? -4000 : 0)
                    .animation(nil, value: parked)        // moving in and out is not animated
                    .opacity(expanded ? 1 : 0)
                    .allowsHitTesting(expanded)
                    .animation(expanded ? Motion.panelContentIn : Motion.panelContentOut, value: expanded)
                    .zIndex(2)
                // The arrow on the ear: at the same spot in both shapes.
                EarToggle(shown: earShown)
                    .offset(y: Ear.top)
                    .zIndex(3)
                // How far the ear is out (the value on every animation frame) is reported to the window's mask: an invisible probe that takes no events, its width is how far the ear is out.
                Color.clear
                    .modifier(EarProbe(extent: earShown ? Ear.width + Ear.radius : 0.5, report: { coordinator.earExtent = $0 }))
                    .animation(Motion.ear, value: earShown)
                    .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(name: "root")     // the slab's rect is reported in this space and the plate is placed by it
        .onHover(perform: hover)
        .onPreferenceChange(FrontGeometryKey.self) { f in if f.rect.width > 1 { front = f } }
        .onChange(of: coordinator.isCompact) { _, compact in
            if compact {
                // Move away only after the panel content has faded out and the plate has shrunk back.
                DispatchQueue.main.asyncAfter(deadline: .now() + Motion.parkAfter) { if coordinator.isCompact { parked = true } }
            } else {
                parked = false
            }
        }
        .animation(Motion.panelShrink, value: coordinator.isCompact)
    }

    /// The ear slides out as soon as the mouse arrives and back 0.5 s after it leaves. The ear itself is cut out by the window mask (its width reported frame by frame by the probe above); only the arrow lives here.
    private func hover(_ inside: Bool) {
        earWork?.cancel()
        let work = DispatchWorkItem {
            guard earShown != inside else { return }
            earShown = inside
        }
        earWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0 : 0.5), execute: work)
    }
}

/// Mid-animation values have to reach the window's mask every frame. SwiftUI animations interpolate in the presentation layer; GeometryReader / onChange in the layout only see the end values.
/// Only an Animatable modifier's animatableData is interpolated per frame, and body is re-evaluated with that frame's value, provided body affects layout:
/// a modifier whose body returns content unchanged is never evaluated at all. So both modifiers below size themselves from the reported value.

/// How far the ear is out: the probe's width is exactly that, reported every frame.
private struct EarProbe: ViewModifier, Animatable {
    var extent: CGFloat
    var report: (CGFloat) -> Void
    var animatableData: CGFloat {
        get { extent }
        set { extent = newValue }
    }
    func body(content: Content) -> some View {
        report(extent)
        return content.frame(width: extent, height: 1)
    }
}

/// The plate's position and size (root view coordinates), laid out every animation frame at the interpolated rect and reported: the window's mask rounds the corners to this rect, flush with the plate.
/// The last overflow points of the width hang past the layout frame on the right (docked at the right edge, see RootView): the glass is that much wider than the room it takes.
private struct PlateFrame: ViewModifier, Animatable {
    var rect: CGRect
    var overflow: CGFloat
    var report: (CGRect) -> Void
    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(rect.animatableData, overflow) }
        set { rect.animatableData = newValue.first; overflow = newValue.second }
    }
    func body(content: Content) -> some View {
        report(rect)
        return content
            .frame(width: rect.width, height: rect.height)
            .frame(width: rect.width - overflow, height: rect.height, alignment: .leading)
            .offset(x: rect.minX, y: rect.minY)
    }
}

/// The collapsed slab's rect (root view coordinates) and corner radius.
struct FrontGeometry: Equatable {
    var rect: CGRect
    var radius: CGFloat
}

struct FrontGeometryKey: PreferenceKey {
    static let defaultValue = FrontGeometry(rect: .zero, radius: CompactView.radius)
    /// Only the slab reports a non-empty rect.
    static func reduce(value: inout FrontGeometry, nextValue: () -> FrontGeometry) {
        let next = nextValue()
        if next.rect.width > 0 { value = next }
    }
}

/// Expanded: the list of sticky-note cards from the top of the panel, no title bar (a title and an empty row are both wasted space);
/// the count, new, sort, delete all, update (while a newer version exists) and the menu fold into a glass capsule floating at the bottom right; the list leaves its height free at the bottom so the last card can scroll above it.
/// The composer does not occupy the top by default; + brings it up.
struct ExpandedView: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var permissions: PermissionState
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var updater: Updater
    @State private var showDone = false
    /// The confirmation before deleting everything.
    @State private var confirmDeleteAll = false
    /// Sort by time (remembered). Only the display order: switched off, the list returns to its own order.
    @AppStorage("sortByTime") private var sortByTime = false
    private static let reorder = Animation.smooth(duration: 0.3)

    var body: some View {
        VStack(spacing: 0) {
            if !permissions.accessibility { permissionBanner.padding(.top, 10) }
            // The composer is hidden by default and + brings it up; always shown when there are no to-dos at all.
            if coordinator.adding || store.active.isEmpty {
                InputPill().padding(.horizontal, 12).padding(.top, permissions.accessibility ? 10 : 0)
            }
            list
        }
        .frame(minWidth: 300, minHeight: 320)
        // The NSScrollView under the list is square and would show sharp corners outside the rounding: clip it round. The glass is a separate layer in RootView.
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .windowDraggable()
        .overlay(alignment: .bottomTrailing) { controls }
        .overlay(alignment: .bottom) { toast }
    }

    /// The room left at the bottom of the list and under the toast: the control capsule's height plus its distance to the edge.
    private static let controlsInset: CGFloat = 48

    /// The control capsule at the bottom right: count, new, sort, delete all, update (while a newer version exists), menu. Floats over the list (see controlsInset).
    private var controls: some View {
        HStack(spacing: 8) {
            if !store.active.isEmpty {
                Text("\(store.active.count) items").font(.caption).foregroundStyle(Style.secondary)
            }
            addButton
            sortButton
            deleteAllButton
            updateButton
            menuButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glass(Capsule())
        .padding(12)
    }

    /// Delete all: every to-do, completed ones included, after a confirmation.
    private var deleteAllButton: some View {
        Button { confirmDeleteAll = true } label: {
            Image(systemName: "trash.circle")
                .foregroundStyle(Style.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.todos.isEmpty)
        .help("Delete all to-dos")
        .confirmationDialog("Delete all to-dos?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                coordinator.selectedID = nil
                store.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every to-do, including completed ones, will be removed. This can't be undone.")
        }
    }

    private var menuButton: some View {
            Menu {
                Toggle("Keep Panel on Top", isOn: Binding(
                    get: { coordinator.alwaysOnTop },
                    set: { coordinator.alwaysOnTop = $0; coordinator.onAlwaysOnTopChanged?($0) }))
                Toggle("Show Completed", isOn: $showDone)
                // Switching the language relaunches the app. Language names are not translated.
                Picker("Language", selection: Binding(get: { AppLanguage.current }, set: { AppLanguage.switchTo($0) })) {
                    ForEach(AppLanguage.allCases) { Text(verbatim: $0.name).tag($0) }
                }
                syncMenu
                Divider()
                Button(permissions.accessibility ? "Accessibility Access: Granted" : "Grant Accessibility Access…") { permissions.request() }
                    .disabled(permissions.accessibility)
                Button("Clear Completed") { store.clearDone() }.disabled(store.done.isEmpty)
                Divider()
                // Version and update (see Updater): the outcome of a manual check and download / install failures go through the toast at the bottom.
                Text("Version \(Updater.version)")
                Toggle("Check for Updates Automatically", isOn: $updater.automatic)
                updateMenuItem
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

    /// Sync ▸ in the ⋯ menu: off, iCloud Drive or a folder of your choice (one Dropbox, Syncthing or the like keeps in step); the one in use is ticked.
    /// Ticking iCloud Drive off, or Off, stops the mirror; the folder item opens the chooser every time, so the folder can be changed. See SyncFolder.
    private var syncMenu: some View {
        Menu("Sync") {
            Toggle("Off", isOn: Binding(get: { store.syncMode == .off }, set: { if $0 { store.setSync(.off) } }))
            Toggle("iCloud Drive", isOn: Binding(get: { store.syncMode == .iCloudDrive }, set: { store.setSync($0 ? .iCloudDrive : .off) }))
            Toggle("Other Folder…", isOn: Binding(get: { if case .folder = store.syncMode { return true } else { return false } }, set: { _ in chooseSyncFolder() }))
            if let folder = store.syncMode.folder {
                Divider()
                Button("Show Sync Folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
            }
        }
    }

    /// The folder chooser for Sync ▸ Other Folder…: the panel is non-activating, so the app is activated for the dialog.
    private func chooseSyncFolder() {
        let dialog = NSOpenPanel()
        dialog.canChooseDirectories = true
        dialog.canChooseFiles = false
        dialog.canCreateDirectories = true
        dialog.prompt = String(localized: "Sync Here")
        dialog.message = String(localized: "Choose a folder your Macs share (iCloud Drive, Dropbox, Syncthing, …). Hoopa keeps todos.json in it.")
        if case .folder(let current) = store.syncMode { dialog.directoryURL = current }
        NSApp.activate(ignoringOtherApps: true)
        if dialog.runModal() == .OK, let url = dialog.url { store.setSync(SyncMode.forFolder(url)) }
    }

    /// The update item in the ⋯ menu: normally "Check for Updates…", "Update to X and Relaunch" once a newer version exists, and only what it is doing while busy.
    @ViewBuilder
    private var updateMenuItem: some View {
        switch updater.state {
        case .available(let r):
            Button("Update to \(r.version) and Relaunch") { updater.install() }
        case .checking:
            Text("Checking for updates…")
        case .downloading(let r, _):
            Text("Downloading \(r.version)…")
        case .installing(let r):
            Text("Installing \(r.version)…")
        default:
            Button("Check for Updates…") { updater.check(manual: true) }
        }
    }

    /// The accent ⬇ added to the capsule while a newer version exists (a menu, like ⋯): which version, install it, read the notes.
    /// A small spinner while downloading / installing; nothing at all the rest of the time, the capsule stays as it is.
    @ViewBuilder
    private var updateButton: some View {
        switch updater.state {
        case .available(let r):
            Menu {
                Text("Version \(r.version) is available")
                Button("Update to \(r.version) and Relaunch") { updater.install() }
                Button("Release Notes…") { NSWorkspace.shared.open(r.page) }
            } label: {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Style.accent)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Version \(r.version) is available")
            .accessibilityLabel("Update available")
        case .downloading(let r, let fraction):
            ProgressView(value: fraction).progressViewStyle(.circular).controlSize(.small)
                .help("Downloading \(r.version)…")
        case .installing(let r):
            ProgressView().controlSize(.small)
                .help("Installing \(r.version)…")
        default:
            EmptyView()
        }
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

    /// New: shows / hides the composer at the top of the list.
    private var addButton: some View {
        Button { coordinator.adding.toggle() } label: {
            Image(systemName: coordinator.adding ? "plus.circle.fill" : "plus.circle")
                .foregroundStyle(coordinator.adding ? Style.accent : Style.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add a to-do")
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
        ScrollViewReader { proxy in
            ScrollView {
                // Grouped by day while sorted by time; the groups move with the clock (a to-do due today moves into "Overdue" once past), recomputed every minute.
                TimelineView(.everyMinute) { ctx in
                    let items = sortByTime ? store.byUrgency : store.active
                    LazyVStack(spacing: 4) {
                        if items.isEmpty && (!showDone || store.done.isEmpty) {
                            emptyState
                        }
                        if sortByTime {
                            ForEach(DayGroup.split(items, now: ctx.date)) { group in
                                header(group.section.title)
                                ForEach(group.items) { todo in card(todo) }
                            }
                        } else {
                            ForEach(items) { todo in card(todo) }
                        }
                        if showDone && !store.done.isEmpty {
                            header("Completed · \(store.done.count)")
                            ForEach(store.done) { todo in
                                TodoCard(todo: todo, selected: coordinator.selectedID == todo.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, Self.controlsInset)
                    // A click on the space between cards: closes the open details.
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.selectedID = nil }
                    // While sorted by time (including the click on the toggle itself) every order change animates, so it is visible where a card went; manual order stays as it is.
                    .animation(Self.reorder, value: sortByTime ? items.map(\.id) : nil)
                }
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            // A new to-do sorted by time may land out of view: scroll just enough to show it (no movement when it is already visible).
            .onChange(of: store.todos.map(\.id)) { old, new in
                guard let added = new.first(where: { !old.contains($0) }) else { return }
                DispatchQueue.main.async { withAnimation(Self.reorder) { proxy.scrollTo(added) } }
            }
            // Opening a to-do's details from the collapsed list: scroll to it.
            .onChange(of: coordinator.selectedID) { _, id in
                guard let id else { return }
                DispatchQueue.main.async { withAnimation(Self.reorder) { proxy.scrollTo(id) } }
            }
        }
    }

    private func card(_ todo: TodoItem) -> some View {
        TodoCard(todo: todo, selected: coordinator.selectedID == todo.id)
            .reorderable(todo.id) { dragged, after in move(dragged, relativeTo: todo.id, after: after) }
    }

    /// The small heading of a group (Overdue / Today / …, Completed).
    private func header(_ title: LocalizedStringKey) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(Style.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
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
            Text("Pick a window / page with ⌖ and set a timer or date with ◔, then type and press Return.\nLater, click the chip to jump straight back to that page.")
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
                .padding(.bottom, Self.controlsInset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: coordinator.toast)
        }
    }
}

/// The groups while sorted by time: Overdue / Today / Tomorrow / Later / No time.
struct DayGroup: Identifiable {
    enum Section: Hashable, CaseIterable {
        case overdue, today, tomorrow, later, unscheduled
        var title: LocalizedStringKey {
            switch self {
            case .overdue: return "Overdue"
            case .today: return "Today"
            case .tomorrow: return "Tomorrow"
            case .later: return "Later"
            case .unscheduled: return "Unscheduled"
            }
        }
    }
    let section: Section
    let items: [TodoItem]
    var id: Section { section }

    /// Groups in the given order; empty groups are left out.
    static func split(_ items: [TodoItem], now: Date) -> [DayGroup] {
        var groups: [Section: [TodoItem]] = [:]
        for t in items {
            let s: Section
            if let d = t.due {
                if TimeFormat.label(d, now: now).overdue {
                    s = .overdue
                } else {
                    let off = TimeFormat.dayOffset(d.date, now: now)
                    s = off <= 0 ? .today : (off == 1 ? .tomorrow : .later)
                }
            } else {
                s = .unscheduled
            }
            groups[s, default: []].append(t)
        }
        return Section.allCases.compactMap { s in groups[s].map { DayGroup(section: s, items: $0) } }
    }
}

/// Where the ear sits: the window leaves this much room on the left, the panel / slab starts right of it. Below the window's corner radius (18): the plate glass in that column is rounded down to 18,
/// straight below that, so the left edge of the ear the mask cuts out is the glass's own edge.
enum Ear {
    static let width: CGFloat = 18
    static let top: CGFloat = 18
    static let height: CGFloat = 26
    static let radius: CGFloat = 8
}

/// The arrow on the collapse / expand ear: the ear is the small tab outside the left edge of the panel (expanded) / slab (collapsed), at exactly the same spot in both shapes:
/// after a click the same ear is still under the mouse, repeated clicks only toggle and never hit the done box or another button. Arrow down means expand, arrow up means collapse.
/// While the ear is folded back the arrow fades out and ignores clicks.
struct EarToggle: View {
    var shown = true
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        Button { coordinator.isCompact.toggle() } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Style.secondary)
                .rotationEffect(.degrees(coordinator.isCompact ? 0 : 180))
                .frame(width: Ear.width, height: Ear.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(coordinator.isCompact ? "Expand" : "Collapse")
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .animation(.easeInOut(duration: 0.2), value: coordinator.isCompact)
        .animation(shown ? Motion.chevronIn : Motion.chevronOut, value: shown)
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
