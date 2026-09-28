import AppKit

/// Docking at a screen edge. Dropping the panel against the left or right edge of a screen (or partly beyond it) docks it there: it sits flush with the edge,
/// and slides off the screen a moment after the mouse leaves, leaving a thin strip of glass at the edge; the mouse on that strip slides it back.
/// Dragging it away from the edge undocks it, and it is an ordinary floating panel again. The side is remembered across launches.
/// Tucking waits while the mouse button is down, a menu or popover is open, or a key was just typed into the panel, so nothing slides away under the user's hands.
/// The window is only ever moved, never resized, here; collapse / expand keep working, and after a resize the panel is snapped to the edge again.
final class EdgeDock {
    enum Side: String { case left, right }

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
    private(set) var side: Side? {
        didSet {
            if let side { UserDefaults.standard.set(side.rawValue, forKey: Self.key) } else { UserDefaults.standard.removeObject(forKey: Self.key) }
            onSideChange?(side)
        }
    }
    /// The side changed (the UI squares the plate's corners on the docked side).
    var onSideChange: ((Side?) -> Void)?
    private var lastKey = Date.distantPast
    /// Docked and slid off the screen (only the strip shows).
    private(set) var isTucked = false
    private var dragging = false
    private var placing = false
    /// A resize came while a slide was running: snap again once it is over.
    private var snapAfterPlacing = false
    private var menuTracking = 0
    private var tuckWork: DispatchWorkItem?
    private var revealWork: DispatchWorkItem?
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
    private func noteMove() {
        guard NSEvent.pressedMouseButtons != 0, !placing else { return }
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

    /// The window was dropped after a drag (also called by the test harness): the position decides.
    func dragEnded() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let f = window.frame, s = screen.frame
        var next: Side?
        if f.minX <= s.minX + Self.snap, edgeIsFree(.left, of: screen, at: f.midY) { next = .left }
        else if f.maxX >= s.maxX - Self.snap, edgeIsFree(.right, of: screen, at: f.midY) { next = .right }
        if next != side {
            side = next
            isTucked = false
            Log.write(next.map { "Dock: \($0.rawValue) edge of screen \(NSStringFromRect(s))" } ?? "Undock")
        }
        guard side != nil else { return }
        place(tucked: false, animated: true)
        scheduleTuck(after: Self.tuckAfter)
    }

    /// Nothing beyond that edge: another display there would show the tucked panel instead of hiding it.
    private func edgeIsFree(_ side: Side, of screen: NSScreen, at y: CGFloat) -> Bool {
        let beyond = NSPoint(x: side == .left ? screen.frame.minX - 1 : screen.frame.maxX + 1, y: y)
        return !NSScreen.screens.contains { $0 != screen && $0.frame.contains(beyond) }
    }

    /// The window's frame docked at the side, flush with the edge, or tucked with only the strip on screen. The window's left column is the ear's (transparent, the ear only on hover),
    /// so at the left edge the window's own edge is flush and the plate stands the ear's width in; at the right edge the plate is flush.
    private func dockedFrame(tucked: Bool) -> NSRect? {
        guard let side, let screen = window.screen ?? NSScreen.main else { return nil }
        var f = window.frame
        let s = screen.frame
        switch side {
        case .left: f.origin.x = tucked ? s.minX + Self.peek - f.width : s.minX
        case .right: f.origin.x = tucked ? s.maxX - Ear.width - Self.peek : s.maxX - f.width
        }
        return f
    }

    private func place(tucked: Bool, animated: Bool) {
        guard let f = dockedFrame(tucked: tucked) else { return }
        isTucked = tucked
        guard f != window.frame else { return }
        placing = true
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Self.slide
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(f, display: true)
            }, completionHandler: { [weak self] in
                guard let self else { return }
                self.placing = false
                if self.snapAfterPlacing { self.snapAfterPlacing = false; self.place(tucked: self.isTucked, animated: true) }
            })
        } else {
            window.setFrame(f, display: true)
            placing = false
        }
    }

    private func scheduleTuck(after delay: TimeInterval) {
        tuckWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.tryTuck() }
        tuckWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Tuck now, unless something is going on: then look again shortly (mouseExited does not come again while the mouse rests in the transparent ear column).
    private func tryTuck() {
        guard side != nil, !isTucked, window.isVisible else { return }
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
