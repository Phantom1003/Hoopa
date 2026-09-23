import AppKit
import ApplicationServices

/// Finds the target in the accessibility tree by "the text visible on screen"; when it is not showing, scrolls the column the target lives in to find it
/// (scroll events are posted straight to the app, the cursor stays put). No dependence on the app's internal IDs, URLs or search.
enum TextLocator {
    struct Hit {
        let frame: CGRect
        let element: AXUIElement?
    }

    /// Finds the target whose text is text in the window. region is the target's column (screen coordinates), used for preference and scrolling.
    static func find(_ text: String, in win: AXUIElement, region: CGRect?, scroll: Bool) -> Hit? {
        let first = attempt(text, win, region)
        if let h = first.hit { return h }
        // Not in that column but the same text elsewhere (a name mentioned in Slack's activity feed, say): scroll that column first and use the other only as a last resort.
        let fallback = first.outside
        guard scroll, let region, let pid = AX.pid(win) else { return fallback }
        let p = CGPoint(x: region.midX, y: region.midY)
        let wid = AX.windowID(win)
        let scrollWheel = { (dy: Int32) in ContextRestore.postScroll(at: p, dy: dy, pid: pid, windowID: wid) }

        // Scroll to the top first, then page down; when the content stops changing the bottom is reached.
        for _ in 0..<8 { scrollWheel(1500) }
        usleep(350_000)
        var last = attempt(text, win, region)
        if let h = last.hit { return h }
        for i in 0..<20 {
            scrollWheel(-Int32(max(region.height * 0.6, 120)))
            usleep(350_000)
            let cur = attempt(text, win, region)
            if let h = cur.hit {
                Log.write("Text locate: found after scrolling \(i + 1) page(s)")
                return h
            }
            if cur.signature == last.signature { break }
            last = cur
        }
        Log.write("Text locate: \"\(text)\" not found even at the bottom of that column\(fallback == nil ? "" : ", using the same text outside the column")")
        return fallback
    }

    /// Confirm after triggering: the target became selected, or the text appears away from the click position (title bar, conversation header), or the window title contains it.
    static func verify(_ text: String, in win: AXUIElement, clicked: Hit) -> Bool {
        if let el = clicked.element, AX.bool(el, kAXSelectedAttribute) == true { return true }
        if let t = AX.title(win), matches(t, text) || t.contains(text) { return true }
        return candidates(text, win).contains { !$0.frame.intersects(clicked.frame.insetBy(dx: -2, dy: -2)) }
    }

    /// Confirm after opening a link: the window title contains the text, or it is visible in the window.
    static func verifyPresence(_ text: String, in win: AXUIElement) -> Bool {
        if let t = AX.title(win), matches(t, text) || t.contains(text) { return true }
        return !candidates(text, win).isEmpty
    }

    /// Relative position (0…1) → the column's screen region in the current window (slightly wider, the full window height).
    static func column(_ rel: [Double]?, in win: AXUIElement) -> CGRect? {
        guard let rel, rel.count == 4, let f = AX.frame(win) else { return nil }
        let x = f.minX + CGFloat(rel[0]) * f.width, w = CGFloat(rel[2]) * f.width
        return CGRect(x: x - 30, y: f.minY, width: w + 60, height: f.height)
    }

    // MARK: Internals

    /// One search: hit = the match inside the column (or anywhere when there is no column); outside = a match outside it; signature tells whether scrolling reached the bottom.
    private static func attempt(_ text: String, _ win: AXUIElement, _ region: CGRect?) -> (hit: Hit?, outside: Hit?, signature: String) {
        let hits = candidates(text, win)
        guard let region else { return (hits.first, nil, "") }
        let isInside: (Hit) -> Bool = { region.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        let outside = hits.filter { !isInside($0) }.min { abs($0.frame.midX - region.midX) < abs($1.frame.midX - region.midX) }
        return (hits.first(where: isInside), outside, signature(win, region))
    }

    /// Elements in the accessibility tree whose text matches and that lie in the window's visible area (taking the clickable ancestor).
    private static func candidates(_ text: String, _ win: AXUIElement) -> [Hit] {
        guard let wf = AX.frame(win) else { return [] }
        var out: [Hit] = []
        var queue: [(AXUIElement, Int)] = [(win, 0)]
        var head = 0
        while head < queue.count && head < 5000 && out.count < 8 {
            let (el, depth) = queue[head]
            head += 1
            let role = AX.role(el)
            let s = role == kAXStaticTextRole ? AX.string(el, kAXValueAttribute) : AX.string(el, kAXTitleAttribute) ?? AX.string(el, kAXDescriptionAttribute)
            if let s, matches(s, text), let f = AX.frame(el), f.width > 0, f.height > 0, wf.contains(CGPoint(x: f.midX, y: f.midY)) {
                let target = AX.actionableAncestor(of: el, within: win) ?? el
                out.append(Hit(frame: AX.frame(target) ?? f, element: target))
                continue
            }
            if depth < 40 { for c in AX.children(el) { queue.append((c, depth + 1)) } }
        }
        return out
    }

    /// A signature of what the column currently shows (the texts of the elements hit along the column's centre line).
    private static func signature(_ win: AXUIElement, _ region: CGRect) -> String {
        guard let app = AX.pid(win).map(AX.app) else { return "" }
        return stride(from: region.minY + 20, to: region.maxY, by: 40).compactMap { y in
            AX.elementAt(app, CGPoint(x: region.midX, y: y)).flatMap(AX.bestLabel)
        }.joined(separator: "|")
    }

    /// Whether two texts mean the same target: nearly identical, or truncated to "prefix…" in a list.
    static func matches(_ candidate: String, _ target: String) -> Bool {
        let c = candidate.trimmingCharacters(in: .whitespaces), t = target.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty, !t.isEmpty else { return false }
        if c == t || TitleMatch.score(c, t) >= 0.9 { return true }
        for ell in ["…", "..."] where c.hasSuffix(ell) {
            let prefix = String(c.dropLast(ell.count)).trimmingCharacters(in: .whitespaces)
            if prefix.count >= 4, t.hasPrefix(prefix) { return true }
        }
        return false
    }
}
