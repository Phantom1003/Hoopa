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
    /// Docking at a screen edge (dropped against the left or right edge, the panel slides off the screen when the mouse leaves), see EdgeDock.
    private(set) var dock: EdgeDock!

    init(contentView: FirstMouseHostingView<AnyView>) {
        hosting = contentView
        // Borderless: the system window frame would draw a dark rounded rectangle around the glass, so SwiftUI draws the whole appearance itself (Liquid Glass).
        super.init(contentRect: NSRect(origin: .zero, size: FloatingPanel.expandedDefault),
                   styleMask: [.borderless, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovableByWindowBackground = true
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
        }
        if UserDefaults.standard.string(forKey: "expandedSize") == nil { rememberExpandedSize() }
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: self, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.onResize?(self.frame.size)
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

    /// The system keeps windows below the menu bar by default, so dragging to the top of the screen "sticks"; the floating panel may reach the top edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
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
            let size = NSSize(width: max(expandedSize.width, FloatingPanel.expandedMin.width),
                              height: max(expandedSize.height, FloatingPanel.expandedMin.height))
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
        expandedSize = frame.size
    }

    /// The mask geometry, reported by RootView every frame: the plate's current rect (root view coordinates) and how far the ear is out. See FirstMouseHostingView.setMask.
    func setMask(plate: CGRect?, ear: CGFloat) { hosting.setMask(plate: plate, ear: ear) }
}

/// When the panel is not the key window the first click also goes straight to SwiftUI instead of only making the window key;
/// pressing on empty space (not a button / text field) drags the whole window (a borderless window has no title bar to drag).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    /// The mask geometry, reported by RootView every frame (mid-animation SwiftUI values): the plate's current rect (root view coordinates, spanning the ear's column) and how far the ear is out.
    /// The mask has no animation of its own and follows every frame, so the corners always sit on the plate's corners: if the mask clipped to the window size while the plate shrinks / grows,
    /// the plate's bottom left corner would land on the mask's straight edge and turn square (the plate's left corners are cut by the mask; the glass itself extends under the ear's column).
    private var plateRect: CGRect?
    private var earExtent: CGFloat = 0.5

    func setMask(plate: CGRect?, ear: CGFloat) {
        guard plate != plateRect || ear != earExtent else { return }
        plateRect = plate
        earExtent = ear
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
        w.setFrame(NSRect(x: w.frame.minX, y: w.frame.maxY - size.height, width: size.width, height: size.height), display: true)
        w.invalidateShadow()
        fitting = false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

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
        mask.path = maskPath(in: b, plate: plateRect ?? b, ear: earExtent)
        layer.mask = mask
        CATransaction.commit()
        window?.invalidateShadow()    // a transparent window's shadow follows the content's shape; refresh it when the shape changes or it keeps the old one
    }

    /// The plate rect is clipped to a rounded rectangle from the right of the ear's column; the ear slides out w wide to the left from under the panel (extending Ear.radius under the panel so the seam does not show),
    /// and a very small w means no ear. Coordinates start at the top left (NSHostingView is flipped, matching SwiftUI's root view coordinates).
    private func maskPath(in b: CGRect, plate: CGRect, ear w: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let body = CGRect(x: Ear.width, y: plate.minY, width: max(plate.maxX - Ear.width, 0), height: plate.height)
        let radius = min(18, body.width / 2, body.height / 2)
        path.addRoundedRect(in: body, cornerWidth: radius, cornerHeight: radius)
        let r = min(Ear.radius, w / 2)
        path.addRoundedRect(in: CGRect(x: Ear.width + Ear.radius - w, y: Ear.top, width: w, height: Ear.height), cornerWidth: r, cornerHeight: r)
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
