import AppKit
import SwiftUI

/// The always-floating panel. Non-activating (like Spotlight): hovering and clicking work right away without a click to activate the app first;
/// a jump does not first pull the focus to Hoopa and then away. When input is needed the panel becomes the key window by itself without activating the whole app.
/// Two shapes: collapsed (a glass slab sized to its content) or an expanded, resizable panel; the top left corner stays put when switching.
final class FloatingPanel: NSPanel {
    // The window has the ear's column (Ear.width) on the left; the panel proper is that much narrower than the window.
    static let expandedDefault = NSSize(width: 360 + Ear.width, height: 480)
    static let expandedMin = NSSize(width: 300 + Ear.width, height: 320)
    /// The size of the expanded panel. AppKit's autosave under "HoopaPanel" stores the window size at the time, which after quitting collapsed is the collapsed size,
    /// so the expanded size is stored in the preferences separately: after a relaunch the panel expands to its last size instead of the minimum.
    private var expandedSize: NSSize {
        get { UserDefaults.standard.string(forKey: "expandedSize").map(NSSizeFromString) ?? FloatingPanel.expandedDefault }
        set { UserDefaults.standard.set(NSStringFromSize(newValue), forKey: "expandedSize") }
    }
    private let hosting: FirstMouseHostingView<AnyView>
    /// The window size changed (including the growth at the moment of expanding); report it to the UI layer.
    var onResize: ((CGSize) -> Void)?
    /// Docking at a screen edge (dropped against the left, right or top edge, the panel slides off the screen when the mouse leaves), see EdgeDock.
    private(set) var dock: EdgeDock!
    /// The size the panel has by its own doing: set by the app (collapse / expand, the slab fitted to its content) or dragged out by the user. Any other resize is undone, see undoOutsideResize.
    private var ownSize = NSSize.zero
    /// The panel is setting its own frame (see setOwnFrame).
    private var resizingSelf = false
    /// A drag of the panel by its empty space is on: where the mouse and the window were when it started (screen coordinates).
    private var drag: (mouse: NSPoint, origin: NSPoint)?

