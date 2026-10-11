import AppKit
import ApplicationServices

/// Browser tabs: reads tab URLs and switches tabs through the browser's own AppleScript interface.
/// When ⌥ mode points at a tab button in the tab bar, its index in the bar tells same-named tabs apart.
enum BrowserTabs {
    /// ⌥ hover: the tab button under the mouse (Chrome covers the tab bar with a transparent AXGroup, hit testing cannot reach it, so search by coordinates).
    static func pick(_ ctx: PickContext) -> PickedElement? {
        guard let tab = ctx.deepest.flatMap(tabButton(containing:)) ?? ctx.axWindow.flatMap({ tabButton(in: $0, at: ctx.point) })
        else { return nil }
        var p = PickedElement(element: tab)
        p.text = nil
        p.tabPosition = position(ofTab: tab)
        return p
    }

    /// Bind: resolves the tab the mouse points at (or the window's current tab).
    static func resolve(_ t: HoverTarget) -> BrowserTab? {
        let tabs = BrowserScripting.listTabs(t.bundleID)
        let pos = t.picked?.tabPosition
        Log.write("Browser tabs read \(t.bundleID) count=\(tabs.count) pos=\(pos.map(String.init) ?? "-")")
        guard !tabs.isEmpty else { return nil }

        // First decide which browser window: the AppleScript window whose bounds best match the picked window.
        var inWindow = tabs
        let byWindow = Dictionary(grouping: tabs, by: { $0.windowIndex })
        let scored = byWindow.compactMap { (wi, ts) -> (Int, CGFloat)? in
            guard let b = ts.first?.windowBounds else { return nil }
            return (wi, overlap(b, t.windowFrame))
        }
        if let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0.5, let ts = byWindow[best.0] {
            inWindow = ts
        } else if byWindow.count > 1 {
            let byTitle = byWindow.values.compactMap { ts -> ([BrowserTab], Double)? in
                guard let a = ts.first(where: { $0.isActive }) else { return nil }
                return (ts, TitleMatch.score(t.windowTitle, a.title))
            }.max { $0.1 < $1.1 }
            if let byTitle, byTitle.1 >= 0.3 { inWindow = byTitle.0 }
        }

        // ⌥ picked a tab: take it by index, and count it only when the title matches (a collapsed group could shift the indices).
        if t.element != nil, let label = t.elementLabel {
            if let pos, let tab = inWindow.first(where: { $0.tabIndex == pos }), TitleMatch.score(tab.title, label) >= 0.6 {
                return tab
            }
            let p = pos ?? 0
            let best = inWindow
                .map { ($0, TitleMatch.score($0.title, label)) }
                .filter { $0.1 >= 0.6 }
                .max { a, b in a.1 != b.1 ? a.1 < b.1 : abs(a.0.tabIndex - p) > abs(b.0.tabIndex - p) }
            if let best { return best.0 }
        }
        return inWindow.first { $0.isActive } ?? tabs.first { $0.isActive }
    }

    /// Bind without AppleScript (no dictionary, or the Automation grant was refused): the page URL the window's web area reports.
    /// A tab button picked with ⌥ counts only when it is the page showing, since the web area belongs to the current tab.
    static func pageFromAX(_ t: HoverTarget) -> (url: String, title: String)? {
        guard let win = t.axWindow, let page = pageURL(in: win, of: AX.app(t.window.pid)) else { return nil }
        var title = page.title ?? ""
        if title.isEmpty { title = windowTitleWithoutApp(t.windowTitle, appName: t.appName) }
        if t.picked?.tabPosition != nil || t.elementSubrole == "AXTabButton" {
            guard let label = t.elementLabel, TitleMatch.score(label, title) >= 0.6 else { return nil }
        }
        Log.write("Browser page read from the web area \(t.bundleID) url=\(page.url)")
        return (page.url, title)
    }

    /// The http(s) URL and title of the window's web area. Read plainly first; Chromium shows AXURL only in full accessibility mode, so retry briefly with it on.
    static func pageURL(in win: AXUIElement, of app: AXUIElement) -> (url: String, title: String?)? {
        let read: () -> (url: String, title: String?)? = {
            guard let web = AX.first(in: win, maxNodes: 600, where: { AX.role($0) == "AXWebArea" && isWebURL(AX.string($0, kAXURLAttribute)) }),
                  let url = AX.string(web, kAXURLAttribute) else { return nil }
            let title = AX.title(web)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (url, title.flatMap { $0.isEmpty ? nil : $0 })
        }
        if let page = read() { return page }
        return AX.withEnhancedUI(app) {
            for _ in 0..<4 {
                if let page = read() { return page }
                Thread.sleep(forTimeInterval: 0.25)
            }
            return nil
        }
    }

