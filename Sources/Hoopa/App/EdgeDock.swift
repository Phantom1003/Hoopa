import AppKit

/// Docking at a screen edge. Dropping the panel against the left, right or top edge of a screen (or partly beyond it) docks it there: it sits flush with the edge,
/// and slides off the screen a moment after the mouse leaves, leaving a thin strip of glass at the edge; the mouse on that strip slides it back.
/// Each edge is its own side: at the left and right edges the panel slides sideways, at the top it slides up. The top edge is the bottom of the menu bar: docked, the panel hangs from it;
/// tucked, it slides up behind it until only the strip is left under the menu bar, where the mouse can reach it (behind the menu bar it could not), and whatever is behind the menu bar
/// (transparent on macOS 26, it would show the glass through) is cut off by the window mask.
/// Docked at the left edge the UI puts the ear on the right side of the panel, so the window's left edge is the plate's and the strip left on screen is the plate's, not the ear's column.
/// Dragging it away from the edge undocks it, and it is an ordinary floating panel again. The side is remembered across launches.
/// With autoHide off a docked panel stays out, flush with the edge, and never slides away (a setting in the ⋯ menu and the menu bar menu).
/// Tucked away, the strip carries the first timed to-do's countdown (in the list's order) as a bar along the edge (the UI draws it, see RootView's EdgeBar; the tucked state is reported through onTuckChange).
/// Tucking waits while the mouse button is down, a menu or popover is open, or a key was just typed into the panel, so nothing slides away under the user's hands.
/// The window is only ever moved, never resized, here; collapse / expand keep working, and after a resize the panel is snapped to the edge again.
/// Displays connected, disconnected or rearranged, or the window moved by the system, put a docked panel back at its edge, see resettle.
final class EdgeDock {
    enum Side: String { case left, right, top }

    /// How much of the plate stays on screen while tucked.
    static let peek: CGFloat = 8
    /// The window's edge within this distance of the screen edge (or beyond it) docks when the drag ends; dragged further away than this, a docked panel undocks.
    static let snap: CGFloat = 16
    private static let slide: TimeInterval = 0.22
    private static let revealAfter: TimeInterval = 0.2       // the mouse has to rest on the strip, brushing the edge does not reveal
    private static let tuckAfter: TimeInterval = 0.6         // after the mouse leaves
    private static let tuckAfterShow: TimeInterval = 1.5     // after the panel is shown by the app (launch, the hotkey, the end of a pick): a glimpse, then away unless the mouse comes
    private static let typingHold: TimeInterval = 2          // after a keystroke into the panel: typing with the mouse parked elsewhere does not lose the panel mid-word

    private unowned let window: FloatingPanel
    private static let key = "dock"
    private static let autoHideKey = "dockAutoHide"
    /// Whether a docked panel slides off the screen when the mouse leaves (on unless set) or stays out until it is undocked. Switching it off brings a tucked panel out; switching it on tucks it soon.
    var autoHide: Bool {
        get { UserDefaults.standard.object(forKey: Self.autoHideKey) == nil ? true : UserDefaults.standard.bool(forKey: Self.autoHideKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.autoHideKey)
            Log.write("Dock: hide at the edge \(newValue ? "on" : "off")")
            guard side != nil else { return }
            if newValue { scheduleTuck(after: Self.tuckAfter) } else { tuckWork?.cancel(); place(tucked: false, animated: true) }
        }
    }
    private(set) var side: Side? {
        didSet {
            if let side { UserDefaults.standard.set(side.rawValue, forKey: Self.key) } else { UserDefaults.standard.removeObject(forKey: Self.key) }
            onSideChange?(side)
        }
    }
    /// The side changed (the UI squares the plate's corners on the docked side).
    var onSideChange: ((Side?) -> Void)?
    private var lastKey = Date.distantPast
    /// Docked and slid off the screen (only the strip shows). Set at the start of the slide, so the UI's bar on the strip fades in with the slide away and out with the slide back.
    private(set) var isTucked = false {
        didSet { if isTucked != oldValue { onTuckChange?(isTucked) } }
    }
    /// The tucked state changed (the UI shows the countdown bar on the strip while tucked).
    var onTuckChange: ((Bool) -> Void)?
    /// The window is being dragged by the mouse.
    private(set) var dragging = false
    /// The window is being moved by the dock itself (a slide, or a snap): not a drag, and the frame may leave the screen (see FloatingPanel.constrainFrameRect).
    private(set) var placing = false
    /// A resize came while a slide was running: snap again once it is over.
    private var snapAfterPlacing = false
    private var menuTracking = 0
    private var tuckWork: DispatchWorkItem?
    private var revealWork: DispatchWorkItem?
    private var resettleWork: DispatchWorkItem?
    /// The display the panel is docked on, see dockScreen.
    private var display: CGDirectDisplayID?
    /// Kept out by another display beyond the edge (see resettle): tucks once that display is gone.
    private var heldOut = false
    private var observers: [Any] = []

