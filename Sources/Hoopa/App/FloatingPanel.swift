import AppKit
import SwiftUI

/// The always-floating panel. Non-activating (like Spotlight): hovering and clicking work right away without a click to activate the app first;
/// a jump does not first pull the focus to Hoopa and then away. When input is needed the panel becomes the key window by itself without activating the whole app.
/// Two shapes: collapsed into a pill (sized to its content) or an expanded, resizable panel; the top left corner stays put when switching.
final class FloatingPanel: NSPanel {
    static let expandedDefault = NSSize(width: 360, height: 480)
    static let expandedMin = NSSize(width: 300, height: 320)
    private var expandedSize = FloatingPanel.expandedDefault
    private let hosting: FirstMouseHostingView<AnyView>

    init(contentView: FirstMouseHostingView<AnyView>) {
        hosting = contentView
        // Borderless: the system window frame would draw a dark rounded rectangle around the pill, so SwiftUI draws the whole appearance itself (Liquid Glass).
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
        expandedSize = frame.size
    }

    /// Transparent background. Changing styleMask makes AppKit rebuild the window layer, so both have to be applied again.
    private func applyChrome() {
        isOpaque = false
        backgroundColor = .clear
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

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

    /// Collapse / expand. Collapsed, the SwiftUI content decides the window size (the pill follows the title length).
    func setCompact(_ compact: Bool) {
        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        if compact {
            expandedSize = frame.size
            styleMask.remove(.resizable)
            applyChrome()
            minSize = NSSize(width: 60, height: 30)
            hosting.capsule = true
            hosting.sizingOptions = [.preferredContentSize]
        } else {
            hosting.sizingOptions = []
            hosting.capsule = false
            styleMask.insert(.resizable)
            applyChrome()
            minSize = FloatingPanel.expandedMin
            let size = NSSize(width: max(expandedSize.width, FloatingPanel.expandedMin.width),
                              height: max(expandedSize.height, FloatingPanel.expandedMin.height))
            setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), display: true, animate: true)
        }
        DispatchQueue.main.async { [self] in
            // After the content size changes, put the top left corner back and stay on screen.
            var f = frame
            f.origin.y = topLeft.y - f.height
            f.origin.x = topLeft.x
            if let s = screen ?? NSScreen.main {
                let v = s.visibleFrame
                f.origin.x = min(max(f.origin.x, v.minX), v.maxX - f.width)
                f.origin.y = min(max(f.origin.y, v.minY), v.maxY - f.height)
            }
            setFrameOrigin(f.origin)
            invalidateShadow()
        }
    }
}

/// When the panel is not the key window the first click also goes straight to SwiftUI instead of only making the window key;
/// pressing on empty space (not a button / text field) drags the whole window (a borderless window has no title bar to drag).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    /// Collapsed is a capsule (corner radius = half the height), expanded has 18pt corners.
    var capsule = false { didSet { needsLayout = true } }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    /// SwiftUI's clipShape does not reach AppKit subviews (the NSScrollView under the list is square and shows white corners outside the rounding),
    /// so the rounded mask is applied on the layer, and the scroll view's own white background is switched off.
    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = capsule ? bounds.height / 2 : 18
        clearScrollBackgrounds(self)
    }

    private func clearScrollBackgrounds(_ v: NSView) {
        if let sv = v as? NSScrollView {
            sv.drawsBackground = false
            sv.backgroundColor = .clear
            sv.contentView.drawsBackground = false
        }
        v.subviews.forEach(clearScrollBackgrounds)
    }
}
