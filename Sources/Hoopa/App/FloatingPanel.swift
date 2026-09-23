import AppKit
import SwiftUI

/// The always-floating panel. Non-activating (like Spotlight): hovering and clicking work right away without a click to activate the app first;
/// a jump does not first pull the focus to Hoopa and then away. When input is needed the panel becomes the key window by itself without activating the whole app.
final class FloatingPanel: NSPanel {
    init(contentView: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        minSize = NSSize(width: 300, height: 320)
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        self.contentView = contentView
        setFrameAutosaveName("HoopaPanel")
        if !setFrameUsingName("HoopaPanel") {
            if let screen = NSScreen.main {
                let f = screen.visibleFrame
                setFrameOrigin(NSPoint(x: f.maxX - 380, y: f.maxY - 560))
            }
        }
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
}

/// When the panel is not the key window the first click also goes straight to SwiftUI instead of only making the window key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
