import AppKit
import ApplicationServices

enum RestoreOutcome: Int, Comparable {
    case appOnly        // only the app could be activated
    case windowOnly     // the window was found but not the target
    case unverified     // the target was triggered but the page change could not be confirmed
    case reopened       // the page was gone and has been reopened
    case exact          // back at the target exactly

    var message: String {
        switch self {
        case .exact: return String(localized: "Jumped back")
        case .reopened: return String(localized: "The page was closed and has been reopened")
        case .unverified: return String(localized: "Triggered the target, but couldn't confirm the page switched")
        case .windowOnly: return String(localized: "Switched to the window, but couldn't find the exact target")
        case .appOnly: return String(localized: "Activated the app, but couldn't find that window")
        }
    }

    static func < (a: RestoreOutcome, b: RestoreOutcome) -> Bool { a.rawValue < b.rawValue }
}

enum RestoreError: Error {
    case appNotFound
    case launchFailed
    case noAccessibility

    var message: String {
        switch self {
        case .appNotFound: return String(localized: "Can't find the app; it may have been deleted")
        case .launchFailed: return String(localized: "The app failed to launch")
        case .noAccessibility: return String(localized: "Accessibility access is missing, so the window can't be located")
        }
    }
}

/// Takes the user "back" to the bound work context: makes sure the app is running, then tries the anchors in order; the first one confirmed to have arrived wins.
/// Never moves the mouse cursor and never sends keyboard events.
enum ContextRestore {
    static func jump(_ b: ContextBinding, completion: @escaping (Result<RestoreOutcome, RestoreError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = perform(b)
            DispatchQueue.main.async { completion(r) }
        }
    }

    private static func perform(_ b: ContextBinding) -> Result<RestoreOutcome, RestoreError> {
        Log.write("Jump start app=\(b.bundleID) title=\(b.windowTitle) anchors=\(b.anchors.map(\.kindLabel).joined(separator: ">"))")
        guard let app = ensureRunning(b) else {
            Log.write("Jump: the app could not be launched")
            return .failure(b.appPath == nil && NSWorkspace.shared.urlForApplication(withBundleIdentifier: b.bundleID) == nil
                            ? .appNotFound : .launchFailed)
        }
        var best = RestoreOutcome.appOnly
        for anchor in b.anchors {
            let r: RestoreOutcome
            switch anchor {
            case .browserTab(let url, let title):
                r = BrowserTabs.restore(bundleID: b.bundleID, url: url, title: title, app: app)
            case .document(let path):
                r = restoreDocument(path, b, app)
            case .link(let url, let expect):
                r = restoreLink(url, expect: expect, b, app)
            case .element(let a):
                guard AX.isTrusted else { return .failure(.noAccessibility) }
                r = restoreElement(a, b, app)
            case .window:
                activate(app)
                let found = raiseWindow(app: app, choose: { chooseWindow($0, $1, b) }) != nil
                // The binding had more specific anchors and only the window was reached: that does not count as "jumped".
                r = found ? (b.anchors.count > 1 ? .windowOnly : .exact) : .appOnly
            }
            Log.write("Jump: anchor \(anchor.kindLabel) -> \(r)")
            if r >= .reopened { return .success(r) }
            best = max(best, r)
        }
        return .success(best)
    }

    // MARK: Anchor kinds

    private static func restoreDocument(_ path: String, _ b: ContextBinding, _ app: NSRunningApplication) -> RestoreOutcome {
        guard let url = URL(string: path) else { return .appOnly }
        open(url, with: app)
        Thread.sleep(forTimeInterval: 0.6)
        activate(app)
        guard AX.isTrusted else { return .unverified }
        let win = raiseWindow(app: app) { windows, axApp in
            WindowMatch.byDocument(windows, path) ?? WindowMatch.byID(windows, b.windowID)
                ?? WindowMatch.byTitle(windows, [b.windowTitle, url.lastPathComponent]) ?? WindowMatch.focused(axApp)
        }
        guard let win else { return .appOnly }
        return AX.string(win, kAXDocumentAttribute) == path ? .exact : .unverified
    }

