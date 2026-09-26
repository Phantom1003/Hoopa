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

    func show() {
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
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
        if animated { trackShadow(for: compact ? Motion.collapseBusy : Motion.expandBusy) } else { invalidateShadow() }
    }

    /// Remember the size while the window is the expanded panel (not when launching at the collapsed size: that is always smaller than the panel's minimum).
    private func rememberExpandedSize() {
        guard frame.width >= FloatingPanel.expandedMin.width, frame.height >= FloatingPanel.expandedMin.height else { return }
        expandedSize = frame.size
    }

    private var shadowTimer: Timer?
    private var earShown = false

    /// The ear slides out / back: the ear part of the mask slides (Core Animation) and the shadow refreshes.
    func setEar(shown: Bool, busy: TimeInterval) {
        earShown = shown
        hosting.earMask = shown
        trackShadow(for: busy)
    }

    /// Keeps the window shadow refreshing during a morph: a transparent window's shadow follows the content's shape and keeps the old one unless refreshed.
    func trackShadow(for duration: TimeInterval) {
        shadowTimer?.invalidate()
        let end = Date().addingTimeInterval(duration + 0.1)
        shadowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] t in
            self?.invalidateShadow()
            if Date() >= end { t.invalidate() }
        }
    }
}

/// When the panel is not the key window the first click also goes straight to SwiftUI instead of only making the window key;
/// pressing on empty space (not a button / text field) drags the whole window (a borderless window has no title bar to drag).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    /// The ear is out: the ear part of the mask slides out (animated).
    var earMask = false { didSet { updateMask(animated: true) } }
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

    /// SwiftUI's clipShape does not reach AppKit subviews (the NSScrollView under the list is square and shows white corners outside the rounding),
    /// so the mask is applied on the layer, and the scroll view's own white background is switched off.
    /// The mask is the outline of the panel / slab: a rounded rectangle (starting right of the ear's column) plus the ear on the left. The plate glass spans the ear's column;
    /// the ear is cut out of it, so ear and panel are the same piece of glass. Both shapes carry a mask (while the window is larger than the content the mask is larger than the glass and does not clip it).
    override func layout() {
        super.layout()
        fitWindow()
        wantsLayer = true
        updateMask(animated: false)
        clearScrollBackgrounds(self)
    }

    private func updateMask(animated: Bool) {
        let mask = (layer?.mask as? CAShapeLayer) ?? CAShapeLayer()
        let b = bounds
        let path = maskPath(in: b, ear: earMask ? Ear.width + Ear.radius : 0.5)
        if animated, let old = mask.path {
            let anim = CABasicAnimation(keyPath: "path")
            anim.fromValue = old
            anim.toValue = path
            anim.duration = Motion.earDuration
            anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            mask.add(anim, forKey: "path")
        }
        mask.frame = b
        mask.path = path
        layer?.mask = mask
    }

    /// The ear slides out w wide to the left from under the panel (extending Ear.radius under the panel so the seam does not show); a very small w means no ear.
    private func maskPath(in b: CGRect, ear w: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: Ear.width, y: 0, width: b.width - Ear.width, height: b.height), cornerWidth: 18, cornerHeight: 18)
        let earY = isFlipped ? Ear.top : b.height - Ear.top - Ear.height
        let r = min(Ear.radius, w / 2)
        path.addRoundedRect(in: CGRect(x: Ear.width + Ear.radius - w, y: earY, width: w, height: Ear.height), cornerWidth: r, cornerHeight: r)
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
