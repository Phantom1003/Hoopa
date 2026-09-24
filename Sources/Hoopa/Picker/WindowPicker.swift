import AppKit

/// Visual picking: a transparent window over every screen, highlights the target under the mouse, click to confirm.
final class WindowPicker {
    private var overlays: [OverlayWindow] = []
    private var timer: Timer?
    private var keyMonitor: Any?
    private var completion: ((ContextBinding?) -> Void)?
    private let resolveQueue = DispatchQueue(label: "hoopa.picker.resolve", qos: .userInteractive)
    private var generation = 0
    private var resolving = false
    private var pendingPoint: (CGPoint, Bool)?
    private var lastPoint: CGPoint?
    private var lastMode: Bool?
    private(set) var hover: HoverTarget?
    private var finished = false

    func begin(completion: @escaping (ContextBinding?) -> Void) {
        self.completion = completion
        for screen in NSScreen.screens {
            let w = OverlayWindow(screen: screen)
            w.overlayView.picker = self
            overlays.append(w)
        }
        Log.write("Picker started overlays=\(overlays.count)")
        NSApp.activate(ignoringOtherApps: true)
        for (i, w) in overlays.enumerated() {
            if i == 0 { w.makeKeyAndOrderFront(nil) } else { w.orderFrontRegardless() }
        }
        overlays.first.map { $0.makeFirstResponder($0.overlayView) }
        NSCursor.crosshair.push()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, !self.finished else { return e }
            if e.keyCode == 53 { self.cancel(); return nil }   // Esc
            return e
        }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func cancel() {
        Log.write("Pick cancelled")
        finish(nil)
    }

    /// The user clicked: take the overlays down first (so they do not cover a system permission prompt), then turn the target into a binding in the background.
    func commit() {
        Log.write("Pick click hover=\(hover.map { "\($0.appName) / \($0.windowTitle) elementMode=\($0.elementMode) el=\($0.elementRole ?? "-")/\($0.elementLabel ?? "-")" } ?? "nil")")
        guard !finished, let target = hover else { return }
        let c = completion
        teardown()
        onWillCapture?()
        DispatchQueue.global(qos: .userInitiated).async {
            let binding = ContextCapture.capture(target)
            DispatchQueue.main.async { c?(binding) }
        }
    }

    /// Called once the overlays are down and the background read starts (the UI can show "Reading…").
    var onWillCapture: (() -> Void)?

    // MARK: Internals

    private func tick() {
        guard !finished else { return }
        let cg = Coord.cg(fromCocoa: NSEvent.mouseLocation)
        let mode = NSEvent.modifierFlags.contains(.option)
        if let lp = lastPoint, lastMode == mode, abs(lp.x - cg.x) < 2, abs(lp.y - cg.y) < 2 { return }
        lastPoint = cg
        lastMode = mode
        overlays.forEach { $0.overlayView.elementMode = mode }
        request(cg, mode)
    }

    private func request(_ p: CGPoint, _ mode: Bool) {
        if resolving { pendingPoint = (p, mode); return }
        resolving = true
        generation += 1
        let gen = generation
        resolveQueue.async { [weak self] in
            let target = ContextCapture.resolve(at: p, elementMode: mode)
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                self.resolving = false
                if gen == self.generation {
                    if target?.window.pid != self.hover?.window.pid {
                        Log.write("Hover -> \(target.map { "\($0.appName) pid=\($0.window.pid) title=\($0.windowTitle) axWin=\($0.axWindow != nil)" } ?? "no window")")
                    }
                    self.hover = target
                    self.overlays.forEach { $0.overlayView.target = target }
                }
                if let (pp, pm) = self.pendingPoint {
                    self.pendingPoint = nil
                    self.request(pp, pm)
                }
            }
        }
    }

    private func finish(_ binding: ContextBinding?) {
        guard !finished else { return }
        let c = completion
        teardown()
        c?(binding)
    }

    private func teardown() {
        finished = true
        completion = nil
        timer?.invalidate()
        timer = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        NSCursor.pop()
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        NSApp.deactivate()
    }
}

// MARK: - Overlay window

final class OverlayWindow: NSWindow {
    let overlayView: OverlayView