    init(contentView: FirstMouseHostingView<AnyView>) {
        hosting = contentView
        // Borderless: the system window frame would draw a dark rounded rectangle around the glass, so SwiftUI draws the whole appearance itself (Liquid Glass).
        super.init(contentRect: NSRect(origin: .zero, size: FloatingPanel.expandedDefault),
                   styleMask: [.borderless, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        // fullScreenAuxiliary: the panel shows over other apps' full-screen windows and has no full screen of its own (see toggleFullScreen); disallowsTiling keeps it out of the system's split view.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovableByWindowBackground = false   // the panel moves itself when dragged, see mouseDown
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        applyChrome()
        self.contentView = contentView
        setFrameAutosaveName("HoopaPanel")
        if !setFrameUsingName("HoopaPanel"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - 180, y: f.maxY - 520))
        } else if clipped(frame.size) != frame.size {   // saved larger than the screen (filled by the system, or sized on a larger screen): its edges would be off the screen, out of reach
            let size = clipped(frame.size)
            Log.write("Saved frame \(NSStringFromSize(frame.size)) is larger than the screen, clipped to \(NSStringFromSize(size))")
            setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: false)
        }
        ownSize = frame.size
        if UserDefaults.standard.string(forKey: "expandedSize") == nil { rememberExpandedSize() }
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: self, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.undoOutsideResize() { return }    // the undo sets the frame again and this runs once more with the size put back
            self.onResize?(self.frame.size)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: self, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.ownSize = self.frame.size            // dragged out by the user: the panel's own size from now on
        }
        dock = EdgeDock(window: self)
        hosting.onHover = { [weak self] inside in self?.dock.hover(inside) }
    }

    /// Transparent background. Changing styleMask makes AppKit rebuild the window layer, so both have to be applied again.
    private func applyChrome() {
        isOpaque = false
        backgroundColor = .clear
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The panel has no full screen mode and is never zoomed: a to-do list the size of the screen is never wanted, and the panel would come back from it with the screen's size as its own.
    /// fullScreenAuxiliary leaves it out of the system's full screen already; ⌃⌘F / 🌐F and the Fill shortcuts still arrive here, and do nothing.
    override func toggleFullScreen(_ sender: Any?) { Log.write("Full screen ignored") }
    override func zoom(_ sender: Any?) { Log.write("Zoom ignored") }

    /// A press on empty space (nothing in the SwiftUI content took it, so it came down the responder chain to the window) drags the panel; the panel moves itself, by its frame, on every
    /// mouseDragged, instead of handing the drag to the window server (isMovableByWindowBackground). A drag the window server runs is what the system's window tiling watches:
    /// dropped against the top of the screen (where the panel docks) it filled the screen with the panel, or moved a panel it could not resize (collapsed) to the middle of the screen.
    /// Moved by its own frame, the panel is just a window changing its origin, and nothing else. The top stays below the menu bar, as the window server keeps dragged windows (the dock's
    /// top edge is that line, see EdgeDock.dragEnded); the dock sees the moves with the button down and takes over when it comes up, as before.
    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else { super.mouseDown(with: event); return }
        drag = (NSEvent.mouseLocation, frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { super.mouseDragged(with: event); return }
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: drag.origin.x + mouse.x - drag.mouse.x, y: drag.origin.y + mouse.y - drag.mouse.y)
        if let s = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? screen ?? NSScreen.main {
            origin.y = min(origin.y, s.visibleFrame.maxY - frame.height)
        }
        setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        if drag != nil { drag = nil } else { super.mouseUp(with: event) }
    }

    /// Sets the frame from the panel's own code; the size becomes the panel's own. Every resize the panel makes goes through here (the dock only moves it).
    func setOwnFrame(_ f: NSRect, display: Bool) {
        resizingSelf = true
        setFrame(f, display: display)
        resizingSelf = false
        ownSize = frame.size
    }

    /// A size the panel did not choose: dragged against the top edge of the screen (where it docks), the system's window tiling fills the screen with the window, and the tiling shortcuts tile it;
    /// a panel the size of the screen is never wanted, and docked, its far edges are off the screen where no drag can shrink it back. So the size is put back, top left corner fixed.
    /// The user's own resize (a live resize, or any change while the mouse button is down) and the panel's (resizingSelf) pass; only a resize with the button up and nobody's name on it is undone.
    /// A point or two is AppKit rounding the frame to pixels while a slide moves it (the collapsed slab's fitted size is fractional), the panel's own as well, or the undo would fight the slide.
    private func undoOutsideResize() -> Bool {
        guard !resizingSelf, !inLiveResize, ownSize.width > 0, frame.size != ownSize else { return false }
        if NSEvent.pressedMouseButtons != 0 || (abs(frame.width - ownSize.width) <= 2 && abs(frame.height - ownSize.height) <= 2) {
            ownSize = frame.size
            return false
        }
        Log.write("Resized from outside to \(NSStringFromSize(frame.size)), back to \(NSStringFromSize(ownSize))")
        setOwnFrame(NSRect(x: frame.minX, y: frame.maxY - ownSize.height, width: ownSize.width, height: ownSize.height), display: true)
        return true
    }

    /// No larger than the screen's visible frame: larger, the panel's edges are off the screen where no resize can reach them.
    private func clipped(_ size: NSSize) -> NSSize {
        guard let v = (screen ?? NSScreen.main)?.visibleFrame.size else { return size }
        return NSSize(width: min(size.width, v.width), height: min(size.height, v.height))
    }

    /// The system keeps windows below the menu bar by default, so dragging to the top of the screen "sticks"; the floating panel may reach the top edge.
    /// Docked at the top edge the frame is the dock's business and not constrained at all, unless the mouse is dragging the window: tucked, the panel sits above the screen but for its strip,
    /// and AppKit re-validates the frame on its own occasions (not only while the dock is placing it), which pushed a tucked panel back down to the top of the screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        if let dock, dock.placing || (dock.side == .top && !dock.dragging) { return frameRect }
        guard let s = screen ?? self.screen ?? NSScreen.main else { return frameRect }
        var f = frameRect
        f.origin.y = min(f.origin.y, s.frame.maxY - f.height)
        f.origin.y = max(f.origin.y, s.frame.minY)
        return f
    }

    /// When the panel is not the key window, AppKit spends the first click on "becoming key" instead of handing it to the hit view
    /// (under the list is an NSScrollView, which acceptsFirstMouse on the SwiftUI hosting view does not reach).
    /// So on mouse down become key first (a non-activating panel does not activate the whole app), then dispatch normally; the first click works.
    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type), !isKeyWindow {
            makeKey()
        }
        if event.type == .keyDown { dock.noteKey() }
        super.sendEvent(event)
    }

    /// Docked and slid off the screen: only a strip of the plate shows at the edge.
    var isTucked: Bool { dock.isTucked }

    func show() {
        dock.willShow()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    override func resignKey() {
        super.resignKey()
        dock.didResignKey()
    }

    func setAlwaysOnTop(_ on: Bool) {
        level = on ? .floating : .normal
    }

    /// Collapse / expand, top left corner fixed. Collapsing sizes the window to the content and shrinks it once the collapse animation is over; expanding grows it to the panel size at once
    /// (the extra area is transparent and click-through, invisible) and the panel glass then grows out of the slab.
    func setCompact(_ compact: Bool, animated: Bool = true) {
        resizingSelf = true                 // setting minSize resizes the window by itself; all of this is the panel's own doing
        defer { resizingSelf = false; ownSize = frame.size }
        if compact {
            rememberExpandedSize()
            styleMask.remove(.resizable)
            applyChrome()
            minSize = NSSize(width: 40, height: 30)
            if animated { hosting.noteMorph(Motion.collapseBusy) }
            hosting.autoFit = true          // shrinking waits for the collapse animation, see fitWindow
            if !animated { hosting.fitWindow(immediately: true) }
        } else {
            hosting.autoFit = false
            styleMask.insert(.resizable)
            applyChrome()
            minSize = FloatingPanel.expandedMin
            let fit = clipped(expandedSize)
            let size = NSSize(width: max(fit.width, FloatingPanel.expandedMin.width),
                              height: max(fit.height, FloatingPanel.expandedMin.height))
            var f = NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
            if let v = (screen ?? NSScreen.main)?.frame {   // stay on screen
                f.origin.x = min(max(f.origin.x, v.minX), v.maxX - f.width)
                f.origin.y = min(max(f.origin.y, v.minY), v.maxY - f.height)
            }
            onResize?(f.size)               // tell the UI layer the panel size first, so the plate's end rect is right
            setFrame(f, display: true)      // lay out once at the new size right away (the state has not changed yet), see AppCoordinator.isCompact
        }
    }

    /// Remember the size while the window is the expanded panel (not when launching at the collapsed size: that is always smaller than the panel's minimum).
    private func rememberExpandedSize() {
        guard frame.width >= FloatingPanel.expandedMin.width, frame.height >= FloatingPanel.expandedMin.height else { return }
        expandedSize = clipped(frame.size)
    }

    /// The mask geometry, reported by RootView every frame: the plate's current rect (root view coordinates) and the ear. See FirstMouseHostingView.setMask.
    func setMask(_ geometry: MaskGeometry) { hosting.setMask(geometry) }

    /// Cut this much off the top of the window (docked at the top edge, the part behind the menu bar). See FirstMouseHostingView.setHiddenTop.
    func setHiddenTop(_ hidden: CGFloat) { hosting.setHiddenTop(hidden) }
}