    private static func isWebURL(_ s: String?) -> Bool {
        guard let s = s?.lowercased() else { return false }
        return s.hasPrefix("http://") || s.hasPrefix("https://")
    }

    /// "Page title - Google Chrome" / "Page title — Mozilla Firefox" → "Page title"
    static func windowTitleWithoutApp(_ title: String, appName: String) -> String {
        for sep in [" - ", " — ", " – "] where title.hasSuffix(sep + appName) {
            return String(title.dropLast(sep.count + appName.count))
        }
        return title
    }

    /// Jump: finds the tab by URL and switches to it; reopens the URL if it was closed.
    /// Without AppleScript (no dictionary, or the Automation grant was refused): a window showing the page, else the URL is handed to the browser through the system.
    static func restore(bundleID: String, url: String, title: String, app: NSRunningApplication) -> RestoreOutcome {
        let scripted = BrowserScripting.supports(bundleID)
        let tabs = scripted ? BrowserScripting.listTabs(bundleID) : []
        if let t = BrowserScripting.bestMatch(in: tabs, url: url, title: title) {
            BrowserScripting.activate(bundleID, windowIndex: t.windowIndex, tabIndex: t.tabIndex)
            ContextRestore.activate(app)
            ContextRestore.raiseWindow(app: app, attempts: 4) { windows, axApp in
                WindowMatch.byTitle(windows, [t.title], threshold: 0.5) ?? WindowMatch.focused(axApp)
            }
            return .exact
        }
        if scripted, BrowserScripting.open(bundleID, url: url) {
            ContextRestore.activate(app)
            return .reopened
        }
        if AX.isTrusted, !title.isEmpty {
            let axApp = AX.app(app.processIdentifier)
            if let win = ContextRestore.raiseWindow(app: app, attempts: 1, choose: { windows, _ in
                WindowMatch.byTitle(windows, [title], threshold: 0.5)
            }) {
                ContextRestore.activate(app)
                let shown = pageURL(in: win, of: axApp)?.url
                Log.write("Jump: browser window by title, web area url=\(shown ?? "-")")
                guard let shown else { return .unverified }
                if BrowserScripting.normalizeURL(shown) == BrowserScripting.normalizeURL(url) { return .exact }
                // Same title, another page: fall through and open the URL.
            }
        }
        guard let u = URL(string: url) else { return .appOnly }
        Log.write("Jump: opening the URL through the system")
        ContextRestore.open(u, with: app)
        ContextRestore.activate(app)
        return .reopened
    }

    // MARK: Tab bar

    private static func tabButton(containing el: AXUIElement) -> AXUIElement? {
        var cur: AXUIElement? = el
        for _ in 0..<4 {
            guard let c = cur else { return nil }
            if AX.subrole(c) == "AXTabButton" { return c }
            cur = AX.parent(c)
        }
        return nil
    }

    /// Walks only the browser shell (skipping the AXWebArea web content); few nodes, cheap enough to call while hovering.
    private static func tabButton(in window: AXUIElement, at p: CGPoint) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var head = 0
        while head < queue.count && head < 1500 {
            let (el, depth) = queue[head]
            head += 1
            let role = AX.role(el)
            if role == "AXWebArea" { continue }
            if AX.subrole(el) == "AXTabButton" {
                if let f = AX.frame(el), f.contains(p) { return el }
                continue
            }
            if depth > 0, role != kAXTabGroupRole, let f = AX.frame(el), f.width > 0, !f.contains(p) { continue }
            if depth < 14 { for c in AX.children(el) { queue.append((c, depth + 1)) } }
        }
        return nil
    }

    private static func position(ofTab tab: AXUIElement) -> Int? {
        guard let parent = AX.parent(tab) else { return nil }
        let tabs = AX.children(parent).filter { AX.subrole($0) == "AXTabButton" }
        return tabs.firstIndex { CFEqual($0, tab) }.map { $0 + 1 }
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull else { return 0 }
        let u = a.union(b)
        return (i.width * i.height) / max(u.width * u.height, 1)
    }
}