    init(screen: NSScreen) {
        overlayView = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        contentView = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayView: NSView {
    weak var picker: WindowPicker?
    var target: HoverTarget? { didSet { needsDisplay = true } }
    var elementMode = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { picker?.commit() }
    override func rightMouseDown(with event: NSEvent) { picker?.cancel() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { picker?.cancel() }
    }

    private func local(_ cg: CGRect) -> NSRect {
        guard let win = window else { return .zero }
        let inWindow = win.convertFromScreen(Coord.cocoaRect(fromCG: cg))
        return convert(inWindow, from: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim slightly so the highlight stands out.
        NSColor.black.withAlphaComponent(0.10).setFill()
        bounds.fill()

        if let t = target {
            let winRect = local(t.windowFrame)
            if winRect.intersects(bounds) {
                let strong = !(elementMode && t.elementFrame != nil)
                drawHighlight(winRect, color: .controlAccentColor, strong: strong, fill: strong)
                let name = t.windowTitle.isEmpty ? t.appName : "\(t.appName) — \(t.windowTitle)"
                drawLabel(name, near: winRect, color: .controlAccentColor)
            }
            if elementMode, t.elementFrame == nil, let hint = t.hint {
                let at = local(CGRect(x: t.point.x, y: t.point.y, width: 1, height: 1))
                drawLabel(hint, near: at.insetBy(dx: -12, dy: -12), color: .systemOrange, below: true)
            }
            if elementMode, let ef = t.elementFrame {
                let r = local(ef)
                if r.intersects(bounds) {
                    drawHighlight(r, color: .systemOrange, strong: true, fill: true)
                    let roleName = friendlyRole(t.elementRole, t.elementSubrole)
                    drawLabel(String(localized: "\(roleName): \(t.elementLabel ?? String(localized: "(no text)"))"), near: r, color: .systemOrange, below: true)
                }
            }
        }
        drawHUD()
    }

    private func drawHighlight(_ r: NSRect, color: NSColor, strong: Bool, fill: Bool) {
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        if fill {
            color.withAlphaComponent(strong ? 0.16 : 0.06).setFill()
            path.fill()
        }
        color.withAlphaComponent(strong ? 1 : 0.5).setStroke()
        path.lineWidth = strong ? 3 : 2
        path.stroke()
    }

    private func drawLabel(_ text: String, near r: NSRect, color: NSColor, below: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let s = NSAttributedString(string: String(text.prefix(90)), attributes: attrs)
        let size = s.size()
        let pad: CGFloat = 6
        var box = NSRect(x: r.minX, y: below ? r.minY - size.height - pad * 2 - 4 : r.maxY + 4,
                         width: size.width + pad * 2, height: size.height + pad * 2)
        if box.maxY > bounds.maxY { box.origin.y = r.maxY - box.height - 4 }
        if box.minY < bounds.minY { box.origin.y = r.minY + 4 }
        if box.maxX > bounds.maxX { box.origin.x = bounds.maxX - box.width - 4 }
        if box.minX < bounds.minX { box.origin.x = bounds.minX + 4 }
        let bg = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
        color.withAlphaComponent(0.92).setFill()
        bg.fill()
        s.draw(at: NSPoint(x: box.minX + pad, y: box.minY + pad))
    }

    private func drawHUD() {
        let lines: [String] = elementMode
            ? [String(localized: "Element mode: click to bind the highlighted tab / sidebar item / button"),
               String(localized: "Release ⌥ to return to window mode · Esc to cancel")]
            : [String(localized: "Move the mouse to highlight a window, click to bind it"),
               String(localized: "Hold ⌥ to pick a tab / sidebar item inside the window · Esc to cancel")]
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: lines.joined(separator: "\n"), attributes: attrs)
        let size = text.size()
        let pad: CGFloat = 14
        let box = NSRect(x: bounds.midX - size.width / 2 - pad, y: bounds.maxY - size.height - pad * 2 - 48,
                         width: size.width + pad * 2, height: size.height + pad * 2)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        text.draw(in: box.insetBy(dx: pad, dy: pad))
    }

    private func friendlyRole(_ role: String?, _ subrole: String?) -> String {
        if subrole == "AXTabButton" { return String(localized: "Tab") }
        switch role {
        case kAXRadioButtonRole: return String(localized: "Tab / Option")
        case kAXButtonRole: return String(localized: "Button")
        case kAXRowRole: return String(localized: "Row")
        case kAXCellRole: return String(localized: "Cell")
        case "AXLink": return String(localized: "Link")
        case kAXMenuItemRole: return String(localized: "Menu Item")
        case kAXStaticTextRole: return String(localized: "Text")
        case kAXImageRole: return String(localized: "Image")
        case "AXTab": return String(localized: "Tab")
        default: return role?.replacingOccurrences(of: "AX", with: "") ?? String(localized: "Element")
        }
    }
}