    private static func restoreLink(_ link: String, expect: String?, _ b: ContextBinding, _ app: NSRunningApplication) -> RestoreOutcome {
        guard let url = URL(string: link) else { return .appOnly }
        open(url, with: app)
        Thread.sleep(forTimeInterval: 0.9)
        activate(app)
        guard AX.isTrusted else { return .unverified }
        let win = raiseWindow(app: app) { windows, axApp in
            WindowMatch.byTitle(windows, [expect ?? ""], threshold: 0.3) ?? WindowMatch.byID(windows, b.windowID)
                ?? WindowMatch.byTitle(windows, [b.windowTitle]) ?? WindowMatch.focused(axApp)
        }
        guard let win else { return .appOnly }
        guard let expect, !expect.isEmpty else { return .exact }
        // After opening a link the page switch may take a moment.
        for _ in 0..<4 {
            if TextLocator.verifyPresence(expect, in: win) { return .exact }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return .unverified
    }

    private static func restoreElement(_ a: AXAnchor, _ b: ContextBinding, _ app: NSRunningApplication) -> RestoreOutcome {
        activate(app)
        guard let win = raiseWindow(app: app, choose: { chooseWindow($0, $1, b) }) else { return .appOnly }
        Thread.sleep(forTimeInterval: 0.25)
        restoreTabs(a.tabs, in: win)

        // Find the target: path → DOM id → role + text → text on screen (scrolling that column if needed).
        var hit: TextLocator.Hit?
        if let el = locate(a, in: win) {
            AX.perform(el, "AXScrollToVisible")
            if let f = AX.frame(el), let wf = AX.frame(win), wf.contains(CGPoint(x: f.midX, y: f.midY)) {
                Log.write("Jump: element located role=\(AX.role(el) ?? "") label=\(AX.bestLabel(el) ?? "")")
                hit = TextLocator.Hit(frame: f, element: el)
            }
        }
        if hit == nil {
            let region = TextLocator.column(a.column, in: win)
            for t in a.texts where hit == nil {
                hit = TextLocator.find(t, in: win, region: region, scroll: true)
                if hit != nil { Log.write("Jump: found by text \"\(t)\"") }
            }
        }
        guard let hit else {
            Log.write("Jump: target not found")
            return .windowOnly
        }
        guard !a.texts.isEmpty else {
            trigger(hit, in: win, reached: { false })
            return .exact
        }
        let ok = trigger(hit, in: win) { a.texts.contains { TextLocator.verify($0, in: win, clicked: hit) } }
        Log.write("Jump: confirm \(ok ? "succeeded" : "unconfirmed")")
        return ok ? .exact : .unverified
    }

    private static func locate(_ a: AXAnchor, in win: AXUIElement) -> AXUIElement? {
        if !a.path.isEmpty, let el = AX.follow(a.path, from: win) {
            if a.texts.isEmpty || AX.matchScore(el, label: a.label, text: a.text) >= 0.6 { return el }
        }
        // A DOM id may be numbered by position (VS Code's list_id_4_2), so check the text after finding it.
        if let id = a.domID, let el = AX.first(in: win, maxNodes: 6000, where: { AX.string($0, "AXDOMIdentifier") == id }),
           a.texts.isEmpty || AX.matchScore(el, label: a.label, text: a.text) >= 0.6 {
            return el
        }
        if !a.texts.isEmpty { return AX.search(in: win, role: a.role, label: a.label, text: a.text) }
        return nil
    }

    private static func chooseWindow(_ windows: [AXUIElement], _ app: AXUIElement, _ b: ContextBinding) -> AXUIElement? {
        WindowMatch.byID(windows, b.windowID) ?? WindowMatch.only(windows)
            ?? WindowMatch.byTitle(windows, [b.windowTitle]) ?? WindowMatch.focused(app)
    }

    // MARK: App

    private static func ensureRunning(_ b: ContextBinding) -> NSRunningApplication? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: b.bundleID).first(where: { !$0.isTerminated }) {
            return app
        }
        var url: URL? = b.appPath.map { URL(fileURLWithPath: $0) }
        if let u = url, !FileManager.default.fileExists(atPath: u.path) { url = nil }
        if url == nil { url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b.bundleID) }
        guard let appURL = url else { return nil }

        let sem = DispatchSemaphore(value: 0)
        var launched: NSRunningApplication?
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) { app, _ in
            launched = app
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 25)
        guard let app = launched else { return nil }
        let deadline = Date().addingTimeInterval(25)
        while !app.isFinishedLaunching && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        Thread.sleep(forTimeInterval: 1.0)
        return app
    }

    static func activate(_ app: NSRunningApplication) {
        let work = { _ = app.activate(options: [.activateIgnoringOtherApps]) }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
    }

    static func open(_ url: URL, with app: NSRunningApplication? = nil) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        let sem = DispatchSemaphore(value: 0)
        let done: (Any?, Error?) -> Void = { _, err in
            if let err { Log.write("Open failed \(url) \(err.localizedDescription)") }
            sem.signal()
        }
        if let appURL = app?.bundleURL {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: cfg, completionHandler: done)
        } else {
            NSWorkspace.shared.open(url, configuration: cfg, completionHandler: done)
        }
        _ = sem.wait(timeout: .now() + 10)
    }

    // MARK: Window

    /// Chooses the window and brings it to the front. Retries a few times while the app creates the window.
    @discardableResult
    static func raiseWindow(app: NSRunningApplication, attempts: Int = 12,
                            choose: ([AXUIElement], AXUIElement) -> AXUIElement?) -> AXUIElement? {
        guard AX.isTrusted else { return nil }
        let axApp = AX.app(app.processIdentifier)
        AX.enableManualAccessibility(axApp)
        for i in 0..<attempts {
            let windows = AX.windows(of: axApp)
            if !windows.isEmpty, let w = choose(windows, axApp) {
                AX.set(w, kAXMinimizedAttribute, kCFBooleanFalse)
                AX.perform(w, kAXRaiseAction)
                AX.set(w, kAXMainAttribute, kCFBooleanTrue)
                AX.set(w, kAXFocusedAttribute, kCFBooleanTrue)
                Log.write("Jump: window raised title=\(AX.title(w) ?? "")")
                return w
            }
            if i < attempts - 1 { Thread.sleep(forTimeInterval: 0.35) }
        }
        Log.write("Jump: window not found")
        return nil
    }

    /// First switch back to the tab the target lived in when it was bound (such as Home / Activity in Slack's left bar).
    private static func restoreTabs(_ labels: [String], in win: AXUIElement) {
        for label in labels {
            let shown = { AX.first(in: win, where: { AX.subrole($0) == "AXTabPanel" && AX.bestLabel($0) == label }) != nil }
            if shown() { continue }
            guard let tab = AX.first(in: win, where: { AX.subrole($0) == "AXTabButton" && AX.bestLabel($0) == label }),
                  let f = AX.frame(tab) else { continue }
            Log.write("Jump: switching back to tab \(label) first")
            trigger(TextLocator.Hit(frame: f, element: tab), in: win, reached: shown)
        }
    }

    // MARK: Triggering the target (no mouse movement, no keyboard)

    /// Tries in turn, checking after each step: AXPress → set selected → post the click straight to the app (the system cursor stays put).
    /// Stops once reached or once the target's state has changed, so a second trigger does not fold up what just expanded.
    @discardableResult
    static func trigger(_ hit: TextLocator.Hit, in win: AXUIElement, reached: () -> Bool) -> Bool {
        let before = state(hit.element, win)
        let changed = { state(hit.element, win) != before }
        if let el = hit.element {
            let actions = AX.actions(el)
            Log.write("Jump: trigger role=\(AX.role(el) ?? "") actions=\(actions.joined(separator: ","))")
            // When the target has no AXPress of its own (VS Code tree rows), press the child inside it that has one.
            let pressable = actions.contains(kAXPressAction) ? el : pressableDescendant(of: el)
            if let pressable, AX.perform(pressable, kAXPressAction) {
                usleep(500_000)
                if reached() { Log.write("Jump: AXPress worked"); return true }
                if changed() { Log.write("Jump: state changed after AXPress"); return false }
            }
            if AX.set(el, kAXSelectedAttribute, kCFBooleanTrue) {
                usleep(400_000)
                if reached() { Log.write("Jump: set selected worked"); return true }
                if changed() { return false }
            }
            // Move the accessibility focus onto the target and, once the focus is confirmed there, send a single Return / space to this app only.
            // No key while the focus is elsewhere, so nothing lands in a text field.
            if let pid = AX.pid(el), AX.set(el, kAXFocusedAttribute, kCFBooleanTrue) {
                usleep(150_000)
                if focusIs(el) {
                    // Space works for buttons and list rows alike; Return only for links, buttons and menu items (in a tree, Return means "rename").
                    var keys = [KeyCode.space]
                    if ["AXLink", kAXButtonRole, kAXMenuItemRole, kAXRadioButtonRole].contains(AX.role(el) ?? "") { keys.append(KeyCode.returnKey) }
                    for key in keys {
                        guard focusIs(el) else { break }
                        postKey(key, pid: pid)
                        usleep(500_000)
                        if reached() { Log.write("Jump: focus + key worked"); return true }
                        if changed() { Log.write("Jump: state changed after the key"); return false }
                    }
                } else {
                    Log.write("Jump: focus did not land on the target, no key sent")
                }
            }
        }
        guard let pid = AX.pid(win) else { return false }
        let p = hit.element.flatMap(clickPoint) ?? CGPoint(x: hit.frame.midX, y: hit.frame.midY)
        postClick(at: p, pid: pid, windowID: AX.windowID(win))
        usleep(500_000)
        return reached()
    }

    /// The first child inside el (up to 4 levels deep) that supports AXPress, largest area preferred.
    private static func pressableDescendant(of el: AXUIElement) -> AXUIElement? {
        var best: (AXUIElement, CGFloat)?
        var queue: [(AXUIElement, Int)] = [(el, 0)]
        var head = 0
        while head < queue.count && head < 80 {
            let (e, d) = queue[head]
            head += 1
            if d > 0, AX.actions(e).contains(kAXPressAction) {
                let area = AX.frame(e).map { $0.width * $0.height } ?? 0
                if area > (best?.1 ?? -1) { best = (e, area) }
            }
            if d < 4 { for c in AX.children(e) { queue.append((c, d + 1)) } }
        }
        return best?.0
    }

    /// Whether the app's current accessibility focus is el (or inside el).
    private static func focusIs(_ el: AXUIElement) -> Bool {
        guard let pid = AX.pid(el), let f = AX.element(AX.app(pid), kAXFocusedUIElementAttribute) else { return false }
        return AX.isSelfOrAncestor(el, of: f)
    }

    enum KeyCode { static let returnKey: CGKeyCode = 36, space: CGKeyCode = 49 }

    /// Posts a single key to that app's process only (not through the system input queue).
    private static func postKey(_ key: CGKeyCode, pid: pid_t) {
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)?.postToPid(pid)
            usleep(30_000)
        }
    }

    /// A rough fingerprint of whether the target reacted: window title + the target's selected / expanded / value.
    private static func state(_ el: AXUIElement?, _ win: AXUIElement) -> String {
        var parts = [AX.title(win) ?? ""]
        if let el {
            for a in [kAXSelectedAttribute, kAXExpandedAttribute, kAXValueAttribute] {
                parts.append(AX.raw(el, a).map { "\($0)" } ?? "-")
            }
        }
        return parts.joined(separator: "|")
    }

    /// The click point on the element: left of centre, clear of the small "pin / archive / more" buttons at the end of a row; hit tested to confirm it really lands on the element.
    private static func clickPoint(_ el: AXUIElement) -> CGPoint? {
        guard let f = AX.frame(el), f.width > 0, f.height > 0 else { return nil }
        var candidates = [CGPoint(x: f.midX, y: f.midY)]
        if f.width > 120 { candidates.insert(CGPoint(x: f.minX + min(f.width * 0.3, 90), y: f.midY), at: 0) }
        let axApp = AX.pid(el).map(AX.app)
        return candidates.first { p in
            guard let axApp, let hit = AX.elementAt(axApp, p) else { return false }
            return AX.isSelfOrAncestor(el, of: hit)
        } ?? candidates[0]
    }

    /// Posts one left click straight to the app's process: not through the system mouse, the cursor stays put, the user's own actions are undisturbed.
    static func postClick(at p: CGPoint, pid: pid_t, windowID: CGWindowID?) {
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { continue }
            e.setIntegerValueField(.mouseEventClickState, value: 1)
            if let w = windowID {
                e.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(w))
                e.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(w))
            }
            e.postToPid(pid)
            usleep(50_000)
        }
        Log.write("Jump: posting click (\(Int(p.x)),\(Int(p.y))) pid=\(pid)")
    }

    /// Posts a scroll event straight to the app's process (the cursor stays put).
    static func postScroll(at p: CGPoint, dy: Int32, pid: pid_t, windowID: CGWindowID?) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0) else { return }
        e.location = p
        if let w = windowID {
            e.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(w))
            e.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(w))
        }
        e.postToPid(pid)
        usleep(40_000)
    }
}