/// When the panel is not the key window the first click also goes straight to SwiftUI instead of only making the window key;
/// pressing on empty space (not a button / text field) falls through to the window, which drags itself (a borderless window has no title bar to drag), see FloatingPanel.mouseDown.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    /// The mask geometry, reported by RootView every frame (mid-animation SwiftUI values): the plate's current rect (root view coordinates, spanning the ear's column) and the ear.
    /// The mask has no animation of its own and follows every frame, so the corners always sit on the plate's corners: if the mask clipped to the window size while the plate shrinks / grows,
    /// the plate's bottom left corner would land on the mask's straight edge and turn square (the plate's left corners are cut by the mask; the glass itself extends under the ear's column).
    private var geometry = MaskGeometry()
    /// The top of the window cut off by the mask: docked at the top edge, the part slid up behind the (transparent) menu bar, see EdgeDock.
    private var hiddenTop: CGFloat = 0

    func setMask(_ g: MaskGeometry) {
        guard g != geometry else { return }
        geometry = g
        updateMask()
    }

    func setHiddenTop(_ hidden: CGFloat) {
        guard hidden != hiddenTop else { return }
        hiddenTop = hidden
        updateMask()
    }
    /// Collapsed: the window is sized to the content. NSHostingView's own preferredContentSize does nothing here, so measure and set it ourselves.
    var autoFit = false { didSet { needsLayout = true } }
    private var fitting = false
    private var shrinkPending = false
    private var busyUntil = Date.distantPast

    /// A collapse animation is playing: until busy seconds pass, the window only grows.
    func noteMorph(_ busy: TimeInterval) {
        busyUntil = max(busyUntil, Date().addingTimeInterval(busy))
    }

    /// Sizes the window to the content's ideal size, top left corner fixed. Growing happens at once (the extra area is transparent, invisible);
    /// shrinking waits until the animation is over (see noteMorph), so glass still folding is not clipped.
    func fitWindow(immediately: Bool = false) {
        guard autoFit, let w = window, !fitting else { return }
        let size = fittingSize
        guard size.width > 1, size.height > 1 else { return }
        if immediately { resizeWindow(to: size); return }
        let cur = w.frame.size
        let grown = NSSize(width: max(cur.width, size.width), height: max(cur.height, size.height))
        if grown != cur { resizeWindow(to: grown) }
        if size.width < grown.width - 0.5 || size.height < grown.height - 0.5 { scheduleShrink() }
    }

    private func scheduleShrink() {
        guard !shrinkPending else { return }
        shrinkPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(busyUntil.timeIntervalSinceNow, 0) + 0.05) { [weak self] in
            guard let self else { return }
            self.shrinkPending = false
            if self.busyUntil > Date() { self.scheduleShrink(); return }   // another animation started meanwhile
            self.fitWindow(immediately: true)     // to the content size at that moment
        }
    }

    private func resizeWindow(to size: NSSize) {
        guard let w = window,
              abs(w.frame.width - size.width) > 0.5 || abs(w.frame.height - size.height) > 0.5 else { return }
        fitting = true
        let f = NSRect(x: w.frame.minX, y: w.frame.maxY - size.height, width: size.width, height: size.height)
        if let panel = w as? FloatingPanel { panel.setOwnFrame(f, display: true) } else { w.setFrame(f, display: true) }
        w.invalidateShadow()
        fitting = false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Not the window server's drag (see FloatingPanel.mouseDown).
    override var mouseDownCanMoveWindow: Bool { false }

    /// The mouse entered / left the window (its glass: the window server does not route the mouse over transparent pixels). Independent of SwiftUI's hover, for the window's docking.
    var onHover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === hoverArea { onHover?(true) } else { super.mouseEntered(with: event) }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === hoverArea { onHover?(false) } else { super.mouseExited(with: event) }
    }

    /// SwiftUI's clipShape does not reach AppKit subviews (the NSScrollView under the list is square and shows white corners outside the rounding),
    /// so the mask is applied on the layer, and the scroll view's own white background is switched off.
    /// The mask is the outline of the panel / slab: the plate's rounded rectangle (starting right of the ear's column) plus the ear on the left. The plate glass spans the ear's column;
    /// the ear is cut out of it, so ear and panel are the same piece of glass. While the window is larger than the plate the mask is only as large as the plate; the rest is empty anyway.
    override func layout() {
        super.layout()
        fitWindow()
        wantsLayer = true
        updateMask()
        clearScrollBackgrounds(self)
    }

    private func updateMask() {
        guard let layer else { return }
        let mask = (layer.mask as? CAShapeLayer) ?? CAShapeLayer()
        let b = bounds
        // Changing a standalone layer's frame implicitly animates for 0.25 s (at the moment of growing the mask is still smaller than the plate and clips it square); switch it off: the mask is set directly from the reported value every frame.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = b
        var path = maskPath(in: b, geometry)
        if hiddenTop > 0 {   // docked at the top edge: whatever is behind the menu bar is cut off
            path = path.intersection(CGPath(rect: CGRect(x: b.minX, y: b.minY + hiddenTop, width: b.width, height: max(b.height - hiddenTop, 0)), transform: nil))
        }
        mask.path = path
        layer.mask = mask
        CATransaction.commit()
        window?.invalidateShadow()    // a transparent window's shadow follows the content's shape; refresh it when the shape changes or it keeps the old one
    }

    /// The plate rect without the ear's column (on its left, or on its right when the ear is there) is clipped to a rounded rectangle; the ear slides out w wide from under the panel on that side
    /// (extending Ear.radius under the panel so the seam does not show), and a very small w means no ear. Coordinates start at the top left (NSHostingView is flipped, matching SwiftUI's root view coordinates).
    private func maskPath(in b: CGRect, _ g: MaskGeometry) -> CGPath {
        let plate = g.plate ?? b
        let path = CGMutablePath()
        let body = CGRect(x: plate.minX + (g.earRight ? 0 : Ear.width), y: plate.minY, width: max(plate.width - Ear.width, 0), height: plate.height)
        let radius = min(18, body.width / 2, body.height / 2)
        path.addRoundedRect(in: body, cornerWidth: radius, cornerHeight: radius)
        let w = g.ear, r = min(Ear.radius, w / 2)
        let x = g.earRight ? body.maxX - Ear.radius : body.minX + Ear.radius - w
        path.addRoundedRect(in: CGRect(x: x, y: Ear.top, width: w, height: Ear.height), cornerWidth: r, cornerHeight: r)
        return path
    }

    private func clearScrollBackgrounds(_ v: NSView) {
        if let sv = v as? NSScrollView {
            sv.drawsBackground = false
            sv.backgroundColor = .clear
            sv.contentView.drawsBackground = false
            sv.scrollerStyle = .overlay      // overlay scroller, takes no content width
            sv.autohidesScrollers = true
        }
        v.subviews.forEach(clearScrollBackgrounds)
    }
}