    init(window: FloatingPanel) {
        self.window = window
        side = UserDefaults.standard.string(forKey: Self.key).flatMap(Side.init)
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in self?.noteMove() })
        observers.append(nc.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in self?.noteResize() })
        observers.append(nc.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak self] _ in self?.noteResize() })
        // A menu open anywhere in the app (the ⋯ menu, a context menu): the panel must not slide away under it.
        observers.append(nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in self?.menuTracking += 1 })
        observers.append(nc.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.menuTracking = max(self.menuTracking - 1, 0)
            if self.side != nil, !self.isTucked { self.scheduleTuck(after: Self.tuckAfter) }
        })
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.scheduleResettle() })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    // MARK: Events from the window

    /// The window is about to be shown by the app: a docked panel comes out, and goes away again unless the mouse comes.
    func willShow() {
        guard side != nil else { return }
        place(tucked: false, animated: false)
        scheduleTuck(after: Self.tuckAfterShow)
    }

    /// The mouse entered / left the window's glass.
    func hover(_ inside: Bool) {
        guard side != nil else { return }
        revealWork?.cancel()
        if inside {
            tuckWork?.cancel()
            guard isTucked else { return }
            let work = DispatchWorkItem { [weak self] in self?.place(tucked: false, animated: true) }
            revealWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.revealAfter, execute: work)
        } else if !isTucked {
            scheduleTuck(after: Self.tuckAfter)
        }
    }

    /// A key was typed into the panel.
    func noteKey() { lastKey = Date() }

    /// The panel stopped being the key window (the user went to another app): away soon, unless the mouse is still on it.
    func didResignKey() {
        guard side != nil, !isTucked else { return }
        scheduleTuck(after: 0.3)
    }

    /// Every move of the window. Only moves with the mouse button down are drags; the drag ends when the button comes up, and the position decides.
    /// A move of the dock's own (a slide at the top edge) keeps the mask's cut in step with the frame. Any other move with the button up (the system's, see resettle) puts a docked panel back.
    private func noteMove() {
        if placing { clipToMenuBar(); return }
        guard NSEvent.pressedMouseButtons != 0 else { scheduleResettle(); return }
        tuckWork?.cancel()
        revealWork?.cancel()
        guard !dragging else { return }
        dragging = true
        watchDragEnd()
    }

    private func watchDragEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            if NSEvent.pressedMouseButtons != 0 { self.watchDragEnd(); return }
            self.dragging = false
            self.dragEnded()
        }
    }

    /// Collapsed / expanded, or the expanded panel resized: a docked panel is snapped to the edge again (a collapse at the right edge leaves the slab short of it).
    /// A live resize by the mouse is followed once it ends; a resize during a slide is followed once the slide is over.
    private func noteResize() {
        guard side != nil, !dragging, !window.inLiveResize else { return }
        if placing { snapAfterPlacing = true; return }
        place(tucked: isTucked, animated: true)
    }

    // MARK: Docking

    /// The window was dropped after a drag (also called by the test harness): the position decides. Within the snap distance of several edges (dropped into a corner), the edge pushed further wins.
    func dragEnded() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let f = window.frame, s = screen.frame
        let depth: [(Side, CGFloat)] = [
            (.left, s.minX + Self.snap - f.minX),
            (.right, f.maxX - (s.maxX - Self.snap)),
            (.top, f.maxY - (Self.top(of: screen) - Self.snap)),   // a drag stops at the menu bar (the window server keeps dragged windows below it), so that is the line
        ]
        let next = depth.filter { $0.1 >= 0 && edgeIsFree($0.0, of: screen, window: f) }.max { $0.1 < $1.1 }?.0
        if next != side {
            side = next
            isTucked = false
            Log.write(next.map { "Dock: \($0.rawValue) edge of screen \(NSStringFromRect(s))" } ?? "Undock")
        }
        guard side != nil else { clipToMenuBar(); return }
        display = screen.displayID
        place(tucked: false, animated: true)
        scheduleTuck(after: Self.tuckAfter)
    }

    /// The top docking edge: the bottom of the menu bar (the screen's top edge where the menu bar is hidden, in a full-screen space). The tucked strip sits under it, and the mask cuts above it.
    private static func top(of screen: NSScreen) -> CGFloat { screen.visibleFrame.maxY }

    /// The screen the panel is docked on: the display it docked on while that is connected (a display connected beyond the edge holds most of a tucked window, and window.screen would be that one),
    /// else the one the window is on (where the system moved it when its display went away).
    private var dockScreen: NSScreen? {
        NSScreen.screens.first { display != nil && $0.displayID == display } ?? window.screen ?? NSScreen.main
    }

    /// Nothing beyond that edge: another display there would show the tucked panel instead of hiding it.
    private func edgeIsFree(_ side: Side, of screen: NSScreen, window f: NSRect) -> Bool {
        let s = screen.frame
        let beyond: NSPoint
        switch side {
        case .left: beyond = NSPoint(x: s.minX - 1, y: f.midY)
        case .right: beyond = NSPoint(x: s.maxX + 1, y: f.midY)
        case .top: beyond = NSPoint(x: f.midX, y: s.maxY + 1)
        }
        return !NSScreen.screens.contains { $0 != screen && $0.frame.contains(beyond) }
    }

    /// The window's frame docked at the side, flush with the edge, or tucked with only the strip on screen. The ear's column (transparent, the ear only on hover) is on the window's left,
    /// or on its right when docked at the left edge, so the window's edge against the screen edge is always the plate's, and the column at the other end stays off screen along with the rest.
    /// At the top the plate's top is the window's top: flush under the menu bar, or slid up behind it with the strip at the bottom.
    /// Along the edge the window is kept within the screen (moved to a smaller display, it would hang off its end), and at the left and right edges below the menu bar, as a drag keeps it.
    private func dockedFrame(tucked: Bool, on screen: NSScreen) -> NSRect? {
        guard let side else { return nil }
        var f = window.frame
        let s = screen.frame
        switch side {
        case .left: f.origin.x = tucked ? s.minX + Ear.width + Self.peek - f.width : s.minX
        case .right: f.origin.x = tucked ? s.maxX - Ear.width - Self.peek : s.maxX - f.width
        case .top: f.origin.y = tucked ? Self.top(of: screen) - Self.peek : Self.top(of: screen) - f.height
        }
        if side == .top { f.origin.x = min(max(f.minX, s.minX), s.maxX - f.width) } else { f.origin.y = min(max(f.minY, s.minY), Self.top(of: screen) - f.height) }
        return f
    }

    private func place(tucked: Bool, animated: Bool) {
        guard let screen = dockScreen, let f = dockedFrame(tucked: tucked, on: screen) else { return }
        display = screen.displayID
        isTucked = tucked
        guard f != window.frame else { clipToMenuBar(); return }
        placing = true
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Self.slide
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(f, display: true)
            }, completionHandler: { [weak self] in
                guard let self else { return }
                self.placing = false
                self.clipToMenuBar()
                if self.snapAfterPlacing { self.snapAfterPlacing = false; self.place(tucked: self.isTucked, animated: true) }
            })
        } else {
            window.setFrame(f, display: true)
            placing = false
            clipToMenuBar()
        }
    }

    /// Docked at the top, whatever of the window is above the menu bar's bottom edge (tucked, or on the way) is cut off by the mask, so nothing shows through the transparent menu bar. Nothing is cut at the other sides.
    private func clipToMenuBar() {
        var hidden: CGFloat = 0
        if side == .top, let screen = dockScreen {
            hidden = max(window.frame.maxY - Self.top(of: screen), 0)
        }
        window.setHiddenTop(hidden)
    }

    private func scheduleTuck(after delay: TimeInterval) {
        tuckWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.tryTuck() }
        tuckWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// The displays changed, or the window was moved by someone else than the dock and the mouse: the system moves the windows of a display that went away, and windows it finds off the screens,
    /// onto a screen. Tucked at the top, the panel was moved down onto the screen while the mask still cut away all but the strip, so the strip and its countdown bar hung in the middle of the screen.
    /// A docked panel is put back at its edge, tucked as it was, once the changes have settled (a display change comes as several notifications and moves); with a display now beyond that edge
    /// it comes out and stays out, as tucked it would show on that display.
    private func scheduleResettle() {
        guard side != nil else { return }
        resettleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.resettle() }
        resettleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func resettle() {
        guard let side, let screen = dockScreen, !dragging else { return }
        if placing { snapAfterPlacing = true; return }
        guard let out = dockedFrame(tucked: false, on: screen) else { return }
        let free = edgeIsFree(side, of: screen, window: out), tucked = isTucked && free
        if let f = dockedFrame(tucked: tucked, on: screen), f != window.frame {
            Log.write("Dock: moved to \(NSStringFromRect(window.frame)) from outside, back to the \(side.rawValue) edge of screen \(NSStringFromRect(screen.frame))\(free ? "" : ", out: another display beyond it")")
        }
        place(tucked: tucked, animated: false)
        if !free { heldOut = true } else if heldOut { heldOut = false; scheduleTuck(after: Self.tuckAfter) }
    }

    /// Tuck now, unless something is going on: then look again shortly (mouseExited does not come again while the mouse rests in the transparent ear column).
    /// Not with another display beyond the edge (connected since the panel docked): it would show the tucked panel.
    private func tryTuck() {
        guard let side, autoHide, !isTucked, window.isVisible else { return }
        if let screen = dockScreen, !edgeIsFree(side, of: screen, window: window.frame) { heldOut = true; return }
        if isBusy || window.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) {
            scheduleTuck(after: 0.5)
            return
        }
        place(tucked: true, animated: true)
    }

    /// The mouse button is down (a drag, or a click held), a menu or a popover is open, or a key was just typed into the panel.
    /// (Not "a text view is the first responder": the panel makes one so as soon as it becomes key, and the panel would never tuck while key.)
    private var isBusy: Bool {
        NSEvent.pressedMouseButtons != 0 || dragging || menuTracking > 0 || !(window.childWindows ?? []).isEmpty
            || Date().timeIntervalSince(lastKey) < Self.typingHold
    }
}

extension NSScreen {
    /// The display's ID, the same for as long as it is connected (an NSScreen object is not: the screens are made anew when the displays change).
    var displayID: CGDirectDisplayID? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
}
